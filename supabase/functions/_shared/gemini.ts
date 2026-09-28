/**
 * Shared Gemini AI Client for Supabase Edge Functions.
 *
 * Fast Ingestion LLM: "gemini-3.5-flash-lite"
 * Primary Embedding Model: "gemini-embedding-2-preview"
 * Fallback Embedding Model: "gemini-embedding-001" (on 429/5xx errors)
 */

export const INGESTION_MODEL = "gemini-3.6-flash";
export const SYNTHESIS_MODEL = "gemini-3.6-flash";
export const SYNTHESIS_FALLBACK_MODEL = "gemini-3.8-flash";
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
  transcript?: string;
  documentText?: string;
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
export function getGeminiApiKey(customApiKey?: string | null): string {
  if (customApiKey && customApiKey.trim().length > 0) {
    console.info(`[Gemini] Using custom API key passed in header/payload (len=${customApiKey.trim().length})`);
    return customApiKey.trim();
  }
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey || apiKey.trim().length === 0) {
    console.error("❌ [Gemini Error] GEMINI_API_KEY environment variable is NOT set in Deno.env!");
    throw new Error(
      "Missing GEMINI_API_KEY environment variable. Please configure it in your Supabase secrets."
    );
  }
  console.info(`[Gemini] GEMINI_API_KEY retrieved from Deno.env (len=${apiKey.trim().length})`);
  return apiKey.trim();
}

export interface AnalyzeMemoryInput {
  title?: string | null;
  content: string;
  imageBase64?: string | null;
  audioBase64?: string | null;
  documentBase64?: string | null;
  videoBase64?: string | null;
  mimeType?: string | null;
  apiKey?: string | null;
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
    return line.trim();
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
  const apiKey = getGeminiApiKey(input.apiKey);
  const trimmedContent = (input.content || "").trim();
  const existingTitle = (input.title || "").trim();
  const isAudio = Boolean(input.audioBase64 && input.audioBase64.trim().length > 0);
  const isPdf = Boolean(
    (input.documentBase64 && input.documentBase64.trim().length > 0) ||
    (input.mimeType === "application/pdf" && input.imageBase64 && input.imageBase64.trim().length > 0)
  );
  const isVideo = Boolean(
    (input.videoBase64 && input.videoBase64.trim().length > 0) ||
    (input.mimeType && (input.mimeType.startsWith("video/") || input.mimeType === "video/mp4" || input.mimeType === "video/quicktime"))
  );

  const isImage = Boolean(input.imageBase64 && input.imageBase64.trim().length > 0);

  const systemInstruction = isAudio
    ? `You are an expert speech recognition and audio transcription engine for a personal "Second Brain".
Listen carefully to the audio and output clean structured JSON:
- "transcript": Verbatim transcription of all spoken words in the audio. If no speech, set to "".
- "title": Concise, descriptive title (3-8 words). If user provided title, keep it unchanged.
- "category": Select one: ["Work", "Personal", "Study", "Travel", "Fashion", "Food", "Finance", "Health & Fitness"].
- "tags": 2-6 lowercase keyword tags without #. Include "voice".
- "summary": ONE concise sentence summarizing the useful meaning.
- "entities": Key entities extracted [{"name": string, "type": string, "attributes": string}].`
    : (isPdf
        ? `You are an expert document reader and categorizer for a personal "Second Brain".
Read the PDF document and output clean structured JSON:
- "document_text": Accurate verbatim extracted text from the document.
- "title": Concise, descriptive title (3-8 words). If user provided title, keep it unchanged.
- "category": Select one: ["Work", "Personal", "Study", "Travel", "Fashion", "Food", "Finance", "Health & Fitness"].
- "tags": 2-6 lowercase keyword tags without #. Include "document".
- "summary": ONE concise sentence summarizing the useful meaning.
- "entities": Key entities extracted [{"name": string, "type": string, "attributes": string}].`
        : (isVideo
            ? `You are an expert video analyzer for a personal "Second Brain".
Inspect the video sequence and output clean structured JSON:
- "transcript": Verbatim transcription of spoken dialogue or description of visual actions.
- "title": Concise, descriptive title (3-8 words). If user provided title, keep it unchanged.
- "category": Select one: ["Work", "Personal", "Study", "Travel", "Fashion", "Food", "Finance", "Health & Fitness"].
- "tags": 2-6 lowercase keyword tags without #. Include "video".
- "summary": ONE concise sentence summarizing key actions or spoken information.
- "entities": Key entities extracted [{"name": string, "type": string, "attributes": string}].`
            : (isImage
                ? `You are an expert visual memory analyzer for a personal "Second Brain".
Analyze the attached image and any supporting OCR text. Output clean structured JSON:
- "title": Concise, descriptive title (3-8 words) based on visual subject matter. If user provided title, keep it unchanged. Never use "Untitled" or "Photo".
- "category": Select one: ["Work", "Personal", "Study", "Travel", "Fashion", "Food", "Finance", "Health & Fitness"].
- "tags": 2-6 specific, relevant lowercase keyword tags without #.
- "summary": ONE concise sentence summarizing the useful meaning (no image captioning like "photo of", no UI chrome clutter).
- "entities": 0-5 key entities [{"name": string, "type": string, "attributes": string}].`
                : `You are an expert note categorizer and summarizer for a personal "Second Brain".
Analyze the provided text note. Output clean structured JSON:
- "title": Concise, descriptive title (3-8 words) summarizing core subject. If user provided title, keep it unchanged.
- "category": Select one: ["Work", "Personal", "Study", "Travel", "Fashion", "Food", "Finance", "Health & Fitness"].
- "tags": 2-6 lowercase keyword tags without #.
- "summary": ONE concise sentence summarizing the useful meaning.
- "entities": 0-5 key entities [{"name": string, "type": string, "attributes": string}].`)));

  const userPrompt = isAudio
    ? `[INPUT]
User-Provided Title: ${existingTitle ? `"${existingTitle}"` : "(None)"}
Transcribe all spoken words and extract structured JSON metadata.`
    : (isPdf
        ? `[INPUT]
User-Provided Title: ${existingTitle ? `"${existingTitle}"` : "(None)"}
Extract document text and structured JSON metadata.`
        : (isVideo
            ? `[INPUT]
User-Provided Title: ${existingTitle ? `"${existingTitle}"` : "(None)"}
Analyze video sequence and extract structured JSON metadata.`
            : (isImage
                ? (trimmedContent.length > 0
                    ? `[INPUT]
User-Provided Title: ${existingTitle ? `"${existingTitle}"` : "(None)"}
OCR Extracted Text:
"""
${trimmedContent}
"""
Analyze the image and OCR text, and return clean structured JSON with title, category, tags, summary, and entities.`
                    : `Identify the main subjects/objects in this image. Generate a concise Title, Category (e.g., Food, Personal, Work, Study), a 2-sentence summary, and 3-5 tags in JSON format.${existingTitle ? `\nUser-Provided Title: "${existingTitle}"` : ""}`)
                : `[INPUT]
User-Provided Title: ${existingTitle ? `"${existingTitle}"` : "(None)"}
Note Content:
"""
${trimmedContent}
"""
Analyze the note content and return clean structured JSON with title, category, tags, summary, and entities.`)));

  let imageBase64Clean = "";
  if (isImage && input.imageBase64) {
    imageBase64Clean = input.imageBase64.trim();
    if (imageBase64Clean.includes(";base64,")) {
      imageBase64Clean = imageBase64Clean.split(";base64,").pop() || imageBase64Clean;
    }
    imageBase64Clean = imageBase64Clean.replace(/\s+/g, "");
  }

  const imageVisionPrompt = `Analyze this image and describe exactly what is in it. Return a valid JSON object with: {"title": "Short Title (3-5 words)", "category": "Work|Personal|Study|Home", "summary": "2-sentence factual summary of what is seen", "tags": ["tag1", "tag2", "tag3"]}. Output ONLY raw JSON, no markdown formatting.${existingTitle ? `\nUser-provided title: "${existingTitle}"` : ""}${trimmedContent ? `\nOCR detected text: "${trimmedContent}"` : ""}`;

  const parts: any[] = [];
  if (isImage) {
    parts.push({ text: imageVisionPrompt });
    parts.push({
      inline_data: {
        mime_type: input.mimeType || "image/jpeg",
        data: imageBase64Clean,
      },
    });
  } else {
    parts.push({ text: `${systemInstruction}\n\n${userPrompt}` });
    if (isPdf) {
      const pdfData = (input.documentBase64 || input.imageBase64)?.trim() || "";
      if (pdfData.length > 0) {
        parts.push({
          inline_data: {
            mime_type: "application/pdf",
            data: pdfData,
          },
        });
      }
    } else if (isVideo) {
      const videoData = (input.videoBase64 || input.imageBase64)?.trim() || "";
      if (videoData.length > 0) {
        let vidMime = input.mimeType || "video/mp4";
        if (vidMime === "video/mov") vidMime = "video/quicktime";
        parts.push({
          inline_data: {
            mime_type: vidMime,
            data: videoData,
          },
        });
      }
    } else if (input.audioBase64 && input.audioBase64.trim().length > 0) {
      let audioMime = input.mimeType || "audio/mp4";
      if (audioMime === "audio/m4a" || audioMime === "audio/x-m4a") {
        audioMime = "audio/mp4";
      }
      parts.push({
        inline_data: {
          mime_type: audioMime,
          data: input.audioBase64.trim(),
        },
      });
    }
  }

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
    },
  };

  const candidateModels = [
    "gemini-3.8-flash",
    "gemini-3.6-flash",
    "gemini-flash-latest",
    "gemini-flash-lite-latest",
    "gemini-3-flash-preview",
  ];

  let lastError: Error | null = null;
  let data: any = null;
  let modelUsed = candidateModels[0];
  const attemptErrors: string[] = [];

  for (const model of candidateModels) {
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        if (attempt > 0) {
          await new Promise((resolve) => setTimeout(resolve, 1500));
        }
        let response = await fetch(url, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify(payload),
          signal,
        });

        if (!response.ok) {
          const errorBody = await response.text();
          console.error("Gemini Vision API Raw Error:", errorBody);

          // If Google REST API rejected snake_case inline_data casing, retry with camelCase inlineData
          if (errorBody.includes("inline_data") || errorBody.includes("mime_type") || errorBody.includes("Cannot find field")) {
            console.warn(`[Ingestion Vision] Google API rejected inline_data casing. Retrying with camelCase inlineData...`);
            const camelParts = parts.map((p) => {
              if (p.inline_data) {
                return {
                  inlineData: {
                    mimeType: p.inline_data.mime_type,
                    data: p.inline_data.data,
                  },
                };
              }
              return p;
            });
            const camelPayload = { ...payload, contents: [{ role: "user", parts: camelParts }] };
            const retryRes = await fetch(url, {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify(camelPayload),
              signal,
            });
            if (retryRes.ok) {
              data = await retryRes.json();
              modelUsed = model;
              break;
            } else {
              const retryErr = await retryRes.text();
              console.error("Gemini Vision API Raw Error (camelCase):", retryErr);
            }
          }

          const msg = `API v1beta/${model} HTTP ${response.status}: ${errorBody}`;
          if ((response.status === 503 || response.status === 429) && attempt === 0) {
            console.warn(`[Ingestion Vision Warning] ${model} hit ${response.status}. Retrying in 1.5s...`);
            continue;
          }
          attemptErrors.push(msg);
          throw new Error(msg);
        }

        data = await response.json();
        modelUsed = model;
        break;
      } catch (err: any) {
        if (attempt === 1 || !(err.message?.includes("503") || err.message?.includes("429"))) {
          console.warn(`[Ingestion Vision Warning] ${model} failed: ${err.message}. Trying next...`);
          lastError = err;
          break;
        }
      }
    }
    if (data) break;
  }

  if (!data || !data.candidates?.[0]?.content?.parts?.[0]?.text) {
    const errorDetails = attemptErrors.length > 0 ? attemptErrors.join("; ") : "No response from Gemini API";
    console.error("❌ Gemini Vision Ingestion Failed completely:", errorDetails);
    throw new Error(`Gemini Vision API failed: ${errorDetails}`);
  }

  const candidateText = data.candidates[0].content.parts[0].text;
  console.info(`[Gemini Vision Dynamic Response Raw] for model ${modelUsed}:`, candidateText);

  let cleanJson = candidateText.trim();
  if (cleanJson.startsWith("```json")) {
    cleanJson = cleanJson.replace(/^```json\s*/, "").replace(/\s*```$/, "");
  } else if (cleanJson.startsWith("```")) {
    cleanJson = cleanJson.replace(/^```\s*/, "").replace(/\s*```$/, "");
  }

  let parsed: any;
  try {
    parsed = JSON.parse(cleanJson);
  } catch (parseErr) {
    console.error("❌ Failed to parse JSON from Gemini vision response:", candidateText);
    throw new Error(`Failed to parse JSON from Gemini vision response: ${candidateText}`);
  }

  // Validate and sanitize extracted fields
  const fallbackTitle = isPdf ? "Document" : (isAudio ? "Voice Note" : "Visual Memory");
  const resolvedTitle =
    existingTitle.length > 0
      ? existingTitle
      : typeof parsed.title === "string" && parsed.title.trim().length > 0
      ? parsed.title.trim()
      : fallbackTitle;

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

  const resolvedTranscript =
    typeof parsed.transcript === "string" ? parsed.transcript.trim() : "";
  const resolvedDocumentText =
    typeof parsed.document_text === "string" ? parsed.document_text.trim() : "";

  return {
    metadata: {
      title: resolvedTitle,
      category: resolvedCategory,
      tags: resolvedTags,
      summary: resolvedSummary,
      transcript: resolvedTranscript,
      documentText: resolvedDocumentText,
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

export interface MemoryEmbeddingInput {
  title?: string | null;
  category?: string | null;
  tags?: string[] | null;
  content: string;
}

/**
 * Formats a memory into the standard retrieval-document representation:
 * title: {title} | category: {category} | tags: {tags} | text: {content}
 */
export function formatMemoryForEmbedding(input: MemoryEmbeddingInput): string {
  const parts: string[] = [];
  const cleanTitle = (input.title || "").trim();
  if (cleanTitle) {
    parts.push(`title: ${cleanTitle}`);
  }

  const cleanCategory = (input.category || "").trim();
  if (cleanCategory) {
    parts.push(`category: ${cleanCategory}`);
  }

  const tagList = Array.isArray(input.tags)
    ? input.tags.map((t) => String(t).trim()).filter((t) => t.length > 0)
    : [];
  if (tagList.length > 0) {
    parts.push(`tags: ${tagList.join(", ")}`);
  }

  let cleanContent = (input.content || "").trim();
  // Strip bare URL line 1 if article body text follows
  if (
    (cleanContent.startsWith("http://") || cleanContent.startsWith("https://")) &&
    cleanContent.includes("\n")
  ) {
    const afterUrl = cleanContent.substring(cleanContent.indexOf("\n")).trim();
    if (afterUrl.length > 0) {
      cleanContent = afterUrl;
    }
  }

  if (cleanContent) {
    parts.push(`text: ${cleanContent}`);
  }

  return parts.join(" | ");
}

/**
 * Formats a search/ask query into the corresponding retrieval-query representation:
 * query: {query}
 */
export function formatQueryForEmbedding(query: string): string {
  return `query: ${query.trim()}`;
}

/**
 * Generates a 768-dimension dense vector embedding using gemini-embedding-2-preview.
 * Supports:
 * - Structured MemoryEmbeddingInput: title: ... | category: ... | tags: ... | text: ...
 * - Query string: query: ...
 * - Legacy (title, content) signature for backward compatibility
 */
export async function generateEmbedding(
  titleOrInput: string | null | undefined | MemoryEmbeddingInput,
  content?: string,
  signal?: AbortSignal
): Promise<EmbeddingResult> {
  const apiKey = getGeminiApiKey();

  let textToEmbed: string;

  if (typeof titleOrInput === "object" && titleOrInput !== null) {
    // Structured document embedding: title, category, tags, content
    textToEmbed = formatMemoryForEmbedding(titleOrInput);
  } else if (titleOrInput === null && typeof content === "string") {
    // Query embedding: title is null, content is search query
    textToEmbed = formatQueryForEmbedding(content);
  } else {
    // Legacy document embedding: title + content
    textToEmbed = formatMemoryForEmbedding({
      title: titleOrInput,
      content: content || "",
    });
  }

  if (!textToEmbed || textToEmbed.trim() === "" || textToEmbed.trim() === "query:") {
    throw new Error("Cannot generate embedding: input text is empty.");
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
        `[Embedding Fallback] Primary model "${PRIMARY_EMBEDDING_MODEL}" failed with status ${status || "network"}: ${err?.message}. Retrying with fallback...`
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

export interface CandidateForRerank {
  id: string;
  title?: string | null;
  content: string;
  category?: string | null;
  tags?: string[] | null;
}

export interface RerankedCandidateResult {
  id: string;
  isRelevant: boolean;
  confidence: "high" | "medium" | "low";
  reason?: string;
}

export interface BatchRerankResult {
  evaluations: RerankedCandidateResult[];
  modelUsed: string;
  usage: TokenUsage;
}

/**
 * Batched semantic reranking of candidate memories using Gemini.
 * Determines whether each candidate memory is genuinely relevant to the user query.
 * Evaluates candidates in a single prompt and filters out unrelated items.
 */
export async function rerankCandidates(
  query: string,
  candidates: CandidateForRerank[],
  signal?: AbortSignal
): Promise<BatchRerankResult> {
  if (!candidates || candidates.length === 0) {
    return {
      evaluations: [],
      modelUsed: "none",
      usage: { promptTokens: 0, completionTokens: 0, totalTokens: 0 },
    };
  }

  const apiKey = getGeminiApiKey();

  const formattedCandidates = candidates
    .map((c, i) => {
      const num = i + 1;
      const title = (c.title || "").trim() || "Untitled Note";
      const cat = c.category || "General";
      const tags =
        Array.isArray(c.tags) && c.tags.length > 0 ? c.tags.join(", ") : "none";
      const contentSnippet =
        c.content.length > 350 ? c.content.slice(0, 350) + "..." : c.content;
      return `[Candidate ${num}] ID: ${c.id}
Title: ${title} | Category: ${cat} | Tags: ${tags}
Content: "${contentSnippet}"`;
    })
    .join("\n\n");

  const systemInstruction = `You are an expert retrieval relevance evaluator for a personal "Second Brain" assistant.
Your task is to determine whether each retrieved candidate memory is GENUINELY RELEVANT to the user's question.

Evaluation Guidelines:
1. Set "is_relevant": true IF the candidate memory directly or semantically relates to what the user is asking about, including domain synonyms and related items (e.g. clothing, dress, fabric, garments, and lace are relevant to fashion/clothing queries; code, IDEs, programming reels, bugs, and algorithms are relevant to software development queries).
2. Set "is_relevant": false IF the candidate is completely unrelated or only shares superficial metadata (e.g. an underexposed dark photo, a mouse, or a dining table is NOT relevant to a clothing query; a dress or fabric note is NOT relevant to a programming query).
3. Provide "confidence": "high", "medium", or "low".
4. Do NOT hallucinate facts not present in the candidate memory.`;

  const userPrompt = `[USER QUESTION]
${query.trim()}

[CANDIDATE MEMORIES]
${formattedCandidates}

Evaluate each candidate memory's relevance to the question.`;

  const payload = {
    contents: [
      {
        role: "user",
        parts: [{ text: `${systemInstruction}\n\n${userPrompt}` }],
      },
    ],
    generationConfig: {
      temperature: 0.1,
      responseMimeType: "application/json",
      responseSchema: {
        type: "OBJECT",
        properties: {
          evaluations: {
            type: "ARRAY",
            items: {
              type: "OBJECT",
              properties: {
                id: { type: "STRING" },
                is_relevant: { type: "BOOLEAN" },
                confidence: { type: "STRING" },
                reason: { type: "STRING" },
              },
              required: ["id", "is_relevant"],
            },
          },
        },
        required: ["evaluations"],
      },
    },
  };

  const candidateModels = [
    "gemini-1.5-flash",
    "gemini-2.0-flash",
    INGESTION_MODEL,
    "gemini-2.5-flash",
  ];

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
        const errorText = await response.text();
        console.warn(
          `[Reranker Warning] Model ${model} returned ${response.status}: ${errorText}`
        );
        continue;
      }

      const data = await response.json();
      const rawText = data.candidates?.[0]?.content?.parts?.[0]?.text;
      if (!rawText) continue;

      const parsed = JSON.parse(rawText);
      const evaluationsList: RerankedCandidateResult[] = [];

      if (Array.isArray(parsed?.evaluations)) {
        for (const ev of parsed.evaluations) {
          evaluationsList.push({
            id: String(ev.id),
            isRelevant: Boolean(ev.is_relevant),
            confidence:
              ev.confidence === "high" ||
              ev.confidence === "medium" ||
              ev.confidence === "low"
                ? ev.confidence
                : "medium",
            reason: ev.reason ? String(ev.reason) : undefined,
          });
        }
      }

      const usageMetadata = data.usageMetadata;
      const promptTokens = usageMetadata?.promptTokenCount ?? 0;
      const completionTokens = usageMetadata?.candidatesTokenCount ?? 0;
      const totalTokens =
        usageMetadata?.totalTokenCount ?? promptTokens + completionTokens;

      return {
        evaluations: evaluationsList,
        modelUsed: model,
        usage: { promptTokens, completionTokens, totalTokens },
      };
    } catch (err: any) {
      console.warn(
        `[Reranker Attempt Error] Model ${model} failed:`,
        err?.message
      );
    }
  }

  // Graceful fallback: if reranker failed, return all candidates as accepted with medium confidence
  console.warn(
    "[Reranker Fallback] Reranking models exhausted. Defaulting to hybrid rank fusion scores."
  );
  return {
    evaluations: candidates.map((c) => ({
      id: c.id,
      isRelevant: true,
      confidence: "medium" as const,
      reason: "Fallback: deterministic hybrid rank",
    })),
    modelUsed: "deterministic-fallback",
    usage: { promptTokens: 0, completionTokens: 0, totalTokens: 0 },
  };
}
