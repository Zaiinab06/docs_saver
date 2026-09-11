/**
 * Shared Gemini AI Client for Supabase Edge Functions.
 *
 * Fast Ingestion LLM: "gemini-3.5-flash-lite"
 * Primary Embedding Model: "gemini-embedding-2-preview"
 * Fallback Embedding Model: "gemini-embedding-001" (on 429/5xx errors)
 */

export const INGESTION_MODEL = "gemini-3.5-flash-lite";
export const PRIMARY_EMBEDDING_MODEL = "gemini-embedding-2-preview";
export const FALLBACK_EMBEDDING_MODEL = "gemini-embedding-001";
export const EMBEDDING_DIMENSION = 768;

export interface IngestionMetadata {
  title: string;
  category: string;
  tags: string[];
}

export interface TokenUsage {
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
}

export interface IngestionAnalysis {
  metadata: IngestionMetadata;
  modelUsed: string;
  usage: TokenUsage;
}

export interface EmbeddingResult {
  embedding: number[];
  modelUsed: string;
}

/**
 * Retrieves the Gemini API key from environment variables.
 * Throws a descriptive error if not found.
 */
export function getGeminiApiKey(): string {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey || apiKey.trim().length === 0) {
    throw new Error(
      "Missing GEMINI_API_KEY environment variable. Please configure it in your Supabase secrets."
    );
  }
  return apiKey.trim();
}

/**
 * Analyzes note content using the fast ingestion model (gemini-3.5-flash-lite)
 * with structured JSON extraction for title, category, and tags.
 */
export async function analyzeMemoryContent(
  input: { title?: string | null; content: string },
  signal?: AbortSignal
): Promise<IngestionAnalysis> {
  const apiKey = getGeminiApiKey();
  const trimmedContent = (input.content || "").trim();
  const existingTitle = (input.title || "").trim();

  const systemInstruction = `You are a high-speed ingestion and categorization engine for a "Second Brain" knowledge system.
Analyze the user's note/memory and extract clean structured JSON:
- "title": A concise, descriptive title (3 to 8 words).
  * If the user provided a specific, non-generic title (not empty, "Untitled", "New Note", etc.), preserve or lightly polish it.
  * If the note is untitled or has a generic title, synthesize a smart, descriptive title capturing the core subject.
- "category": Select the single best matching category from:
  ["Work", "Personal", "Ideas", "Learning", "Technical", "Finance", "Health", "Meeting", "Journal", "Reference", "Projects", "Tasks", "General"].
- "tags": An array of 3 to 7 relevant, lowercase keyword tags (e.g. ["flutter", "architecture", "supabase", "sqlite"]).`;

  const userPrompt = `[INPUT]
Original Title: ${existingTitle ? `"${existingTitle}"` : "(Untitled)"}
Content:
"""
${trimmedContent || "(No content provided)"}
"""`;

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${INGESTION_MODEL}:generateContent`;

  const payload = {
    contents: [
      {
        role: "user",
        parts: [{ text: `${systemInstruction}\n\n${userPrompt}` }],
      },
    ],
    generationConfig: {
      temperature: 0.2,
      responseMimeType: "application/json",
      responseSchema: {
        type: "OBJECT",
        properties: {
          title: {
            type: "STRING",
            description: "Concise, descriptive title (3-8 words)",
          },
          category: {
            type: "STRING",
            description: "High-level classification category",
          },
          tags: {
            type: "ARRAY",
            items: { type: "STRING" },
            description: "3-7 lowercase keyword tags",
          },
        },
        required: ["title", "category", "tags"],
      },
    },
  };

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": apiKey,
    },
    body: JSON.stringify(payload),
    signal,
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(
      `Gemini ingestion LLM (${INGESTION_MODEL}) failed with status ${response.status}: ${errorBody}`
    );
  }

  const data = await response.json();
  const candidateText = data.candidates?.[0]?.content?.parts?.[0]?.text;

  if (!candidateText) {
    throw new Error(`Gemini ingestion LLM (${INGESTION_MODEL}) returned empty text candidate.`);
  }

  let parsed: any;
  try {
    let cleanJson = candidateText.trim();
    if (cleanJson.startsWith("```json")) {
      cleanJson = cleanJson.replace(/^```json\s*/, "").replace(/\s*```$/, "");
    } else if (cleanJson.startsWith("```")) {
      cleanJson = cleanJson.replace(/^```\s*/, "").replace(/\s*```$/, "");
    }
    parsed = JSON.parse(cleanJson);
  } catch (parseErr) {
    throw new Error(
      `Failed to parse JSON from Gemini ingestion response: ${candidateText}. Error: ${parseErr}`
    );
  }

  // Validate and sanitize extracted fields
  const resolvedTitle =
    typeof parsed.title === "string" && parsed.title.trim().length > 0
      ? parsed.title.trim()
      : existingTitle || "Untitled Memory";

  const resolvedCategory =
    typeof parsed.category === "string" && parsed.category.trim().length > 0
      ? parsed.category.trim()
      : "General";

  let resolvedTags: string[] = [];
  if (Array.isArray(parsed.tags)) {
    resolvedTags = parsed.tags
      .filter((t: unknown) => typeof t === "string" && (t as string).trim().length > 0)
      .map((t: string) => t.trim().toLowerCase());
    resolvedTags = Array.from(new Set(resolvedTags));
  }
  if (resolvedTags.length === 0) {
    resolvedTags = ["memory", resolvedCategory.toLowerCase()];
  }

  const usageMetadata = data.usageMetadata;
  const promptTokens = usageMetadata?.promptTokenCount ?? 0;
  const completionTokens = usageMetadata?.candidatesTokenCount ?? 0;
  const totalTokens =
    usageMetadata?.totalTokenCount ?? promptTokens + completionTokens;

  return {
    metadata: {
      title: resolvedTitle,
      category: resolvedCategory,
      tags: resolvedTags,
    },
    modelUsed: INGESTION_MODEL,
    usage: {
      promptTokens,
      completionTokens,
      totalTokens,
    },
  };
}

/**
 * Invokes the Gemini embedding endpoint for a given model.
 */
async function callEmbeddingApi(
  model: string,
  text: string,
  apiKey: string,
  targetDimension: number = EMBEDDING_DIMENSION,
  signal?: AbortSignal
): Promise<number[]> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:embedContent`;

  const payload: Record<string, unknown> = {
    content: {
      parts: [{ text }],
    },
    outputDimensionality: targetDimension,
  };

  let response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": apiKey,
    },
    body: JSON.stringify(payload),
    signal,
  });

  // Handle older embedding models that may reject outputDimensionality with 400
  if (response.status === 400) {
    const errText = await response.text();
    if (
      errText.includes("outputDimensionality") ||
      errText.includes("output_dimensionality") ||
      errText.includes("INVALID_ARGUMENT")
    ) {
      console.warn(
        `Embedding model ${model} rejected outputDimensionality parameter. Retrying without it...`
      );
      delete payload.outputDimensionality;
      response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": apiKey,
        },
        body: JSON.stringify(payload),
        signal,
      });
    } else {
      const err = new Error(`Embedding API error (${model}) HTTP 400: ${errText}`);
      (err as any).status = 400;
      throw err;
    }
  }

  if (!response.ok) {
    const errorText = await response.text();
    const error = new Error(
      `Embedding API error (${model}) HTTP ${response.status}: ${errorText}`
    );
    (error as any).status = response.status;
    throw error;
  }

  const data = await response.json();
  const values = data.embedding?.values;

  if (!Array.isArray(values) || values.length === 0) {
    throw new Error(`Embedding API (${model}) returned invalid or empty values.`);
  }

  // Ensure strict 768-dimension vector
  if (values.length > targetDimension) {
    return values.slice(0, targetDimension);
  } else if (values.length < targetDimension) {
    const padded = [...values];
    while (padded.length < targetDimension) {
      padded.push(0);
    }
    return padded;
  }

  return values;
}

/**
 * Generates a 768-dimension dense vector embedding for content + title.
 * Pipeline: Primary (gemini-embedding-2-preview) with automatic fallback
 * to (gemini-embedding-001) on 429 or 5xx server errors.
 */
export async function generateEmbedding(
  title: string | null | undefined,
  content: string,
  signal?: AbortSignal
): Promise<EmbeddingResult> {
  const apiKey = getGeminiApiKey();

  // Combine title and content for rich semantic representation
  const cleanTitle = (title || "").trim();
  const cleanContent = (content || "").trim();
  const textToEmbed = cleanTitle
    ? `${cleanTitle}\n\n${cleanContent}`
    : cleanContent;

  if (!textToEmbed) {
    throw new Error("Cannot generate embedding: Title and content are both empty.");
  }

  try {
    const embedding = await callEmbeddingApi(
      PRIMARY_EMBEDDING_MODEL,
      textToEmbed,
      apiKey,
      EMBEDDING_DIMENSION,
      signal
    );
    return {
      embedding,
      modelUsed: PRIMARY_EMBEDDING_MODEL,
    };
  } catch (err: any) {
    const status = err?.status;
    const isRetryableStatus =
      status === 429 || (typeof status === "number" && status >= 500);

    if (isRetryableStatus || (err?.name === "TypeError" && !signal?.aborted)) {
      console.warn(
        `[Embedding Fallback] Primary model "${PRIMARY_EMBEDDING_MODEL}" failed with status ${status || "network"}: ${err?.message}. Falling back to "${FALLBACK_EMBEDDING_MODEL}"...`
      );

      try {
        const fallbackEmbedding = await callEmbeddingApi(
          FALLBACK_EMBEDDING_MODEL,
          textToEmbed,
          apiKey,
          EMBEDDING_DIMENSION,
          signal
        );
        return {
          embedding: fallbackEmbedding,
          modelUsed: FALLBACK_EMBEDDING_MODEL,
        };
      } catch (fallbackErr: any) {
        throw new Error(
          `Embedding generation failed on both primary (${PRIMARY_EMBEDDING_MODEL}) and fallback (${FALLBACK_EMBEDDING_MODEL}). ` +
            `Primary error: ${err?.message}; Fallback error: ${fallbackErr?.message}`
        );
      }
    }

    // Re-throw non-retryable errors (e.g., 401 Unauthorized, aborts)
    throw err;
  }
}
