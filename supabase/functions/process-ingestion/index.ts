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

async function authenticateRequest(req: Request): Promise<{
  userId: string;
  authHeader: string;
} | null> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !/^Bearer\s+/i.test(authHeader)) {
    return null;
  }

  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) {
    return null;
  }

  const {
    data: { user },
    error,
  } = await supabaseAdmin.auth.getUser(token);

  if (error || !user) {
    return null;
  }

  return { userId: user.id, authHeader };
}

interface IngestionRecord {
  id: string;
  user_id: string;
  title?: string | null;
  content: string;
  category?: string | null;
  tags?: string[] | null;
  image_base64?: string | null;
  audio_base64?: string | null;
  document_base64?: string | null;
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

  // Timeout guardrail: 60 seconds execution deadline for batch operations
  const timeoutController = new AbortController();
  const timeoutId = setTimeout(() => {
    timeoutController.abort(new Error("Function execution timed out"));
  }, 60_000);

  try {
    const authenticatedRequest = await authenticateRequest(req);
    if (!authenticatedRequest) {
      return new Response(
        JSON.stringify({ error: "Unauthorized: valid Bearer token required." }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const authenticatedUserId = authenticatedRequest.userId;

    // 2. Parse Payload (supports direct POST payload or memoryId)
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

    const signal = timeoutController.signal;

    // MAINTENANCE ACTION: Safe Server-Side Re-Embedding of Existing Memories
    if (body.action === "reembed_all" || body.reembed_all === true) {
      return new Response(
        JSON.stringify({
          error: "Administrative re-embedding is not enabled for this endpoint.",
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Extract record from { record: { ... } } or top-level object
    const rawRecord = body.record ?? body;
    saveToDb = body.save_to_db !== false && rawRecord.save_to_db !== false;

    let targetId = rawRecord.id ?? body.memoryId ?? body.id;
    const requestedUserId = rawRecord.user_id ?? body.user_id;
    let targetUserId = authenticatedUserId;
    let targetTitle = rawRecord.title ?? body.title;
    let targetContent = rawRecord.content ?? body.content;
    let targetCategory = rawRecord.category ?? body.category;
    let targetTags = rawRecord.tags ?? body.tags;
    const targetImageBase64 = rawRecord.image_base64 ?? body.image_base64;
    let targetAudioBase64 = rawRecord.audio_base64 ?? body.audio_base64;
    let targetDocumentBase64 = rawRecord.document_base64 ?? body.document_base64;
    let targetMimeType = rawRecord.mime_type ?? body.mime_type;
    let isEmbeddingOnly = Boolean(body.embedding_only);
    const preserveContent = Boolean(
      body.preserve_content ||
      rawRecord.preserve_content ||
      body.is_note
    );
    let existingEmbedding: any = null;
    let existingAiStatus: string | null = null;

    if (requestedUserId && String(requestedUserId) !== authenticatedUserId) {
      return new Response(
        JSON.stringify({ error: "Forbidden: user_id does not match the authenticated user." }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Always load an existing target so service-role access is preceded by an ownership check.
    if (targetId) {
      try {
        const { data: dbMem } = await supabaseAdmin
          .from("memories")
          .select("id, user_id, title, content, category, tags, embedding, ai_status, media_url")
          .eq("id", targetId)
          .maybeSingle();

        if (dbMem) {
          if (String(dbMem.user_id) !== authenticatedUserId) {
            return new Response(
              JSON.stringify({ error: "Forbidden: memory does not belong to the authenticated user." }),
              {
                status: 403,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
              },
            );
          }

          targetTitle = targetTitle || dbMem.title;
          targetContent = targetContent || dbMem.content;
          targetCategory = targetCategory || dbMem.category;
          targetTags = targetTags || dbMem.tags;
          existingEmbedding = dbMem.embedding;
          existingAiStatus = dbMem.ai_status;
          // If memory was already analyzed and approved by user, switch to embedding_only mode
          if (existingAiStatus === "processed" && !rawRecord.imageBase64 && !targetImageBase64 && !targetAudioBase64 && !targetDocumentBase64) {
            isEmbeddingOnly = true;
          }

          if (!targetAudioBase64 && dbMem.media_url && !targetImageBase64) {
            const mediaUrl = String(dbMem.media_url);
            const isAudioUrl =
              mediaUrl.endsWith(".m4a") ||
              mediaUrl.endsWith(".aac") ||
              mediaUrl.endsWith(".mp3") ||
              mediaUrl.endsWith(".wav") ||
              (dbMem.tags && Array.isArray(dbMem.tags) && dbMem.tags.includes("voice"));
            if (isAudioUrl) {
              try {
                let storagePath = mediaUrl;
                if (storagePath.includes("/memories/")) {
                  storagePath = storagePath.split("/memories/").pop() || storagePath;
                }
                const { data: fileData } = await supabaseAdmin.storage
                  .from("memories")
                  .download(storagePath);
                if (fileData) {
                  const arrayBuffer = await fileData.arrayBuffer();
                  const bytes = new Uint8Array(arrayBuffer);
                  let binary = "";
                  for (let i = 0; i < bytes.byteLength; i++) {
                    binary += String.fromCharCode(bytes[i]);
                  }
                  targetAudioBase64 = btoa(binary);
                  targetMimeType = targetMimeType || "audio/m4a";
                }
              } catch (_) { }
            }
          }

          if (!targetDocumentBase64 && dbMem.media_url && !targetImageBase64 && !targetAudioBase64) {
            const mediaUrl = String(dbMem.media_url);
            if (mediaUrl.endsWith(".pdf")) {
              try {
                let storagePath = mediaUrl;
                if (storagePath.includes("/memories/")) {
                  storagePath = storagePath.split("/memories/").pop() || storagePath;
                }
                const { data: fileData } = await supabaseAdmin.storage
                  .from("memories")
                  .download(storagePath);
                if (fileData) {
                  const arrayBuffer = await fileData.arrayBuffer();
                  const bytes = new Uint8Array(arrayBuffer);
                  let binary = "";
                  for (let i = 0; i < bytes.byteLength; i++) {
                    binary += String.fromCharCode(bytes[i]);
                  }
                  targetDocumentBase64 = btoa(binary);
                  targetMimeType = targetMimeType || "application/pdf";
                }
              } catch (_) { }
            }
          }
        }
      } catch (_) {
        // Fall through
      }
    }

    // Avoid duplicate embedding generation if a valid embedding already exists
    if (
      existingEmbedding &&
      (Array.isArray(existingEmbedding)
        ? existingEmbedding.length > 0
        : String(existingEmbedding).length > 10)
    ) {
      console.info(
        `[Ingestion] Memory ${targetId} already has valid embedding. Skipping duplicate generation.`
      );
      return new Response(
        JSON.stringify({
          success: true,
          id: targetId,
          already_embedded: true,
          ai_status: existingAiStatus || "processed",
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    targetId = targetId ? String(targetId) : crypto.randomUUID();
    targetUserId = targetUserId ? String(targetUserId) : "anonymous_client";

    recordToProcess = {
      id: targetId,
      user_id: targetUserId,
      title: targetTitle ? String(targetTitle) : null,
      content: targetContent ? String(targetContent) : "",
      category: targetCategory ? String(targetCategory) : null,
      tags: Array.isArray(targetTags) ? targetTags : null,
      image_base64: targetImageBase64 ? String(targetImageBase64) : null,
      audio_base64: targetAudioBase64 ? String(targetAudioBase64) : null,
      document_base64: targetDocumentBase64 ? String(targetDocumentBase64) : null,
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
      `[Ingestion Started] Processing memory ${recordToProcess.id} for user ${recordToProcess.user_id} (saveToDb: ${saveToDb}, embeddingOnly: ${isEmbeddingOnly})`
    );

    // 4. Run Ingestion Prompt and Embedding Generation

    // If embedding_only mode is requested (e.g. MemoryReviewScreen save where user already reviewed metadata),
    // skip LLM re-analysis to preserve user's custom title, tags, category, and summary!
    if (isEmbeddingOnly && saveToDb) {
      const embeddingResult = await generateEmbedding(
        {
          title: recordToProcess.title,
          category: recordToProcess.category,
          tags: recordToProcess.tags,
          content: recordToProcess.content,
        },
        undefined,
        signal
      );

      const serverUpdatedAt = new Date().toISOString();
      const { error: updateError } = await supabaseAdmin
        .from("memories")
        .update({
          embedding: embeddingResult.embedding,
          ai_status: "processed",
          server_updated_at: serverUpdatedAt,
        })
        .eq("id", recordToProcess.id);

      if (updateError) {
        console.warn(
          `[Ingestion DB Error] Failed to update embedding for ${recordToProcess.id}: ${updateError.message}`
        );
      }

      const executionTimeMs = Math.round(performance.now() - startTime);

      try {
        await supabaseAdmin.from("ai_usage_logs").insert({
          user_id: recordToProcess.user_id,
          feature_name: "ingestion_embedding",
          model_used: embeddingResult.modelUsed,
          prompt_tokens: 0,
          completion_tokens: 0,
          total_tokens: 0,
          execution_time_ms: executionTimeMs,
        });
      } catch (_) { }

      console.info(
        `[Ingestion Success] Memory ${recordToProcess.id} embedded in ${executionTimeMs}ms (model: ${embeddingResult.modelUsed})`
      );

      return new Response(
        JSON.stringify({
          success: true,
          id: recordToProcess.id,
          title: recordToProcess.title,
          embedding_dimensions: embeddingResult.embedding.length,
          embedding_model: embeddingResult.modelUsed,
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
    }

    // Fast Ingestion LLM (gemini-3.5-flash-lite)
    const analysisResult = await analyzeMemoryContent(
      {
        title: recordToProcess.title,
        content: recordToProcess.content,
        imageBase64: recordToProcess.image_base64,
        audioBase64: recordToProcess.audio_base64,
        documentBase64: recordToProcess.document_base64,
        mimeType: recordToProcess.mime_type,
      },
      signal
    );

    const finalTitle = analysisResult.metadata.title;
    const finalCategory = analysisResult.metadata.category;
    const finalTags = analysisResult.metadata.tags;
    const finalSummary = analysisResult.metadata.summary;
    const finalEntities = analysisResult.metadata.entities;
    const finalTranscript = analysisResult.metadata.transcript;
    const finalDocumentText = analysisResult.metadata.documentText;

    const isVoiceMemory = Boolean(
      recordToProcess.audio_base64 ||
      (recordToProcess.tags && Array.isArray(recordToProcess.tags) && recordToProcess.tags.includes("voice")) ||
      (recordToProcess.media_url && (
        recordToProcess.media_url.endsWith(".m4a") ||
        recordToProcess.media_url.endsWith(".aac") ||
        recordToProcess.media_url.endsWith(".mp3") ||
        recordToProcess.media_url.endsWith(".wav")
      ))
    );

    const isPdfMemory = Boolean(
      recordToProcess.document_base64 ||
      (recordToProcess.tags && Array.isArray(recordToProcess.tags) && recordToProcess.tags.includes("pdf")) ||
      (recordToProcess.media_url && recordToProcess.media_url.endsWith(".pdf"))
    );

    let resolvedAiStatus = "processed";

    if (isVoiceMemory) {
      if (finalTranscript && finalTranscript.trim().length > 0) {
        recordToProcess.content = finalTranscript.trim();
        resolvedAiStatus = "processed";
      } else {
        // For voice/audio memories, NEVER use finalSummary as memories.content.
        // If transcript is empty/missing, do NOT mark the memory processed.
        recordToProcess.content = "";
        resolvedAiStatus = "failed";
      }
    } else if (isPdfMemory) {
      if (finalDocumentText && finalDocumentText.trim().length > 0) {
        recordToProcess.content = finalDocumentText.trim();
        resolvedAiStatus = "processed";
      } else if (recordToProcess.content && recordToProcess.content.trim().length > 0) {
        resolvedAiStatus = "processed";
      } else {
        // For PDF document memories, NEVER use finalSummary as memories.content.
        // If document text extraction is empty/missing, do NOT fabricate content.
        recordToProcess.content = "";
        resolvedAiStatus = "failed";
      }
    } else if (finalTranscript && finalTranscript.trim().length > 0) {
      recordToProcess.content = finalTranscript.trim();
    } else if (finalDocumentText && finalDocumentText.trim().length > 0) {
      recordToProcess.content = finalDocumentText.trim();
    }

    const hasUserTitle = Boolean(
      body.user_provided_title ||
      (recordToProcess.title &&
        recordToProcess.title.trim().length > 0 &&
        !recordToProcess.title.startsWith("Note (") &&
        !recordToProcess.title.startsWith("Voice Note (") &&
        recordToProcess.title !== "Quick Note")
    );
    const hasUserCategory = Boolean(
      body.user_provided_category ||
      (recordToProcess.category &&
        recordToProcess.category.trim().length > 0 &&
        !["General", "Quick Notes", "All"].includes(recordToProcess.category))
    );
    const hasUserTags = Boolean(
      body.user_provided_tags ||
      (recordToProcess.tags &&
        recordToProcess.tags.length > 0 &&
        !(recordToProcess.tags.length === 1 && (recordToProcess.tags[0] === "note" || recordToProcess.tags[0] === "voice")))
    );

    const resolvedTitle = hasUserTitle
      ? recordToProcess.title
      : (resolvedAiStatus === "failed" ? recordToProcess.title : (finalTitle || recordToProcess.title));
    const resolvedCategory = hasUserCategory
      ? recordToProcess.category
      : (finalCategory || recordToProcess.category || "General");
    const returnedSummary = resolvedAiStatus === "failed" ? "" : (finalSummary || "");

    let resolvedTags = recordToProcess.tags || [];
    if (!hasUserTags) {
      resolvedTags = finalTags || [];
    } else if (finalTags && Array.isArray(finalTags)) {
      const merged = new Set([...resolvedTags, ...finalTags]);
      resolvedTags = Array.from(merged);
    }

    if (recordToProcess.audio_base64 || (recordToProcess.tags && recordToProcess.tags.includes("voice"))) {
      if (!resolvedTags.includes("voice")) {
        resolvedTags.push("voice");
      }
    }

    if (recordToProcess.document_base64 || (recordToProcess.tags && recordToProcess.tags.includes("document")) || (recordToProcess.tags && recordToProcess.tags.includes("pdf"))) {
      if (!resolvedTags.includes("document")) {
        resolvedTags.push("document");
      }
    }

    let embeddingValues: number[] | null = null;
    let embeddingModel: string | null = null;

    // If saving to DB, generate 768-d embedding and update public.memories
    if (saveToDb) {
      const embeddingResult = await generateEmbedding(
        {
          title: resolvedTitle,
          category: resolvedCategory,
          tags: resolvedTags,
          content: recordToProcess.content,
        },
        undefined,
        signal
      );
      embeddingValues = embeddingResult.embedding;
      embeddingModel = embeddingResult.modelUsed;

      const serverUpdatedAt = new Date().toISOString();
      const updatePayload: Record<string, any> = {
        title: resolvedTitle,
        category: resolvedCategory,
        tags: resolvedTags,
        embedding: embeddingResult.embedding,
        ai_status: resolvedAiStatus,
        server_updated_at: serverUpdatedAt,
      };
      if (isVoiceMemory) {
        if (finalTranscript && finalTranscript.trim().length > 0) {
          updatePayload.content = finalTranscript.trim();
        } else {
          // Never use finalSummary as memories.content for voice/audio memories
          updatePayload.content = "";
        }
      } else if (isPdfMemory) {
        if (finalDocumentText && finalDocumentText.trim().length > 0) {
          updatePayload.content = finalDocumentText.trim();
        } else if (recordToProcess.content && recordToProcess.content.trim().length > 0) {
          updatePayload.content = recordToProcess.content.trim();
        } else {
          // Never use finalSummary as memories.content for PDF document memories
          updatePayload.content = "";
        }
      } else if (finalTranscript && finalTranscript.trim().length > 0) {
        updatePayload.content = finalTranscript.trim();
      } else if (finalDocumentText && finalDocumentText.trim().length > 0) {
        updatePayload.content = finalDocumentText.trim();
      } else if (!preserveContent) {
        const existingContent = (recordToProcess.content || "").trim();
        const isLinkContent =
          existingContent.startsWith("http://") ||
          existingContent.startsWith("https://");
        if (!isLinkContent && finalSummary && finalSummary.trim().length > 0) {
          updatePayload.content = finalSummary.trim();
        }
      }

      const { error: updateError } = await supabaseAdmin
        .from("memories")
        .update(updatePayload)
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
        title: resolvedTitle,
        category: resolvedCategory,
        tags: resolvedTags,
        summary: returnedSummary,
        transcript: finalTranscript,
        document_text: finalDocumentText,
        content: recordToProcess.content,
        entities: resolvedAiStatus === "failed" ? [] : finalEntities,
        embedding_dimensions: embeddingValues ? embeddingValues.length : null,
        embedding_model: embeddingModel,
        ai_status: resolvedAiStatus,
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
