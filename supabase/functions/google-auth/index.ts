import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { unzipSync, strFromU8 } from "https://esm.sh/fflate@0.8.2";
import { corsHeaders, handleCors } from "../_shared/cors.ts";

// Supabase Admin Client using Service Role Key (bypasses RLS for backend worker tasks)
const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const supabaseAdmin = createClient(supabaseUrl, supabaseServiceRoleKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
});

/**
 * Helper to convert Uint8Array bytes to base64 efficiently in chunks.
 */
function uint8ArrayToBase64(bytes: Uint8Array): string {
  const CHUNK_SIZE = 0x8000; // 32768
  let binary = "";
  for (let i = 0; i < bytes.length; i += CHUNK_SIZE) {
    const chunk = bytes.subarray(i, Math.min(i + CHUNK_SIZE, bytes.length));
    binary += String.fromCharCode.apply(null, chunk as any);
  }
  return btoa(binary);
}

/**
 * Resolves accurate MIME type from filename extension if Drive returned generic octet-stream.
 */
function resolveMimeType(fileName: string, mimeType: string): string {
  if (mimeType && mimeType !== "application/octet-stream" && mimeType !== "binary/octet-stream") {
    return mimeType;
  }
  const lower = fileName.toLowerCase();
  if (lower.endsWith(".docx")) return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
  if (lower.endsWith(".doc")) return "application/msword";
  if (lower.endsWith(".xlsx")) return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
  if (lower.endsWith(".xls")) return "application/vnd.ms-excel";
  if (lower.endsWith(".pptx")) return "application/vnd.openxmlformats-officedocument.presentationml.presentation";
  if (lower.endsWith(".ppt")) return "application/vnd.ms-powerpoint";
  if (lower.endsWith(".pdf")) return "application/pdf";
  if (lower.endsWith(".txt")) return "text/plain";
  if (lower.endsWith(".xml")) return "application/xml";
  if (lower.endsWith(".json")) return "application/json";
  if (lower.endsWith(".md") || lower.endsWith(".markdown")) return "text/markdown";
  if (lower.endsWith(".csv")) return "text/csv";
  if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
  if (lower.endsWith(".png")) return "image/png";
  if (lower.endsWith(".webp")) return "image/webp";
  if (lower.endsWith(".mp3")) return "audio/mpeg";
  if (lower.endsWith(".m4a")) return "audio/x-m4a";
  if (lower.endsWith(".wav")) return "audio/wav";
  if (lower.endsWith(".aac")) return "audio/aac";
  if (lower.endsWith(".mp4")) return "video/mp4";
  if (lower.endsWith(".webm")) return "video/webm";
  if (lower.endsWith(".zip")) return "application/zip";
  return mimeType || "application/octet-stream";
}

/**
 * Extracts plain text from DOCX OpenXML package (word/document.xml).
 */
function extractDocxText(bytes: Uint8Array): string {
  try {
    const unzipped = unzipSync(bytes);
    const docXmlBytes = unzipped["word/document.xml"];
    if (!docXmlBytes) return "";
    const xmlStr = strFromU8(docXmlBytes);
    const withNewlines = xmlStr.replace(/<\/w:p>/gi, "\n");
    return withNewlines.replace(/<[^>]+>/g, "").replace(/\n\s*\n/g, "\n").trim();
  } catch (err) {
    console.warn("[docx] Failed to parse docx xml:", err);
    return "";
  }
}

/**
 * Extracts tabular text from XLSX OpenXML package (xl/sharedStrings.xml & sheet1.xml).
 */
function extractXlsxText(bytes: Uint8Array): string {
  try {
    const unzipped = unzipSync(bytes);
    const sharedStrings: string[] = [];
    const ssBytes = unzipped["xl/sharedStrings.xml"];
    if (ssBytes) {
      const ssXml = strFromU8(ssBytes);
      const matches = ssXml.match(/<t[^>]*>([^<]*)<\/t>/gi) || [];
      for (const m of matches) {
        sharedStrings.push(m.replace(/<[^>]+>/g, ""));
      }
    }
    const sheetBytes = unzipped["xl/worksheets/sheet1.xml"];
    if (!sheetBytes) return "";
    const sheetXml = strFromU8(sheetBytes);
    const rowMatches = sheetXml.match(/<row[^>]*>[\s\S]*?<\/row>/gi) || [];
    const rows: string[] = [];
    for (const r of rowMatches) {
      const cellMatches = r.match(/<c[^>]*>[\s\S]*?<\/c>/gi) || [];
      const cellValues: string[] = [];
      for (const c of cellMatches) {
        const isShared = c.includes('t="s"');
        const valMatch = c.match(/<v>([^<]*)<\/v>/i);
        if (valMatch) {
          const rawVal = valMatch[1];
          if (isShared) {
            const idx = parseInt(rawVal, 10);
            cellValues.push(sharedStrings[idx] || "");
          } else {
            cellValues.push(rawVal);
          }
        }
      }
      if (cellValues.length > 0) {
        rows.push(cellValues.join(", "));
      }
    }
    return rows.join("\n");
  } catch (err) {
    console.warn("[xlsx] Failed to parse xlsx xml:", err);
    return "";
  }
}

/**
 * Extracts slide text from PPTX OpenXML package (ppt/slides/slide*.xml).
 */
function extractPptxText(bytes: Uint8Array): string {
  try {
    const unzipped = unzipSync(bytes);
    const slideKeys = Object.keys(unzipped)
      .filter((k) => k.startsWith("ppt/slides/slide") && k.endsWith(".xml"))
      .sort();
    const slides: string[] = [];
    for (const key of slideKeys) {
      const xmlStr = strFromU8(unzipped[key]);
      const textMatches = xmlStr.match(/<a:t[^>]*>([^<]*)<\/a:t>/gi) || [];
      const slideText = textMatches.map((t) => t.replace(/<[^>]+>/g, "")).join(" ").trim();
      if (slideText) {
        slides.push(`[Slide ${slides.length + 1}]\n${slideText}`);
      }
    }
    return slides.join("\n\n");
  } catch (err) {
    console.warn("[pptx] Failed to parse pptx xml:", err);
    return "";
  }
}

/**
 * Extracts printable ASCII/UTF-8 character sequences from legacy binary formats (DOC, XLS, PPT).
 */
function extractPrintableText(bytes: Uint8Array): string {
  let result = "";
  let currentWord = "";
  for (let i = 0; i < bytes.length; i++) {
    const byte = bytes[i];
    if ((byte >= 32 && byte <= 126) || byte === 10 || byte === 9) {
      currentWord += String.fromCharCode(byte);
    } else {
      if (currentWord.length >= 4) {
        result += currentWord + " ";
      }
      currentWord = "";
    }
  }
  if (currentWord.length >= 4) {
    result += currentWord;
  }
  return result.replace(/\s{2,}/g, " ").trim();
}

/**
 * Base64URL encoding without padding (RFC 7636).
 */
function toBase64Url(bytes: Uint8Array): string {
  const binString = String.fromCharCode(...bytes);
  return btoa(binString)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

/**
 * Generates the PKCE S256 code challenge from the verifier.
 */
async function generateCodeChallenge(verifier: string): Promise<string> {
  const data = new TextEncoder().encode(verifier);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return toBase64Url(new Uint8Array(digest));
}

/**
 * Generates an HTTP 302 redirect response to safely trigger the mobile app deep link.
 * Does not expose any tokens or authorization codes in the URL or headers.
 */
function buildRedirectResponse(deepLinkUrl: string): Response {
  return new Response(null, {
    status: 302,
    headers: {
      "Location": deepLinkUrl,
      "Cache-Control": "no-store, no-cache, must-revalidate",
    },
  });
}

function readErrorField(error: unknown, field: string): unknown {
  if (error && typeof error === "object" && field in error) {
    return (error as Record<string, unknown>)[field];
  }
  return null;
}

function safeErrorMessage(error: unknown): string {
  const message = readErrorField(error, "message");
  if (typeof message !== "string" || message.length === 0) {
    return "Unknown error";
  }

  return message
    .replace(/(access[_ -]?token|refresh[_ -]?token|authorization[_ -]?code|client[_ -]?secret|cookie|secret)\s*[:=]\s*[^,\s]+/gi, "$1=[redacted]")
    .slice(0, 240);
}

function safeErrorCode(error: unknown): string {
  const code = readErrorField(error, "code");
  return typeof code === "string" && /^[A-Za-z0-9_.-]+$/.test(code)
    ? code
    : "unknown";
}

function safeErrorName(error: unknown): string {
  const name = readErrorField(error, "name");
  return typeof name === "string" && /^[A-Za-z0-9_.-]+$/.test(name)
    ? name
    : "Error";
}

function safeErrorHttpStatus(error: unknown): number | null {
  const status = readErrorField(error, "status");
  return typeof status === "number" && Number.isInteger(status) ? status : null;
}

function logSafeVaultFailure(
  stage: string,
  error: unknown,
  operation: "create" | "update",
): string {
  const errorCode = safeErrorCode(error);
  console.error("[google-auth] Vault storage failure", JSON.stringify({
    action: "oauth_callback",
    stage,
    operation,
    function_name: "public.store_vault_secret",
    error_name: safeErrorName(error),
    error_message: safeErrorMessage(error),
    postgres_code: errorCode,
    http_status: safeErrorHttpStatus(error),
  }));
  return errorCode;
}

Deno.serve(async (req: Request) => {
  // 1. Handle CORS Preflight
  const corsResponse = handleCors(req);
  if (corsResponse) {
    return corsResponse;
  }

  const url = new URL(req.url);

  // =========================================================================
  // 2. GET /callback: Google OAuth Redirect Handler
  // =========================================================================
  if (req.method === "GET") {
    const code = url.searchParams.get("code");
    const state = url.searchParams.get("state");
    const error = url.searchParams.get("error");
    const errorDescription = url.searchParams.get("error_description");
    const pickedFileIds = url.searchParams.get("picked_file_ids");
    const callbackParameterNames = [...url.searchParams.keys()].sort();

    console.info("[google-auth] OAuth callback received", JSON.stringify({
      action: "oauth_callback",
      callback_kind: pickedFileIds ? "picker_result" : error ? "oauth_error" : code ? "oauth_code" : "unknown",
      has_code: Boolean(code),
      has_state: Boolean(state),
      has_error: Boolean(error),
      has_error_description: Boolean(errorDescription),
      has_picked_file_ids: Boolean(pickedFileIds),
      has_scope: url.searchParams.has("scope"),
      parameter_names: callbackParameterNames,
    }));

    // Only an explicit access_denied means the user cancelled authorization.
    // Silent prompt=none failures must remain authorization errors.
    if (error) {
      const isUserCancellation = error === "access_denied";
      const safeReason = /^[A-Za-z0-9_.-]+$/.test(error) ? error : "oauth_error";
      console.warn("[google-auth] Google OAuth returned callback error", JSON.stringify({
        action: "oauth_callback",
        callback_kind: "oauth_error",
        reason: isUserCancellation ? "access_denied" : safeReason,
        has_error_description: Boolean(errorDescription),
        has_state: Boolean(state),
        has_picked_file_ids: Boolean(pickedFileIds),
      }));
      return buildRedirectResponse(
        isUserCancellation
          ? "secondbrain://oauth/callback?status=cancelled&error=access_denied"
          : `secondbrain://oauth/callback?status=error&reason=google_oauth_${encodeURIComponent(safeReason)}`
      );
    }

    if (!code || !state) {
      console.warn("[google-auth] Missing code or state in callback");
      return buildRedirectResponse(
        "secondbrain://oauth/callback?status=error&reason=missing_parameters"
      );
    }

    // Atomic one-time state consumption & PKCE verifier retrieval
    const { data: consumedRows, error: consumeErr } = await supabaseAdmin.rpc(
      "consume_oauth_session",
      { target_state_token: state }
    );

    if (consumeErr || !consumedRows || consumedRows.length === 0) {
      console.warn("[google-auth] State validation failed: expired, invalid, or replayed state");
      return buildRedirectResponse(
        "secondbrain://oauth/callback?status=error&reason=invalid_or_expired_state"
      );
    }

    const { user_id, code_verifier } = consumedRows[0];

    // Read Google OAuth credentials from environment configuration
    const googleClientId = Deno.env.get("GOOGLE_CLIENT_ID");
    const googleClientSecret = Deno.env.get("GOOGLE_CLIENT_SECRET");
    const googleRedirectUri =
      Deno.env.get("GOOGLE_REDIRECT_URI") ||
      `${supabaseUrl}/functions/v1/google-auth/callback`;

    if (!googleClientId || !googleClientSecret) {
      console.error("[google-auth] GOOGLE_CLIENT_ID or GOOGLE_CLIENT_SECRET is missing");
      return buildRedirectResponse(
        "secondbrain://oauth/callback?status=error&reason=credentials_not_configured"
      );
    }

    // Exchange authorization code for tokens with Google
    try {
      const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          code,
          code_verifier,
          client_id: googleClientId,
          client_secret: googleClientSecret,
          redirect_uri: googleRedirectUri,
          grant_type: "authorization_code",
        }),
      });

      if (!tokenResponse.ok) {
        await tokenResponse.text();
        console.error("[google-auth] Token exchange failed", JSON.stringify({
          action: "oauth_callback",
          stage: "token_exchange",
          function_name: "google-auth",
          error_name: "TokenExchangeError",
          error_message: "Google token exchange returned a non-success status",
          postgres_code: null,
          http_status: tokenResponse.status,
        }));
        return buildRedirectResponse(
          "secondbrain://oauth/callback?status=error&reason=token_exchange_failed"
        );
      }

      const tokenData = await tokenResponse.json();
      const refreshToken = tokenData.refresh_token as string | undefined;
      const idToken = tokenData.id_token as string | undefined;

      // Extract account email safely from id_token if present
      let accountEmail: string | null = null;
      let accountName: string | null = null;

      if (idToken) {
        try {
          const parts = idToken.split(".");
          if (parts.length >= 2) {
            const payload = JSON.parse(atob(parts[1]));
            accountEmail = payload.email || null;
            accountName = payload.name || null;
          }
        } catch (_) { }
      }

      // 1. Fetch existing integration row to preserve values on re-authorization
      const {
        data: existingIntegration,
        error: existingErr,
      } = await supabaseAdmin
        .from("user_integrations")
        .select("vault_refresh_token_id, account_email, account_name")
        .eq("user_id", user_id)
        .eq("provider", "google_drive")
        .maybeSingle();

      if (existingErr) {
        console.error(`[google-auth] Failed to query existing integration: ${existingErr.message}`);
        return buildRedirectResponse(
          "secondbrain://oauth/callback?status=error&reason=database_error"
        );
      }

      // 2. Preserve or update Vault refresh token
      // If a new refresh token is returned by Google, store it in Vault.
      // If no new refresh token is returned, preserve the existing vault_refresh_token_id.
      let vaultSecretId = existingIntegration?.vault_refresh_token_id ?? null;
      if (refreshToken) {
        const operation = existingIntegration?.vault_refresh_token_id ? "update" : "create";
        const { data: newSecretId, error: vaultErr } = await supabaseAdmin.rpc(
          "store_vault_secret",
          {
            new_secret: refreshToken,
            new_name: `google_rf_${user_id}`,
            new_description: "Google Drive OAuth refresh token",
          }
        );

        if (vaultErr || !newSecretId) {
          const failureStage = vaultErr
            ? safeErrorCode(vaultErr) === "23505"
              ? "duplicate_key"
              : safeErrorCode(vaultErr) === "42501"
                ? "permission"
                : operation
            : "rpc_response";
          const failureCode = logSafeVaultFailure(
            failureStage,
            vaultErr ?? { name: "EmptyRpcResponse", message: "RPC returned no secret ID" },
            operation,
          );
          return buildRedirectResponse(
            `secondbrain://oauth/callback?status=error&reason=${encodeURIComponent(`vault_storage_failed:${failureStage}:${failureCode}`)}`
          );
        }
        vaultSecretId = newSecretId;
      }

      // If neither a new refresh token nor an existing Vault secret exists, abort
      if (!vaultSecretId) {
        console.error("[google-auth] No refresh token returned and no existing Vault secret found");
        return buildRedirectResponse(
          "secondbrain://oauth/callback?status=error&reason=missing_refresh_token"
        );
      }

      // 3. Preserve or update account details
      // If new account details are present in id_token, update them; otherwise preserve existing.
      const finalEmail = accountEmail || existingIntegration?.account_email || null;
      const finalName = accountName || existingIntegration?.account_name || null;

      // 4. Upsert integration metadata in public.user_integrations safely
      const { error: upsertErr } = await supabaseAdmin
        .from("user_integrations")
        .upsert(
          {
            user_id,
            provider: "google_drive",
            account_email: finalEmail,
            account_name: finalName,
            scopes: ["https://www.googleapis.com/auth/drive.file"],
            status: "connected",
            vault_refresh_token_id: vaultSecretId,
            updated_at: new Date().toISOString(),
          },
          { onConflict: "user_id,provider" }
        );

      if (upsertErr) {
        console.error(`[google-auth] Failed to update user_integrations: ${upsertErr.message}`);
        return buildRedirectResponse(
          "secondbrain://oauth/callback?status=error&reason=integration_record_failed"
        );
      }

      // Success: redirect to app with status-only deep link (ZERO codes or tokens in deep link)
      let redirectUrl = "secondbrain://oauth/callback?status=success";
      if (pickedFileIds) {
        const firstPicked = pickedFileIds.split(",")[0].trim();
        if (firstPicked) {
          redirectUrl += `&picked_file_id=${encodeURIComponent(firstPicked)}`;
        }
      }
      return buildRedirectResponse(redirectUrl);
    } catch (exchangeErr: unknown) {
      console.error("[google-auth] OAuth callback failure", JSON.stringify({
        action: "oauth_callback",
        stage: "callback_or_redirect",
        function_name: "google-auth",
        error_name: safeErrorName(exchangeErr),
        error_message: safeErrorMessage(exchangeErr),
        postgres_code: safeErrorCode(exchangeErr),
        http_status: safeErrorHttpStatus(exchangeErr),
      }));
      return buildRedirectResponse(
        "secondbrain://oauth/callback?status=error&reason=internal_error"
      );
    }
  }

  // =========================================================================
  // 3. POST /start, /status, /disconnect: Authenticated User Actions
  // =========================================================================
  if (req.method === "POST") {
    // Validate Supabase User JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace(/^Bearer\s+/i, "");
    const {
      data: { user },
      error: userError,
    } = await supabaseAdmin.auth.getUser(token);

    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized user" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    let body: any = {};
    try {
      body = await req.json();
    } catch (_) { }

    const action =
      typeof body.action === "string" && body.action.trim().length > 0
        ? body.action.trim()
        : "status";

    // -----------------------------------------------------------------------
    // Action: /start or /start_picker
    // -----------------------------------------------------------------------
    if (action === "start" || action === "start_picker") {
      const isPicker =
        action === "start_picker" ||
        body.mode === "picker" ||
        body.isPicker === true;
      let hasValidConnection = false;
      if (isPicker) {
        const { data: integration, error: integrationErr } = await supabaseAdmin
          .from("user_integrations")
          .select("status, vault_refresh_token_id")
          .eq("user_id", user.id)
          .eq("provider", "google_drive")
          .maybeSingle();

        if (!integrationErr && integration?.status === "connected" && integration.vault_refresh_token_id) {
          const { data: storedRefreshToken, error: vaultErr } = await supabaseAdmin.rpc(
            "get_vault_secret",
            { target_secret_id: integration.vault_refresh_token_id },
          );
          const googleClientId = Deno.env.get("GOOGLE_CLIENT_ID");
          const googleClientSecret = Deno.env.get("GOOGLE_CLIENT_SECRET");

          if (!vaultErr && storedRefreshToken && googleClientId && googleClientSecret) {
            const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
              method: "POST",
              headers: { "Content-Type": "application/x-www-form-urlencoded" },
              body: new URLSearchParams({
                client_id: googleClientId,
                client_secret: googleClientSecret,
                refresh_token: storedRefreshToken,
                grant_type: "refresh_token",
              }),
            });

            if (tokenResponse.ok) {
              hasValidConnection = true;
            } else {
              const refreshError = await tokenResponse.json().catch(() => ({}));
              if (refreshError?.error === "invalid_grant") {
                await supabaseAdmin
                  .from("user_integrations")
                  .update({
                    status: "revoked",
                    vault_refresh_token_id: null,
                    updated_at: new Date().toISOString(),
                  })
                  .eq("user_id", user.id)
                  .eq("provider", "google_drive");
              }
            }
          }
        }
      }
      const googleClientId = Deno.env.get("GOOGLE_CLIENT_ID");
      const googleRedirectUri =
        Deno.env.get("GOOGLE_REDIRECT_URI") ||
        `${supabaseUrl}/functions/v1/google-auth/callback`;

      if (!googleClientId) {
        return new Response(
          JSON.stringify({
            error: "CONFIGURATION_ERROR",
            message:
              "Google Client ID is not configured on Supabase. Please configure GOOGLE_CLIENT_ID secret.",
          }),
          {
            status: 503,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      // Generate 256-bit cryptographically secure state token
      const stateBytes = new Uint8Array(32);
      crypto.getRandomValues(stateBytes);
      const stateToken = toBase64Url(stateBytes);

      // Generate 512-bit PKCE verifier and S256 challenge
      const verifierBytes = new Uint8Array(64);
      crypto.getRandomValues(verifierBytes);
      const codeVerifier = toBase64Url(verifierBytes);
      const codeChallenge = await generateCodeChallenge(codeVerifier);

      // Store in oauth_sessions with 10-minute expiry
      const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
      const { error: insertErr } = await supabaseAdmin
        .from("oauth_sessions")
        .insert({
          user_id: user.id,
          state_token: stateToken,
          code_verifier: codeVerifier,
          expires_at: expiresAt,
        });

      if (insertErr) {
        console.error(`[google-auth] Failed to insert oauth_sessions: ${insertErr.message}`);
        return new Response(
          JSON.stringify({ error: "Failed to initialize OAuth session" }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      // Opportunistic cleanup of expired sessions
      try {
        await supabaseAdmin
          .from("oauth_sessions")
          .delete()
          .lt("expires_at", new Date().toISOString());
      } catch (_) { }

      // Construct Google Authorization URL
      const authUrl = new URL("https://accounts.google.com/o/oauth2/v2/auth");
      authUrl.searchParams.set("client_id", googleClientId);
      authUrl.searchParams.set("redirect_uri", googleRedirectUri);
      authUrl.searchParams.set("response_type", "code");
      authUrl.searchParams.set(
        "scope",
        isPicker
          ? "https://www.googleapis.com/auth/drive.file"
          : "https://www.googleapis.com/auth/drive.file email profile"
      );
      authUrl.searchParams.set("code_challenge", codeChallenge);
      authUrl.searchParams.set("code_challenge_method", "S256");
      authUrl.searchParams.set("state", stateToken);
      authUrl.searchParams.set("access_type", "offline");
      // Google requires prompt=consent for the desktop/mobile Picker flow,
      // including accounts that already have a valid Drive connection.
      if (isPicker || !hasValidConnection) {
        authUrl.searchParams.set("prompt", "consent");
      } else if (!isPicker) {
        authUrl.searchParams.set("prompt", "none");
      }
      if (isPicker) {
        authUrl.searchParams.set("trigger_onepick", "true");
      }

      return new Response(
        JSON.stringify({
          success: true,
          auth_url: authUrl.toString(),
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // -----------------------------------------------------------------------
    // Action: /status
    // -----------------------------------------------------------------------
    if (action === "status") {
      const { data: integration, error: statusErr } = await supabaseAdmin
        .from("user_integrations")
        .select("status, account_email, account_name, updated_at")
        .eq("user_id", user.id)
        .eq("provider", "google_drive")
        .maybeSingle();

      if (statusErr) {
        return new Response(
          JSON.stringify({ error: statusErr.message }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      return new Response(
        JSON.stringify({
          connected: integration?.status === "connected",
          status: integration?.status || "not_connected",
          email: integration?.account_email || null,
          name: integration?.account_name || null,
          updated_at: integration?.updated_at || null,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // -----------------------------------------------------------------------
    // Action: /disconnect
    // -----------------------------------------------------------------------
    if (action === "disconnect") {
      const { data: integration, error: fetchErr } = await supabaseAdmin
        .from("user_integrations")
        .select("vault_refresh_token_id")
        .eq("user_id", user.id)
        .eq("provider", "google_drive")
        .maybeSingle();

      if (fetchErr) {
        console.error(`[google-auth] Failed to query user_integrations: ${fetchErr.message}`);
        return new Response(
          JSON.stringify({ error: "Failed to query integration status." }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      if (integration?.vault_refresh_token_id) {
        // Read decrypted token for Google revocation
        const { data: refreshToken } = await supabaseAdmin.rpc(
          "get_vault_secret",
          { target_secret_id: integration.vault_refresh_token_id }
        );

        if (refreshToken) {
          try {
            await fetch("https://oauth2.googleapis.com/revoke", {
              method: "POST",
              headers: {
                "Content-Type": "application/x-www-form-urlencoded",
              },
              body: `token=${encodeURIComponent(refreshToken)}`,
            });
          } catch (revokeErr) {
            console.warn(`[google-auth] Google token revocation warning: ${revokeErr}`);
          }
        }

        // Delete secret from Supabase Vault
        const { error: delErr } = await supabaseAdmin.rpc("delete_vault_secret", {
          target_secret_id: integration.vault_refresh_token_id,
        });

        if (delErr) {
          console.error(`[google-auth] Failed to delete Vault secret: ${delErr.message}`);
          return new Response(
            JSON.stringify({ error: "Failed to delete secure credentials from Vault." }),
            {
              status: 500,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            }
          );
        }
      }

      // Update user_integrations to revoked
      const { error: updateErr } = await supabaseAdmin
        .from("user_integrations")
        .update({
          status: "revoked",
          vault_refresh_token_id: null,
          updated_at: new Date().toISOString(),
        })
        .eq("user_id", user.id)
        .eq("provider", "google_drive");

      if (updateErr) {
        console.error(`[google-auth] Failed to update integration to revoked: ${updateErr.message}`);
        return new Response(
          JSON.stringify({ error: "Failed to update integration status." }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      return new Response(
        JSON.stringify({
          success: true,
          status: "disconnected",
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // -----------------------------------------------------------------------
    // Action: /import_doc - Secure Google Docs Content Extraction
    // -----------------------------------------------------------------------
    if (action === "import_doc") {
      const rawFileId = body.fileId;
      if (!rawFileId || typeof rawFileId !== "string" || !rawFileId.trim()) {
        return new Response(
          JSON.stringify({
            error: "INVALID_FILE_ID",
            message: "Missing or invalid Google Drive file ID.",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      const fileId = rawFileId.trim();

      // Validate Google Drive file ID format: standard base64url-like format without path traversal
      const fileIdRegex = /^[a-zA-Z0-9_-]{10,128}$/;
      if (!fileIdRegex.test(fileId)) {
        return new Response(
          JSON.stringify({
            error: "INVALID_FILE_ID",
            message: "Invalid Google Drive file ID format.",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      // 1. Verify user integration status and retrieve Vault secret reference
      const { data: integration, error: fetchErr } = await supabaseAdmin
        .from("user_integrations")
        .select("status, vault_refresh_token_id")
        .eq("user_id", user.id)
        .eq("provider", "google_drive")
        .maybeSingle();

      if (fetchErr) {
        console.error(`[google-auth] Failed to query user_integrations: ${fetchErr.message}`);
        return new Response(
          JSON.stringify({
            error: "DATABASE_ERROR",
            message: "Failed to verify integration status.",
          }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      if (!integration || integration.status !== "connected" || !integration.vault_refresh_token_id) {
        return new Response(
          JSON.stringify({
            error: "NOT_CONNECTED",
            message: "Google account is not connected. Please connect Google Drive in Settings.",
          }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      // 2. Retrieve refresh token securely from Supabase Vault
      const { data: refreshToken, error: vaultErr } = await supabaseAdmin.rpc(
        "get_vault_secret",
        { target_secret_id: integration.vault_refresh_token_id }
      );

      if (vaultErr || !refreshToken) {
        console.error(`[google-auth] Failed to retrieve vault secret: ${vaultErr?.message}`);
        return new Response(
          JSON.stringify({
            error: "VAULT_ERROR",
            message: "Failed to access secure Google credentials.",
          }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      // 3. Refresh Google Access Token
      const googleClientId = Deno.env.get("GOOGLE_CLIENT_ID");
      const googleClientSecret = Deno.env.get("GOOGLE_CLIENT_SECRET");

      if (!googleClientId || !googleClientSecret) {
        console.error("[google-auth] Missing GOOGLE_CLIENT_ID or GOOGLE_CLIENT_SECRET");
        return new Response(
          JSON.stringify({
            error: "CONFIGURATION_ERROR",
            message: "Google OAuth credentials not configured on the server.",
          }),
          {
            status: 503,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      let accessToken: string;
      try {
        const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({
            client_id: googleClientId,
            client_secret: googleClientSecret,
            refresh_token: refreshToken,
            grant_type: "refresh_token",
          }),
        });

        if (!tokenResponse.ok) {
          const tokenErrBody = await tokenResponse.json().catch(() => ({}));
          console.error(`[google-auth] Token refresh failed (HTTP ${tokenResponse.status}):`, tokenErrBody?.error || "unknown");

          if (tokenErrBody?.error === "invalid_grant") {
            // Refresh token revoked or expired by user
            await supabaseAdmin
              .from("user_integrations")
              .update({
                status: "revoked",
                vault_refresh_token_id: null,
                updated_at: new Date().toISOString(),
              })
              .eq("user_id", user.id)
              .eq("provider", "google_drive");

            return new Response(
              JSON.stringify({
                error: "TOKEN_REVOKED",
                message: "Google authorization expired or was revoked. Please reconnect in Settings.",
              }),
              {
                status: 401,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
              }
            );
          }

          return new Response(
            JSON.stringify({
              error: "AUTH_REFRESH_FAILED",
              message: "Failed to refresh Google authorization.",
            }),
            {
              status: 502,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            }
          );
        }

        const tokenData = await tokenResponse.json();
        accessToken = tokenData.access_token;
        if (!accessToken) {
          throw new Error("Missing access_token in Google response");
        }
      } catch (refreshErr: any) {
        console.error(`[google-auth] Exception during token refresh: ${refreshErr?.message}`);
        return new Response(
          JSON.stringify({
            error: "AUTH_REFRESH_FAILED",
            message: "Unable to refresh Google access token.",
          }),
          {
            status: 502,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      // 4. Fetch Google Drive File Metadata
      let metaData: { id: string; name: string; mimeType: string; webViewLink?: string; trashed?: boolean };
      try {
        const metadataUrl = new URL(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(fileId)}`);
        metadataUrl.searchParams.set("fields", "id,name,mimeType,webViewLink,trashed");
        metadataUrl.searchParams.set("supportsAllDrives", "true");

        const metaResponse = await fetch(metadataUrl.toString(), {
          headers: {
            Authorization: `Bearer ${accessToken}`,
          },
        });

        if (!metaResponse.ok) {
          const status = metaResponse.status;
          console.error(`[google-auth] Drive files.get returned HTTP ${status}`);

          if (status === 404) {
            return new Response(
              JSON.stringify({
                error: "FILE_NOT_FOUND",
                message: "File not found or not accessible. Under the current Google Drive permissions, the document must be opened with Google Picker or created by Second Brain.",
              }),
              {
                status: 404,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
              }
            );
          }

          if (status === 403) {
            return new Response(
              JSON.stringify({
                error: "PERMISSION_DENIED",
                message: "Access denied to the requested Google Drive file.",
              }),
              {
                status: 403,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
              }
            );
          }

          if (status === 429) {
            return new Response(
              JSON.stringify({
                error: "RATE_LIMITED",
                message: "Google Drive API rate limit exceeded. Please try again shortly.",
              }),
              {
                status: 429,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
              }
            );
          }

          return new Response(
            JSON.stringify({
              error: "DRIVE_API_ERROR",
              message: `Google Drive API returned error (HTTP ${status}).`,
            }),
            {
              status: 502,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            }
          );
        }

        metaData = await metaResponse.json();
      } catch (metaErr: any) {
        console.error(`[google-auth] Exception fetching file metadata: ${metaErr?.message}`);
        return new Response(
          JSON.stringify({
            error: "DRIVE_API_ERROR",
            message: "Failed to communicate with Google Drive API.",
          }),
          {
            status: 502,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      if (metaData.trashed) {
        return new Response(
          JSON.stringify({
            error: "FILE_TRASHED",
            message: "The selected file is in the Google Drive trash.",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      const resolvedMime = resolveMimeType(metaData.name || "", metaData.mimeType || "");

      // 5. Explicitly reject ZIP and compressed archives
      if (
        resolvedMime === "application/zip" ||
        resolvedMime === "application/x-zip-compressed" ||
        resolvedMime === "application/x-rar-compressed" ||
        resolvedMime === "application/x-7z-compressed"
      ) {
        return new Response(
          JSON.stringify({
            error: "UNSUPPORTED_ARCHIVE",
            message: "ZIP archives cannot be imported directly. Please extract and import individual files.",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      // 6. Explicitly reject executable / binary system files
      if (
        resolvedMime === "application/x-msdownload" ||
        resolvedMime === "application/x-executable" ||
        resolvedMime === "application/vnd.microsoft.portable-executable"
      ) {
        return new Response(
          JSON.stringify({
            error: "UNSUPPORTED_BINARY",
            message: "Executable and system files are not supported.",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      // Check size limit: 15 MB for docs/audio, 25 MB for video
      const isVideoMime =
        resolvedMime === "video/mp4" ||
        resolvedMime === "video/webm" ||
        resolvedMime === "video/quicktime";
      const maxAllowedBytes = isVideoMime ? 25 * 1024 * 1024 : 15 * 1024 * 1024;

      // 7. Route and extract based on MIME type
      let exportedText = "";
      let mediaBase64: string | null = null;
      let mediaType: string | null = null;
      let extractionMethod = "direct_text";
      const warnings: string[] = [];

      try {
        // --- Category A: Google Workspace Native Documents ---
        if (resolvedMime === "application/vnd.google-apps.document") {
          extractionMethod = "google_docs_export";
          const exportUrl = new URL(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(fileId)}/export`);
          exportUrl.searchParams.set("mimeType", "text/plain");
          const resp = await fetch(exportUrl.toString(), {
            headers: { Authorization: `Bearer ${accessToken}` },
          });
          if (!resp.ok) {
            return new Response(
              JSON.stringify({
                error: "EXPORT_FAILED",
                message: `Failed to export Google Docs content (HTTP ${resp.status}).`,
              }),
              { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
            );
          }
          exportedText = await resp.text();
        } else if (resolvedMime === "application/vnd.google-apps.spreadsheet") {
          extractionMethod = "google_sheets_export";
          const exportUrl = new URL(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(fileId)}/export`);
          exportUrl.searchParams.set("mimeType", "text/csv");
          const resp = await fetch(exportUrl.toString(), {
            headers: { Authorization: `Bearer ${accessToken}` },
          });
          if (!resp.ok) {
            return new Response(
              JSON.stringify({
                error: "EXPORT_FAILED",
                message: `Failed to export Google Sheets content (HTTP ${resp.status}).`,
              }),
              { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
            );
          }
          exportedText = await resp.text();
        } else if (resolvedMime === "application/vnd.google-apps.presentation") {
          extractionMethod = "google_slides_export";
          const exportUrl = new URL(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(fileId)}/export`);
          exportUrl.searchParams.set("mimeType", "text/plain");
          const resp = await fetch(exportUrl.toString(), {
            headers: { Authorization: `Bearer ${accessToken}` },
          });
          if (!resp.ok) {
            return new Response(
              JSON.stringify({
                error: "EXPORT_FAILED",
                message: `Failed to export Google Slides content (HTTP ${resp.status}).`,
              }),
              { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
            );
          }
          exportedText = await resp.text();
        }
        // --- Category B: Uploaded Files Download via files.get?alt=media ---
        else {
          const downloadUrl = `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(fileId)}?alt=media&supportsAllDrives=true`;
          const downloadResp = await fetch(downloadUrl, {
            headers: { Authorization: `Bearer ${accessToken}` },
          });

          if (!downloadResp.ok) {
            return new Response(
              JSON.stringify({
                error: "DOWNLOAD_FAILED",
                message: `Failed to download file from Google Drive (HTTP ${downloadResp.status}).`,
              }),
              { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
            );
          }

          const arrayBuffer = await downloadResp.arrayBuffer();
          const bytes = new Uint8Array(arrayBuffer);

          if (bytes.byteLength > maxAllowedBytes) {
            return new Response(
              JSON.stringify({
                error: "DOCUMENT_TOO_LARGE",
                message: `File exceeds maximum allowable size (${Math.round(maxAllowedBytes / (1024 * 1024))} MB).`,
              }),
              { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
            );
          }

          // 1. Text formats: TXT, XML, JSON, Markdown, CSV
          if (
            resolvedMime === "text/plain" ||
            resolvedMime === "text/xml" ||
            resolvedMime === "application/xml" ||
            resolvedMime === "application/json" ||
            resolvedMime === "text/markdown" ||
            resolvedMime === "text/x-markdown" ||
            resolvedMime === "text/csv" ||
            resolvedMime === "application/csv"
          ) {
            extractionMethod = "direct_text";
            exportedText = new TextDecoder("utf-8").decode(bytes);
          }
          // 2. PDF Documents
          else if (resolvedMime === "application/pdf") {
            extractionMethod = "gemini_pdf";
            mediaType = "pdf";
            mediaBase64 = uint8ArrayToBase64(bytes);
          }
          // 3. DOCX (Word OpenXML)
          else if (
            resolvedMime === "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
          ) {
            extractionMethod = "docx_xml";
            exportedText = extractDocxText(bytes);
          }
          // 4. DOC (Legacy Word)
          else if (resolvedMime === "application/msword") {
            extractionMethod = "doc_text_stream";
            exportedText = extractPrintableText(bytes);
          }
          // 5. XLSX (Excel OpenXML)
          else if (
            resolvedMime === "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
          ) {
            extractionMethod = "xlsx_sheets";
            exportedText = extractXlsxText(bytes);
          }
          // 6. XLS (Legacy Excel)
          else if (resolvedMime === "application/vnd.ms-excel") {
            extractionMethod = "xls_text_stream";
            exportedText = extractPrintableText(bytes);
          }
          // 7. PPTX (PowerPoint OpenXML)
          else if (
            resolvedMime === "application/vnd.openxmlformats-officedocument.presentationml.presentation"
          ) {
            extractionMethod = "pptx_slides";
            exportedText = extractPptxText(bytes);
          }
          // 8. PPT (Legacy PowerPoint)
          else if (resolvedMime === "application/vnd.ms-powerpoint") {
            extractionMethod = "ppt_text_stream";
            exportedText = extractPrintableText(bytes);
          }
          // 9. Images (JPG, JPEG, PNG, WEBP)
          else if (
            resolvedMime === "image/jpeg" ||
            resolvedMime === "image/png" ||
            resolvedMime === "image/webp"
          ) {
            extractionMethod = "gemini_ocr";
            mediaType = "image";
            mediaBase64 = uint8ArrayToBase64(bytes);
          }
          // 10. Audio (MP3, M4A, WAV, AAC, OGG)
          else if (
            resolvedMime === "audio/mpeg" ||
            resolvedMime === "audio/mp3" ||
            resolvedMime === "audio/mp4" ||
            resolvedMime === "audio/wav" ||
            resolvedMime === "audio/x-m4a" ||
            resolvedMime === "audio/aac" ||
            resolvedMime === "audio/ogg"
          ) {
            extractionMethod = "gemini_speech_to_text";
            mediaType = "audio";
            mediaBase64 = uint8ArrayToBase64(bytes);
          }
          // 11. Video (MP4, WEBM, QuickTime)
          else if (isVideoMime) {
            extractionMethod = "gemini_video_transcript";
            mediaType = "video";
            mediaBase64 = uint8ArrayToBase64(bytes);
          }
          // 12. Other Unsupported formats
          else {
            return new Response(
              JSON.stringify({
                error: "UNSUPPORTED_MIME_TYPE",
                message: `File type (${resolvedMime}) is not supported for import. Supported formats: Google Docs, Sheets, Slides, TXT, XML, JSON, Markdown, CSV, PDF, Office documents (DOCX, XLSX, PPTX), Images, Audio, and Video.`,
              }),
              { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
            );
          }
        }
      } catch (extractErr: any) {
        console.error(`[google-auth] Exception during file extraction: ${extractErr?.message}`);
        return new Response(
          JSON.stringify({
            error: "EXTRACTION_FAILED",
            message: `Failed to extract file content: ${extractErr?.message || "Unknown error"}`,
          }),
          { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // 8. Validate extracted content
      if ((!exportedText || exportedText.trim().length === 0) && !mediaBase64) {
        return new Response(
          JSON.stringify({
            error: "EMPTY_DOCUMENT",
            message: "The selected file contains no readable text or supported media.",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      const MAX_CONTENT_LENGTH = 500_000;
      if (exportedText.length > MAX_CONTENT_LENGTH) {
        warnings.push(`Extracted text exceeded ${MAX_CONTENT_LENGTH} characters and was truncated.`);
        exportedText = exportedText.substring(0, MAX_CONTENT_LENGTH);
      }

      // 9. Return structured CommonExtractionResult
      return new Response(
        JSON.stringify({
          success: true,
          title: metaData.name || "Untitled Google Drive File",
          content: exportedText,
          fileId: metaData.id,
          webViewLink: metaData.webViewLink || `https://drive.google.com/file/d/${metaData.id}/view`,
          mimeType: resolvedMime,
          extractionMethod,
          mediaBase64: mediaBase64 || null,
          mediaType: mediaType || null,
          warnings: warnings.length > 0 ? warnings : null,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    return new Response(
      JSON.stringify({ error: `Unknown action: ${action}` }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  return new Response(JSON.stringify({ error: `Method ${req.method} not allowed` }), {
    status: 405,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
