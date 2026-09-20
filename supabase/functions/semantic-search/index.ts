import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, handleCors } from "../_shared/cors.ts";
import { generateEmbedding } from "../_shared/gemini.ts";

/**
 * Token-Bucket In-Memory Rate Limiter
 * Provides zero-latency burst guardrails per user_id.
 */
interface Bucket {
  tokens: number;
  lastRefillMs: number;
}

class TokenBucketRateLimiter {
  private buckets = new Map<string, Bucket>();
  private readonly capacity: number;
  private readonly refillTokensPerMs: number;

  constructor(capacity = 30, refillTokensPerSecond = 0.5) {
    this.capacity = capacity;
    this.refillTokensPerMs = refillTokensPerSecond / 1000;
  }

  public consume(
    userId: string,
    tokensRequested = 1
  ): { allowed: boolean; remainingTokens: number; retryAfterSeconds: number } {
    const now = Date.now();
    let bucket = this.buckets.get(userId);

    if (!bucket) {
      bucket = { tokens: this.capacity, lastRefillMs: now };
      this.buckets.set(userId, bucket);
    } else {
      const elapsedMs = Math.max(0, now - bucket.lastRefillMs);
      bucket.tokens = Math.min(
        this.capacity,
        bucket.tokens + elapsedMs * this.refillTokensPerMs
      );
      bucket.lastRefillMs = now;
    }

    if (this.buckets.size > 2000) {
      const cutoff = Date.now() - 3600_000;
      for (const [key, b] of this.buckets.entries()) {
        if (b.lastRefillMs < cutoff) {
          this.buckets.delete(key);
        }
      }
    }

    if (bucket.tokens >= tokensRequested) {
      bucket.tokens -= tokensRequested;
      return {
        allowed: true,
        remainingTokens: Math.floor(bucket.tokens),
        retryAfterSeconds: 0,
      };
    }

    const deficit = tokensRequested - bucket.tokens;
    const retryAfterMs = Math.ceil(deficit / this.refillTokensPerMs);
    const retryAfterSeconds = Math.max(1, Math.ceil(retryAfterMs / 1000));

    return {
      allowed: false,
      remainingTokens: Math.floor(bucket.tokens),
      retryAfterSeconds,
    };
  }
}

const rateLimiter = new TokenBucketRateLimiter(30, 0.5);

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// Supabase Admin Client using Service Role Key for telemetry logging
const supabaseAdmin = createClient(supabaseUrl, supabaseServiceRoleKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
});

interface SemanticSearchRequest {
  query: string;
  match_threshold?: number;
  match_count?: number;
}

export interface SemanticSearchResultItem {
  id: string;
  title: string;
  content: string;
  category: string;
  tags: string[];
  media_url: string | null;
  client_created_at: string | null;
  similarity: number;
}

Deno.serve(async (req: Request) => {
  // 1. Handle CORS Preflight
  const corsResponse = handleCors(req);
  if (corsResponse) {
    return corsResponse;
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: `Method ${req.method} not allowed` }),
      {
        status: 405,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  const startTime = performance.now();
  let authenticatedUserId: string | null = null;

  // Timeout guardrail: 25 seconds execution deadline
  const timeoutController = new AbortController();
  const timeoutId = setTimeout(() => {
    timeoutController.abort(new Error("Function execution timed out (25s deadline)"));
  }, 25_000);

  try {
    // 2. Authenticate Request via Supabase Auth JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({
          error: "Unauthorized: Missing or malformed Authorization header. Bearer token required.",
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const token = authHeader.replace("Bearer ", "").trim();

    // User-scoped Supabase client that carries user JWT for RLS and auth.uid()
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: {
        headers: { Authorization: authHeader },
      },
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    });

    const {
      data: { user },
      error: userAuthError,
    } = await userClient.auth.getUser(token);

    if (userAuthError || !user) {
      return new Response(
        JSON.stringify({
          error: "Unauthorized: Invalid or expired authentication token.",
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    authenticatedUserId = user.id;

    // 3. Rate Limiting Guardrail
    const rateLimitCheck = rateLimiter.consume(authenticatedUserId, 1);
    if (!rateLimitCheck.allowed) {
      console.warn(
        `[Rate Limit] User ${authenticatedUserId} exceeded rate limit. Retry after ${rateLimitCheck.retryAfterSeconds}s.`
      );
      return new Response(
        JSON.stringify({
          error: "Rate limit exceeded. Too many requests. Please wait a moment.",
          retry_after_seconds: rateLimitCheck.retryAfterSeconds,
        }),
        {
          status: 429,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
            "Retry-After": rateLimitCheck.retryAfterSeconds.toString(),
          },
        }
      );
    }

    // 4. Validate and Parse Input Payload
    let body: SemanticSearchRequest;
    try {
      body = await req.json();
    } catch (_parseErr) {
      return new Response(
        JSON.stringify({ error: "Invalid JSON body in request." }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const query = typeof body?.query === "string" ? body.query.trim() : "";
    if (!query) {
      return new Response(
        JSON.stringify({
          error: "Validation failed: 'query' field is required and cannot be empty.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    if (query.length > 1000) {
      return new Response(
        JSON.stringify({
          error: "Validation failed: Query exceeds maximum allowed length of 1000 characters.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Match threshold defaults to 0.3 (lower bound 0.0, upper bound 1.0)
    const matchThreshold =
      typeof body.match_threshold === "number"
        ? Math.max(0, Math.min(1, body.match_threshold))
        : 0.3;

    // Match count defaults to 10 (capped between 1 and 50)
    const matchCount =
      typeof body.match_count === "number"
        ? Math.max(1, Math.min(50, Math.round(body.match_count)))
        : 10;

    console.info(
      `[Semantic Search] Processing query for user ${authenticatedUserId}: "${query.slice(0, 50)}..." (threshold: ${matchThreshold}, count: ${matchCount})`
    );

    // 5. Generate Query Dense Embedding (768 dimensions) via Gemini API
    const signal = timeoutController.signal;
    const embeddingResult = await generateEmbedding(null, query, signal);

    // 6. Vector Similarity Search via PostgreSQL RPC `match_memories_v2`
    // with fallback to legacy `match_memories` if needed
    let rawMatches: any[] | null = null;
    let rpcError: any = null;

    const rpcV2Response = await userClient.rpc("match_memories_v2", {
      query_embedding: embeddingResult.embedding,
      match_threshold: matchThreshold,
      match_count: matchCount,
    });

    if (!rpcV2Response.error) {
      rawMatches = rpcV2Response.data;
    } else {
      console.warn(
        `[Semantic Search Notice] match_memories_v2 error: ${rpcV2Response.error.message}. Attempting legacy fallback...`
      );
      const rpcV1Response = await userClient.rpc("match_memories", {
        query_embedding: embeddingResult.embedding,
        match_threshold: matchThreshold,
        match_count: matchCount,
      });
      rawMatches = rpcV1Response.data;
      rpcError = rpcV1Response.error;
    }

    if (rpcError) {
      console.error(
        `[Semantic Search RPC Error] Failed to execute vector search: ${rpcError.message}`
      );
      throw new Error(`Database vector search failed: ${rpcError.message}`);
    }

/**
 * Generic Semantic Relevance Filter
 *
 * In Gemini 768-d dense embedding space (gemini-embedding-2-preview), unrelated texts
 * typically exhibit cosine similarities between ~0.48 and ~0.56.
 *
 * This function applies a generic, query-agnostic relevance filtering strategy:
 * 1. Absolute noise floor: Rejects any match below MIN_SIMILARITY_THRESHOLD (0.57).
 *    If the top-ranked match does not reach this floor, the query has no relevant matches.
 *    Set to 0.57 to stay strictly above the ~0.48–0.56 noise ceiling while avoiding
 *    false negatives for cross-lingual (Roman Urdu), short-query, or long-document matches.
 * 2. Dynamic relative cutoff: Retains all matches within MAX_DROP_FROM_TOP (0.18)
 *    of the top score, clamped to the noise floor.
 * 3. Preserves descending similarity ordering.
 */
export function filterRelevantSemanticResults<
  T extends {
    similarity: number;
    title?: string;
    content?: string;
    category?: string;
    tags?: string[];
  }
>(
  items: T[],
  minThreshold = 0.57,
  maxDropFromTop?: number,
  query?: string
): T[] {
  if (!items || items.length === 0) {
    return [];
  }

  // Ensure items are sorted descending by similarity
  const sorted = [...items].sort((a, b) => b.similarity - a.similarity);

  const topScore = sorted[0].similarity;
  const effectiveMin = Math.max(minThreshold, 0.57);

  // If even the best match does not meet the minimum relevance threshold, return empty
  if (topScore < effectiveMin) {
    return [];
  }

  const margin = topScore - effectiveMin;
  const adaptiveDrop =
    maxDropFromTop !== undefined
      ? maxDropFromTop
      : Math.max(0.03, 0.03 + 0.25 * margin);
  const dynamicCutoff = Math.max(effectiveMin, topScore - adaptiveDrop);

  const queryTokens: string[] = query
    ? query
        .toLowerCase()
        .replace(/[^\w\s]/g, " ")
        .split(/\s+/)
        .filter((t) => t.length >= 2)
    : [];

  return sorted.filter((item) => {
    if (item.similarity < effectiveMin) {
      return false;
    }

    if (item.similarity >= dynamicCutoff) {
      return true;
    }

    if (queryTokens.length > 0) {
      const titleLower = (item.title || "").toLowerCase();
      const contentLower = (item.content || "").toLowerCase();
      const categoryLower = (item.category || "").toLowerCase();
      const tagsLower = Array.isArray(item.tags)
        ? item.tags.map((t) => String(t).toLowerCase())
        : [];

      const hasTokenMatch = queryTokens.some(
        (t) =>
          titleLower.includes(t) ||
          contentLower.includes(t) ||
          categoryLower.includes(t) ||
          tagsLower.some((tag) => tag.includes(t))
      );

      if (hasTokenMatch) {
        const hybridCutoff = Math.max(effectiveMin, topScore - 0.12);
        return item.similarity >= hybridCutoff;
      }
    }

    return false;
  });
}

    // 7. Enforce multi-tenant user isolation defense-in-depth and format results
    const rawResults: SemanticSearchResultItem[] = (rawMatches || [])
      .filter((rec: any) => !rec.user_id || rec.user_id === authenticatedUserId)
      .map((rec: any) => ({
        id: String(rec.id),
        title: rec.title ? String(rec.title) : "Untitled Memory",
        content: String(rec.content ?? ""),
        category: rec.category ? String(rec.category) : "General",
        tags: Array.isArray(rec.tags) ? rec.tags : [],
        media_url: rec.media_url ? String(rec.media_url) : null,
        client_created_at: rec.client_created_at
          ? String(rec.client_created_at)
          : (rec.created_at ? String(rec.created_at) : null),
        similarity:
          typeof rec.similarity === "number"
            ? Math.round(rec.similarity * 10000) / 10000
            : 0,
      }));

    // 8. Generic Semantic Relevance Filtering
    const results = filterRelevantSemanticResults(
      rawResults,
      matchThreshold,
      undefined,
      query
    );

    const executionTimeMs = Math.round(performance.now() - startTime);

    // 8. Telemetry Logging into public.ai_usage_logs
    try {
      await supabaseAdmin.from("ai_usage_logs").insert({
        user_id: authenticatedUserId,
        feature_name: "semantic_search",
        model_used: embeddingResult.modelUsed,
        prompt_tokens: 0,
        completion_tokens: 0,
        total_tokens: 0,
        execution_time_ms: executionTimeMs,
      });
    } catch (telemetryErr) {
      console.warn(
        `[Telemetry Warning] Failed to log AI usage for search query "${query.slice(0, 30)}":`,
        telemetryErr
      );
    }

    console.info(
      `[Semantic Search Success] Returned ${results.length} ranked memories in ${executionTimeMs}ms for user ${authenticatedUserId}. Model: ${embeddingResult.modelUsed}`
    );

    return new Response(
      JSON.stringify({
        success: true,
        query,
        count: results.length,
        threshold: matchThreshold,
        results,
        execution_time_ms: executionTimeMs,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error: any) {
    const isTimeout =
      error?.name === "AbortError" ||
      String(error?.message).toLowerCase().includes("timed out");

    console.error("[Semantic Search Failure] Exception processing request:", error);

    const statusCode = isTimeout ? 504 : 500;
    return new Response(
      JSON.stringify({
        success: false,
        error: error?.message || "Internal server error during semantic search",
        is_timeout: isTimeout,
      }),
      {
        status: statusCode,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } finally {
    clearTimeout(timeoutId);
  }
});
