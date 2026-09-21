-- Migration: Create oauth_sessions, user_integrations, and secure Vault helper functions
-- Description: Supports Phase 1 OAuth connection with atomic single-use state consumption and Supabase Vault token storage.

-- 1. OAuth Sessions Table (Short-lived PKCE & State Storage)
CREATE TABLE IF NOT EXISTS public.oauth_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    state_token TEXT NOT NULL UNIQUE,
    code_verifier TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '10 minutes'),
    used_at TIMESTAMPTZ NULL
);

-- Index for atomic one-time lookup and expiry checks
CREATE INDEX IF NOT EXISTS idx_oauth_sessions_lookup 
    ON public.oauth_sessions (state_token, used_at, expires_at);

-- RLS: Zero access for anon and authenticated; strictly service_role only
ALTER TABLE public.oauth_sessions ENABLE ROW LEVEL SECURITY;

-- 2. User Integrations Table (Metadata Only - No Plaintext Tokens)
CREATE TABLE IF NOT EXISTS public.user_integrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL CHECK (provider IN ('google_drive')),
    account_email TEXT,
    account_name TEXT,
    scopes TEXT[] NOT NULL DEFAULT '{}',
    status TEXT NOT NULL DEFAULT 'connected' CHECK (status IN ('connected', 'expired', 'revoked')),
    vault_refresh_token_id UUID REFERENCES vault.secrets(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_user_provider UNIQUE (user_id, provider)
);

-- Index on user_integrations for quick user status queries
CREATE INDEX IF NOT EXISTS idx_user_integrations_user_provider 
    ON public.user_integrations (user_id, provider);

-- RLS: Users can view their own integration status
ALTER TABLE public.user_integrations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own integration status"
    ON public.user_integrations FOR SELECT
    USING (auth.uid() = user_id);

-- Note: All modifications and token operations are performed strictly by Edge Functions via service_role.

-- 3. Atomic State Consumption Helper Function
-- Atomically marks the session as used and returns the user_id and code_verifier.
-- Replay or expired sessions return 0 rows.
CREATE OR REPLACE FUNCTION public.consume_oauth_session(target_state_token TEXT)
RETURNS TABLE (
    user_id UUID,
    code_verifier TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN QUERY
    UPDATE public.oauth_sessions
    SET used_at = now()
    WHERE state_token = target_state_token
      AND used_at IS NULL
      AND expires_at > now()
    RETURNING oauth_sessions.user_id, oauth_sessions.code_verifier;
END;
$$;

-- Revoke execute from public/anon/authenticated; grant only to service_role
REVOKE EXECUTE ON FUNCTION public.consume_oauth_session(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_oauth_session(TEXT) TO service_role;

-- 4. Secure Vault Helper Functions for Edge Functions
-- Storing a refresh token in vault.secrets
CREATE OR REPLACE FUNCTION public.store_vault_secret(
    new_secret TEXT,
    new_name TEXT DEFAULT NULL,
    new_description TEXT DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    secret_id UUID;
BEGIN
    SELECT vault.create_secret(new_secret, new_name, new_description) INTO secret_id;
    RETURN secret_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.store_vault_secret(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.store_vault_secret(TEXT, TEXT, TEXT) TO service_role;

-- Reading a decrypted secret from vault.decrypted_secrets
CREATE OR REPLACE FUNCTION public.get_vault_secret(target_secret_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    decrypted TEXT;
BEGIN
    SELECT decrypted_secret FROM vault.decrypted_secrets
    WHERE id = target_secret_id
    INTO decrypted;
    RETURN decrypted;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_vault_secret(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_vault_secret(UUID) TO service_role;

-- Deleting a secret from vault.secrets
CREATE OR REPLACE FUNCTION public.delete_vault_secret(target_secret_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    DELETE FROM vault.secrets WHERE id = target_secret_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.delete_vault_secret(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_vault_secret(UUID) TO service_role;
