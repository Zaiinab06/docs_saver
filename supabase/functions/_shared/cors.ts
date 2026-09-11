/**
 * Cross-Origin Resource Sharing (CORS) configuration for Supabase Edge Functions.
 */
export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-goog-api-key",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS, PUT, DELETE, PATCH",
};

/**
 * Handles CORS preflight OPTIONS requests.
 * Returns a Response with CORS headers if the request method is OPTIONS, or null otherwise.
 */
export function handleCors(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return null;
}
