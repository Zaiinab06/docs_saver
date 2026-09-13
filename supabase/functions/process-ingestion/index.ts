import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, handleCors } from "../_shared/cors.ts";
import {
  analyzeMemoryContent,
  generateEmbedding,
} from "../_shared/gemini.ts";

/**
 * Token-Bucket In-Memory Rate Limiter
 * Provides zero-latency guardrails per user_id.
 */
interface Bucket {
  tokens: number;
  lastRefillMs: number;
}

class TokenBucketRateLimiter {
  private buckets = new Map<string, Bucket>();
  private readonly capacity: number;
  private readonly refillTokensPerMs: number;

  /**
   * @param capacity Maximum burst capacity (tokens)
   * @param refillTokensPerSecond Token refill rate per second
   */
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

    // Periodic cleanup of stale buckets (older than 1 hour)
    if (this.buckets.size > 2000) {
      this.cleanup(3600_000);
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

  private cleanup(maxAgeMs: number) {
    const cutoff = Date.now() - maxAgeMs;
    for (const [key, bucket] of this.buckets.entries()) {
      if (bucket.lastRefillMs < cutoff) {
        this.buckets.delete(key);
      }
    }
  }
}

// Global rate limiter instance (30 capacity, 0.5 tokens/sec refill = 30/min sustained)
const rateLimiter = new TokenBucketRateLimiter(30, 0.5);

// Supabase Admin Client using Service Role Key (bypasses RLS for backend worker tasks)
const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceRoleKey =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const supabaseAdmin = createClient(supabaseUrl, supabaseServiceRoleKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
});

interface IngestionRecord {
  id: string;
  user_id: string;
  title?: string | null;
  content: string;
  image_base64?: string | null;
  mime_type?: string | null;
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
  let recordToProcess: IngestionRecord | null = null;
  let saveToDb = true;

  // Timeout guardrail: 25 seconds execution deadline
  const timeoutController = new AbortController();
  const timeoutId = setTimeout(() => {
    timeoutController.abort(new Error("Function execution timed out (25s deadline)"));
  }, 25_000);

  try {
    // 2. Parse Payload (supports pg_net webhook payload, direct POST payload, or memoryId)
    let body: any;
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

    // Extract record from { record: { ... } } or top-level object
    const rawRecord = body.record ?? body;
    saveToDb = body.save_to_db !== false && rawRecord.save_to_db !== false;

    let targetId = rawRecord.id ?? body.memoryId ?? body.id;
    let targetUserId = rawRecord.user_id ?? body.user_id;
    let targetTitle = rawRecord.title ?? body.title;
    let targetContent = rawRecord.content ?? body.content;
    const targetImageBase64 = rawRecord.image_base64 ?? body.image_base64;
    const targetMimeType = rawRecord.mime_type ?? body.mime_type;

    // If memoryId passed from background sync/bloc and content not in body, fetch from DB
    if (targetId && (!targetContent || !targetUserId)) {
      try {
        const { data: dbMem } = await supabaseAdmin
          .from("memories")
          .select("id, user_id, title, content")
          .eq("id", targetId)
          .maybeSingle();

        if (dbMem) {
          targetUserId = targetUserId || dbMem.user_id;
          targetTitle = targetTitle || dbMem.title;
          targetContent = targetContent || dbMem.content;
        }
      } catch (_) {
        // Fall through
      }
    }

    targetId = targetId ? String(targetId) : crypto.randomUUID();
    targetUserId = targetUserId ? String(targetUserId) : "anonymous_client";

    recordToProcess = {
      id: targetId,
      user_id: targetUserId,
      title: targetTitle ? String(targetTitle) : null,
      content: targetContent ? String(targetContent) : "",
      image_base64: targetImageBase64 ? String(targetImageBase64) : null,
      mime_type: targetMimeType ? String(targetMimeType) : null,
    };

    // 3. Token-Bucket Rate Limit Check
    const rateLimitCheck = rateLimiter.consume(recordToProcess.user_id, 1);
    if (!rateLimitCheck.allowed) {
      console.warn(
        `[Rate Limit] User ${recordToProcess.user_id} exceeded token bucket capacity. Retry after ${rateLimitCheck.retryAfterSeconds}s.`
      );
      return new Response(
        JSON.stringify({
          error: "Rate limit exceeded. Too many requests for this user.",
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

    console.info(
      `[Ingestion Started] Processing memory ${recordToProcess.id} for user ${recordToProcess.user_id} (saveToDb: ${saveToDb})`
    );

    // 4. Run Ingestion Prompt and Embedding Generation
    const signal = timeoutController.signal;

    // Fast Ingestion LLM (gemini-3.5-flash-lite)
    const analysisResult = await analyzeMemoryContent(
      {
        title: recordToProcess.title,
        content: recordToProcess.content,
        imageBase64: recordToProcess.image_base64,
        mimeType: recordToProcess.mime_type,
      },
      signal
    );

    const finalTitle = analysisResult.metadata.title;
    const finalCategory = analysisResult.metadata.category;
    const finalTags = analysisResult.metadata.tags;
    const finalSummary = analysisResult.metadata.summary;
    const finalEntities = analysisResult.metadata.entities;

    let embeddingValues: number[] | null = null;
    let embeddingModel: string | null = null;

    // If saving to DB, generate 768-d embedding and update public.memories
    if (saveToDb) {
      const embeddingResult = await generateEmbedding(
        finalTitle,
        recordToProcess.content,
        signal
      );
      embeddingValues = embeddingResult.embedding;
      embeddingModel = embeddingResult.modelUsed;

      const serverUpdatedAt = new Date().toISOString();
      const { error: updateError } = await supabaseAdmin
        .from("memories")
        .update({
          title: finalTitle,
          category: finalCategory,
          tags: finalTags,
          embedding: embeddingResult.embedding,
          ai_status: "processed",
          server_updated_at: serverUpdatedAt,
        })
        .eq("id", recordToProcess.id);

      if (updateError) {
        console.warn(
          `[Ingestion DB Notice] public.memories update skipped or row not found for ${recordToProcess.id}: ${updateError.message}`
        );
      }
    }

    const executionTimeMs = Math.round(performance.now() - startTime);

    // 5. Telemetry Logging into public.ai_usage_logs
    try {
      const { error: telemetryError } = await supabaseAdmin
        .from("ai_usage_logs")
        .insert({
          user_id: recordToProcess.user_id,
          feature_name: "ingestion",
          model_used: analysisResult.modelUsed,
          prompt_tokens: analysisResult.usage.promptTokens,
          completion_tokens: analysisResult.usage.completionTokens,
          total_tokens: analysisResult.usage.totalTokens,
          execution_time_ms: executionTimeMs,
        });

      if (telemetryError) {
        console.warn(
          `[Telemetry Warning] Failed to log AI usage for ${recordToProcess.id}: ${telemetryError.message}`
        );
      }
    } catch (telemetryErr) {
      console.warn("[Telemetry Error] Exception logging telemetry:", telemetryErr);
    }

    console.info(
      `[Ingestion Success] Memory ${recordToProcess.id} processed in ${executionTimeMs}ms. Model: ${analysisResult.modelUsed}`
    );

    return new Response(
      JSON.stringify({
        success: true,
        id: recordToProcess.id,
        title: finalTitle,
        category: finalCategory,
        tags: finalTags,
        summary: finalSummary,
        entities: finalEntities,
        embedding_dimensions: embeddingValues ? embeddingValues.length : null,
        embedding_model: embeddingModel,
        ai_status: "processed",
        execution_time_ms: executionTimeMs,
      }),
      {
        status: 200,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
        },
      }
    );
  } catch (error: any) {
    const isTimeout =
      error?.name === "AbortError" ||
      String(error?.message).toLowerCase().includes("timed out");

    console.error(
      `[Ingestion Failure] Processing failed for record ${recordToProcess?.id ?? "unknown"}:`,
      error
    );

    // If saveToDb was requested and record id is present, gracefully mark ai_status = 'failed'
    if (saveToDb && recordToProcess?.id) {
      try {
        await supabaseAdmin
          .from("memories")
          .update({
            ai_status: "failed",
            server_updated_at: new Date().toISOString(),
          })
          .eq("id", recordToProcess.id);
      } catch (dbFallbackErr) {
        console.error(
          `[Status Fallback Error] Could not update ai_status to 'failed' for ${recordToProcess.id}:`,
          dbFallbackErr
        );
      }
    }

    const statusCode = isTimeout ? 504 : 500;
    return new Response(
      JSON.stringify({
        success: false,
        error: error?.message || "Internal server error during ingestion",
        is_timeout: isTimeout,
      }),
      {
        status: statusCode,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
        },
      }
    );
  } finally {
    clearTimeout(timeoutId);
  }
});
