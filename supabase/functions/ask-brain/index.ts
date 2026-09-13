import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, handleCors } from "../_shared/cors.ts";
import {
  generateEmbedding,
  synthesizeAnswer,
  GroundedMemoryItem,
} from "../_shared/gemini.ts";

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

interface AskBrainRequest {
  query: string;
  matchThreshold?: number;
  matchCount?: number;
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
    let body: AskBrainRequest;
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

    // Match threshold defaults to 0.3 (lower bound 0.0, upper bound 1.0)
    const matchThreshold =
      typeof body.matchThreshold === "number"
        ? Math.max(0, Math.min(1, body.matchThreshold))
        : 0.3;

    // Match count defaults to 5 (capped between 1 and 20)
    const matchCount =
      typeof body.matchCount === "number"
        ? Math.max(1, Math.min(20, Math.round(body.matchCount)))
        : 5;

    console.info(
      `[Ask Brain] Processing query for user ${authenticatedUserId}: "${query.slice(0, 50)}..." (threshold: ${matchThreshold}, count: ${matchCount})`
    );

    // 5. Generate Query Dense Embedding (768 dimensions)
    const signal = timeoutController.signal;
    const embeddingResult = await generateEmbedding(null, query, signal);

    // 6. Vector Similarity Search via PostgreSQL RPC `match_memories`
    const { data: rawMatches, error: rpcError } = await userClient.rpc(
      "match_memories",
      {
        query_embedding: embeddingResult.embedding,
        match_threshold: matchThreshold,
        match_count: matchCount,
      }
    );

    if (rpcError) {
      console.error(
        `[Ask Brain RPC Error] Failed to execute match_memories: ${rpcError.message}`
      );
      throw new Error(`Database similarity search failed: ${rpcError.message}`);
    }

    // Enforce multi-tenant user isolation defense-in-depth
    const matchedMemories: GroundedMemoryItem[] = (rawMatches || [])
      .filter((rec: any) => !rec.user_id || rec.user_id === authenticatedUserId)
      .map((rec: any) => ({
        id: String(rec.id),
        title: rec.title ? String(rec.title) : "Untitled Note",
        content: String(rec.content ?? ""),
        category: rec.category ? String(rec.category) : undefined,
        tags: Array.isArray(rec.tags) ? rec.tags : undefined,
        client_created_at: rec.client_created_at
          ? String(rec.client_created_at)
          : undefined,
        similarity:
          typeof rec.similarity === "number" ? rec.similarity : undefined,
      }));

    // 7. Guardrail: If no relevant memories match the threshold
    if (matchedMemories.length === 0) {
      const executionTimeMs = Math.round(performance.now() - startTime);

      try {
        await supabaseAdmin.from("ai_usage_logs").insert({
          user_id: authenticatedUserId,
          feature_name: "ask_brain",
          model_used: embeddingResult.modelUsed,
          prompt_tokens: 0,
          completion_tokens: 0,
          total_tokens: 0,
          execution_time_ms: executionTimeMs,
        });
      } catch (telemetryErr) {
        console.warn(
          "[Telemetry Warning] Failed to log zero-match usage:",
          telemetryErr
        );
      }

      return new Response(
        JSON.stringify({
          answer:
            "I couldn't find any relevant memories or notes in your Second Brain related to your question.",
          sources: [],
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 8. RAG Grounding & Answer Synthesis via Gemini 3.8 Flash
    const synthesisResult = await synthesizeAnswer(
      query,
      matchedMemories,
      signal
    );

    const executionTimeMs = Math.round(performance.now() - startTime);

    // 9. Telemetry Logging into public.ai_usage_logs
    try {
      await supabaseAdmin.from("ai_usage_logs").insert({
        user_id: authenticatedUserId,
        feature_name: "ask_brain",
        model_used: synthesisResult.modelUsed,
        prompt_tokens: synthesisResult.usage.promptTokens,
        completion_tokens: synthesisResult.usage.completionTokens,
        total_tokens: synthesisResult.usage.totalTokens,
        execution_time_ms: executionTimeMs,
      });
    } catch (telemetryErr) {
      console.warn(
        `[Telemetry Warning] Failed to log AI usage for query "${query.slice(0, 30)}":`,
        telemetryErr
      );
    }

    // 10. Format structured response
    const sources = matchedMemories.map((m) => ({
      id: m.id,
      title: m.title || "Untitled Note",
      similarity:
        typeof m.similarity === "number"
          ? Math.round(m.similarity * 1000) / 1000
          : 0,
    }));

    console.info(
      `[Ask Brain Success] Query answered in ${executionTimeMs}ms with ${sources.length} sources. Model: ${synthesisResult.modelUsed}`
    );

    return new Response(
      JSON.stringify({
        answer: synthesisResult.answer,
        sources,
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

    console.error("[Ask Brain Failure] Exception processing request:", error);

    const statusCode = isTimeout ? 504 : 500;
    return new Response(
      JSON.stringify({
        error: error?.message || "Internal server error during ask-brain processing",
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
