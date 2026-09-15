/**
 * Shared Gemini AI Client for Supabase Edge Functions.
 *
 * Fast Ingestion LLM: "gemini-3.5-flash-lite"
 * Primary Embedding Model: "gemini-embedding-2-preview"
 * Fallback Embedding Model: "gemini-embedding-001" (on 429/5xx errors)
 */

export const INGESTION_MODEL = "gemini-3.5-flash-lite";
export const SYNTHESIS_MODEL = "gemini-3.8-flash";
export const SYNTHESIS_FALLBACK_MODEL = "gemini-2.5-flash";
export const PRIMARY_EMBEDDING_MODEL = "gemini-embedding-2-preview";
export const FALLBACK_EMBEDDING_MODEL = "gemini-embedding-001";
export const EMBEDDING_DIMENSION = 768;

export interface GroundedMemoryItem {
  id: string;
  title?: string | null;
  content: string;
  category?: string | null;
  tags?: string[] | null;
  client_created_at?: string | null;
  similarity?: number | null;
}

export interface SynthesisResult {
  answer: string;
  modelUsed: string;
  usage: TokenUsage;
}

export interface LivingEntityItem {
  name: string;
  type: string;
  attributes?: string;
}

export interface IngestionMetadata {
  title: string;
  category: string;
  tags: string[];
  summary: string;
  entities: LivingEntityItem[];
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

export interface AnalyzeMemoryInput {
  title?: string | null;
  content: string;
  imageBase64?: string | null;
  mimeType?: string | null;
}

/**
 * Sanitizes the semantic summary to guarantee a maximum of 1-2 concise points/lines,
 * filtering out raw URLs, status bar noise, and UI button text.
 */
export function sanitizeSemanticSummary(raw: string): string {
  if (!raw || typeof raw !== "string") return "";
  const lines = raw
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => {
      if (line.length === 0) return false;
      // Filter out raw URLs
      if (/^https?:\/\//i.test(line) || /^www\./i.test(line)) return false;
      // Filter out status bar patterns (e.g. 7:45 PM, 100%, 5G)
      if (/^\d{1,2}:\d{2}/.test(line) && line.length < 20) return false;
      if (/^\d{1,3}%\s*$/.test(line)) return false;
      // Filter out common UI chrome buttons / labels
      const clean = line.replace(/^[•\-\*]\s*/, "").trim().toLowerCase();
      const noise = [
        "back", "next", "done", "cancel", "close", "search", "home",
        "share", "menu", "more", "less ai", "settings", "profile",
      ];
      if (noise.includes(clean)) return false;
      return true;
    });

  if (lines.length === 0) return "";
  const maxLines = lines.slice(0, 2);
  const formatted = maxLines.map((line) => {
    if (line.startsWith("•") || line.startsWith("-") || line.startsWith("*")) {
      return `• ${line.replace(/^[•\-\*]\s*/, "").trim()}`;
    }
    return `• ${line.trim()}`;
  });

  return formatted.join("\n");
}

/**
 * Analyzes note content using the fast ingestion model (gemini-3.5-flash-lite)
 * with structured JSON extraction for title, category, tags, summary, and living memory entities.
 */
export async function analyzeMemoryContent(
  input: AnalyzeMemoryInput,
  signal?: AbortSignal
): Promise<IngestionAnalysis> {
  const apiKey = getGeminiApiKey();
  const trimmedContent = (input.content || "").trim();
  const existingTitle = (input.title || "").trim();

  const systemInstruction = `You are an expert multimodal visual intelligence and categorization engine for a personal "Second Brain".
You will receive an image and any supporting OCR extracted text.
Visually inspect the image carefully, read any visible text, and output clean structured JSON:
- "title": A concise, descriptive, human-readable title (3 to 8 words) summarizing the core subject.
  * If the user provided an explicit non-empty title, keep that title unchanged.
  * If no title is provided, generate a specific, factual title based on the visual subject matter. Never use "Untitled" or "Captured Memory" or "Photo".
- "category": Select the single best matching category from the 8 official app categories:
  ["Work", "Personal", "Study", "Travel", "Fashion", "Food", "Finance", "Health & Fitness"].
  * Decision criteria:
    - "Food": Dishes, pizza, sushi, meals, cooking ingredients, groceries, coffee, restaurants, drinks, snacks.
    - "Work": Code/programming screenshots, IDEs, software architecture, technical documentation, office tasks, company projects, spreadsheets, professional emails.
    - "Study": Handwritten/printed lecture notes, academic textbooks, science/math formulas, whiteboards, flashcards, certificates, research papers.
    - "Fashion": Outfits, clothing, shoes, sneakers, bags, jewelry, accessories, cosmetics, skincare.
    - "Finance": Receipts, invoices, bills, credit cards, bank statements, cryptocurrency charts, stock market graphs, expenses.
    - "Travel": Scenery, landmarks, monuments, hotels, flights, boarding passes, maps, nature/hiking, travel itineraries.
    - "Health & Fitness": Gym equipment, workouts, athletic training, vitamins, medicine/prescriptions, medical reports, healthy habits.
    - "Personal": Personal everyday items, human body/hand, selfies, pets, home moments, hobbies, casual snapshots.
  * Do NOT default to "Personal" unless it is genuinely personal/everyday life.
- "tags": An array of 2 to 6 specific, relevant, lowercase keyword tags describing what is actually visible or discussed (e.g. ["pizza", "mozzarella", "lunch"] or ["flutter", "bloc", "dart"]).
  * ABSOLUTELY FORBIDDEN TAGS: "photo", "image", "empty", "untitled", "general", "memory", "note".
  * If you cannot determine specific meaningful tags, return [].
- "summary": A SHORT semantic description containing ONLY the most important information visible and relevant in the image and OCR together.
  * MAXIMUM 1 to 2 concise points or lines. Format as bullet points (e.g. "• ") or 1-2 concise lines.
  * The description must communicate the core meaningful context (for example: identifying the app, platform, or source if visible, and the core subject, concept, or purpose).
  * CRITICAL: The AI must NOT use the raw OCR dump as the memory description. NEVER output long OCR sentences, full paragraphs, URLs, or unrelated detected text.
  * CRITICAL: Completely IGNORE and EXCLUDE irrelevant OCR clutter such as status bar text, battery/signal/time indicators, weather text, browser chrome, search URLs, buttons ("Back", "Next", "Done", "Cancel", "Search"), navigation labels, timestamps, ads, "Less AI", and random UI noise.
  * Dynamically determine these points from the image; do not fabricate or hardcode.
- "entities": Extract 0 to 5 key entities, concepts, or topics identified in the image:
  * "name": Entity name (e.g. "Pizza Margherita", "Flutter Bloc", "Newton's Laws", "Nike Air")
  * "type": One of "Object", "Topic", "Person", "Place", "Organization", "Project"
  * "attributes": Concise contextual detail`;

  const userPrompt = `[INPUT]
User-Provided Title: ${existingTitle ? `"${existingTitle}"` : "(None - please generate title)"}
OCR Extracted Text:
"""
${trimmedContent || "(No text detected by OCR. Rely entirely on visual image analysis.)"}
"""
Please visually analyze the attached image and OCR text, and return the structured JSON.`;

  const parts: any[] = [];
  if (input.imageBase64 && input.imageBase64.trim().length > 0) {
    parts.push({
      inlineData: {
        mimeType: input.mimeType || "image/jpeg",
        data: input.imageBase64.trim(),
      },
    });
  }
  parts.push({
    text: `${systemInstruction}\n\n${userPrompt}`,
  });

  const payload = {
    contents: [
      {
        role: "user",
        parts,
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
            description:
              "Must be one of: Work, Personal, Study, Travel, Fashion, Food, Finance, Health & Fitness",
          },
          tags: {
            type: "ARRAY",
            items: { type: "STRING" },
            description: "2-6 lowercase keyword tags without #",
          },
          summary: {
            type: "STRING",
            description:
              "Maximum 1-2 concise points/lines of semantic description (e.g. • App/Platform • Core subject). No raw OCR dumps, URLs, or UI noise.",
          },
          entities: {
            type: "ARRAY",
            items: {
              type: "OBJECT",
              properties: {
                name: { type: "STRING" },
                type: { type: "STRING" },
                attributes: { type: "STRING" },
              },
              required: ["name", "type"],
            },
            description: "Key entities extracted for Living Memory",
          },
        },
        required: ["title", "category", "tags", "summary"],
      },
    },
  };

  const candidateModels = [
    INGESTION_MODEL,
    "gemini-2.5-flash",
    "gemini-1.5-flash",
  ];

  let lastError: Error | null = null;
  let data: any = null;
  let modelUsed = INGESTION_MODEL;

  for (const model of candidateModels) {
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
    try {
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
        throw new Error(`Model ${model} failed HTTP ${response.status}: ${errorBody}`);
      }

      data = await response.json();
      modelUsed = model;
      break;
    } catch (err: any) {
      console.warn(`[Ingestion Vision Warning] Model ${model} failed: ${err.message}. Trying next model...`);
      lastError = err;
    }
  }

  if (!data) {
    throw lastError || new Error("All Gemini ingestion models failed.");
  }

  const candidateText = data.candidates?.[0]?.content?.parts?.[0]?.text;

  if (!candidateText) {
    throw new Error(`Gemini ingestion LLM (${modelUsed}) returned empty text candidate.`);
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
    existingTitle.length > 0
      ? existingTitle
      : typeof parsed.title === "string" && parsed.title.trim().length > 0
      ? parsed.title.trim()
      : "Visual Memory";

  const validCategories = [
    "Work",
    "Personal",
    "Study",
    "Travel",
    "Fashion",
    "Food",
    "Finance",
    "Health & Fitness",
  ];
  let resolvedCategory =
    typeof parsed.category === "string" && parsed.category.trim().length > 0
      ? parsed.category.trim()
      : "Personal";

  if (!validCategories.includes(resolvedCategory)) {
    const match = validCategories.find(
      (c) => c.toLowerCase() === resolvedCategory.toLowerCase()
    );
    resolvedCategory = match || "Personal";
  }

  const bannedTags = new Set([
    "photo",
    "image",
    "empty",
    "untitled",
    "general",
    "memory",
    "note",
    "picture",
    "capture",
    "camera",
  ]);

  let resolvedTags: string[] = [];
  if (Array.isArray(parsed.tags)) {
    resolvedTags = parsed.tags
      .filter((t: unknown) => typeof t === "string" && (t as string).trim().length > 0)
      .map((t: string) => t.trim().toLowerCase().replace(/^#/, ""))
      .filter((t: string) => !bannedTags.has(t) && t.length > 1);
    resolvedTags = Array.from(new Set(resolvedTags));
  }

  const resolvedSummary =
    typeof parsed.summary === "string" && parsed.summary.trim().length > 0
      ? sanitizeSemanticSummary(parsed.summary)
      : "";

  let resolvedEntities: LivingEntityItem[] = [];
  if (Array.isArray(parsed.entities)) {
    resolvedEntities = parsed.entities
      .filter((e: any) => e && typeof e.name === "string" && e.name.trim().length > 0)
      .map((e: any) => ({
        name: String(e.name).trim(),
        type: e.type ? String(e.type).trim() : "Topic",
        attributes: e.attributes ? String(e.attributes).trim() : "",
      }));
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
      summary: resolvedSummary,
      entities: resolvedEntities,
    },
    modelUsed,
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
  let cleanContent = (content || "").trim();

  // If content begins with a URL line followed by article/readable content,
  // strip the bare URL from the embedding input so the 768-d vector focuses
  // strictly on the high-signal semantic text.
  if (
    (cleanContent.startsWith("http://") || cleanContent.startsWith("https://")) &&
    cleanContent.includes("\n")
  ) {
    const afterUrl = cleanContent.substring(cleanContent.indexOf("\n")).trim();
    if (afterUrl.length > 0) {
      cleanContent = afterUrl;
    }
  }

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

/**
 * Calls Gemini text generation API for RAG synthesis.
 */
async function callSynthesisApi(
  model: string,
  systemInstruction: string,
  userPrompt: string,
  apiKey: string,
  signal?: AbortSignal
): Promise<{ text: string; usage: TokenUsage }> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;

  const payload = {
    contents: [
      {
        role: "user",
        parts: [{ text: `${systemInstruction}\n\n${userPrompt}` }],
      },
    ],
    generationConfig: {
      temperature: 0.2,
      maxOutputTokens: 1024,
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
    const err = new Error(
      `Gemini synthesis LLM (${model}) failed with status ${response.status}: ${errorBody}`
    );
    (err as any).status = response.status;
    throw err;
  }

  const data = await response.json();
  const text = data.candidates?.[0]?.content?.parts?.[0]?.text;

  if (!text) {
    throw new Error(`Gemini synthesis LLM (${model}) returned an empty response candidate.`);
  }

  const usageMetadata = data.usageMetadata;
  const promptTokens = usageMetadata?.promptTokenCount ?? 0;
  const completionTokens = usageMetadata?.candidatesTokenCount ?? 0;
  const totalTokens =
    usageMetadata?.totalTokenCount ?? promptTokens + completionTokens;

  return {
    text: text.trim(),
    usage: {
      promptTokens,
      completionTokens,
      totalTokens,
    },
  };
}

/**
 * Synthesizes a grounded answer from matched memories using Gemini 3.8 Flash
 * with fallback to Gemini 2.5 Flash.
 */
export async function synthesizeAnswer(
  query: string,
  memories: GroundedMemoryItem[],
  signal?: AbortSignal
): Promise<SynthesisResult> {
  const apiKey = getGeminiApiKey();

  const formattedMemories = memories
    .map((m, index) => {
      const memoryNumber = index + 1;
      const title = (m.title || "").trim() || "Untitled Note";
      const dateStr = m.client_created_at
        ? new Date(m.client_created_at).toISOString().split("T")[0]
        : "Unknown Date";
      const categoryStr = m.category || "General";
      const tagsStr =
        Array.isArray(m.tags) && m.tags.length > 0
          ? m.tags.join(", ")
          : "none";

      return `[Memory ${memoryNumber}] (ID: ${m.id})
Title: ${title}
Date: ${dateStr} | Category: ${categoryStr} | Tags: ${tagsStr}
Content:
"""
${m.content}
"""`;
    })
    .join("\n\n");

  const systemInstruction = `You are the personal AI knowledge assistant for the user's "Second Brain".
Your goal is to answer the user's question accurately, concisely, and factually based EXCLUSIVELY on their personal memories provided below.

Strict Grounding & Citation Rules:
1. Base your answer strictly on the provided context memories. Do NOT hallucinate, extrapolate, or invent facts that are not explicitly present in the memories.
2. If the memories do not contain enough relevant information to answer the question, state clearly and politely: "Based on your stored notes and memories, I don't have sufficient information to answer this question."
3. Cite your sources inline using brackets like [1], [2], etc., corresponding to the [Memory X] source numbers from which facts were gathered.
4. Keep the answer clear, helpful, and concise (typically 2-5 sentences unless greater detail is needed).`;

  const userPrompt = `[RETRIEVED MEMORIES]
${formattedMemories}

[USER QUESTION]
${query.trim()}

Answer:`;

  try {
    const result = await callSynthesisApi(
      SYNTHESIS_MODEL,
      systemInstruction,
      userPrompt,
      apiKey,
      signal
    );
    return {
      answer: result.text,
      modelUsed: SYNTHESIS_MODEL,
      usage: result.usage,
    };
  } catch (err: any) {
    const status = err?.status;
    const isRetryable =
      status === 404 ||
      status === 400 ||
      status === 429 ||
      (typeof status === "number" && status >= 500);

    if (isRetryable && !signal?.aborted) {
      console.warn(
        `[Synthesis Fallback] Primary model "${SYNTHESIS_MODEL}" failed with status ${status}: ${err?.message}. Falling back to "${SYNTHESIS_FALLBACK_MODEL}"...`
      );

      try {
        const fallbackResult = await callSynthesisApi(
          SYNTHESIS_FALLBACK_MODEL,
          systemInstruction,
          userPrompt,
          apiKey,
          signal
        );
        return {
          answer: fallbackResult.text,
          modelUsed: SYNTHESIS_FALLBACK_MODEL,
          usage: fallbackResult.usage,
        };
      } catch (fallbackErr: any) {
        console.warn(
          `[Synthesis Safety Fallback] Fallback model "${SYNTHESIS_FALLBACK_MODEL}" also failed. Falling back to "${INGESTION_MODEL}"...`
        );
        const lastResortResult = await callSynthesisApi(
          INGESTION_MODEL,
          systemInstruction,
          userPrompt,
          apiKey,
          signal
        );
        return {
          answer: lastResortResult.text,
          modelUsed: INGESTION_MODEL,
          usage: lastResortResult.usage,
        };
      }
    }

    throw err;
  }
}

