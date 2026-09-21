# Vault Storage Duplicate Key Fix

PROPOSED — NOT APPLIED

## 1. Confirmed Production Error

- PostgreSQL error code: 23505
- HTTP status: 409
- Error: duplicate key value violates a unique constraint
- RPC: `store_vault_secret`

## 2. Root Cause Analysis

Repeated Google OAuth attempts are trying to create a new Vault secret using the same user-scoped secret name.

The current Edge Function call in [supabase/functions/google-auth/index.ts](../supabase/functions/google-auth/index.ts#L331-L347) uses:

```ts
new_name: `google_rf_${user_id}`
```

This is intended to be unique per user, but the current SQL wrapper in [supabase/migrations/20260920163000_create_oauth_sessions_and_user_integrations.sql](../supabase/migrations/20260920163000_create_oauth_sessions_and_user_integrations.sql#L79-L98) does a plain `vault.create_secret(...)` call every time. That means on any retry for the same user, the function attempts to create another secret with the same `name`, and PostgreSQL rejects it with `23505` (`duplicate key value violates a unique constraint`).

This creates a duplicate-secret failure during the callback flow, after Google returns a refresh token and before the app is marked connected. The callback then redirects to:

```text
secondbrain://oauth/callback?status=error&reason=vault_storage_failed
```

The underlying issue is not OAuth scope, redirect URI, or token exchange logic itself. It is a Vault storage idempotency bug: a create-only pattern is being used for a user-scoped secret name that should be reused or updated.

## 3. Current Implementation

Current SQL helper in [supabase/migrations/20260920163000_create_oauth_sessions_and_user_integrations.sql](../supabase/migrations/20260920163000_create_oauth_sessions_and_user_integrations.sql#L79-L98):

```sql
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
```

Current Edge Function call in [supabase/functions/google-auth/index.ts](../supabase/functions/google-auth/index.ts#L331-L347):

```ts
const { data: newSecretId, error: vaultErr } = await supabaseAdmin.rpc(
  "store_vault_secret",
  {
    new_secret: refreshToken,
    new_name: `google_rf_${user_id}`,
    new_description: "Google Drive OAuth refresh token",
  }
);
```

Issue:
- The secret name is stable per user, but the function attempts to create a new secret each time.
- Vault enforces uniqueness on the secret name.
- Subsequent OAuth retries produce a duplicate-key error and the HTTP 409 response.

## 4. Proposed Safe Fix

PROPOSED — NOT APPLIED

The fix should make `public.store_vault_secret` idempotent by doing the following:

- Use a stable, per-user secret name such as `google_rf_<user_id>`.
- If a secret with that name already exists, update the existing secret instead of creating a new row.
- If it does not exist, create it.
- Preserve the current `RETURNS UUID` contract.
- Preserve `SECURITY DEFINER` and `SET search_path = ''`.
- Preserve encryption by continuing to store the secret in Vault.
- Preserve the current OAuth redirect flow and callback behavior.
- Never log or expose the refresh token, secret value, access token, or client secret.
- Do not modify OAuth scopes or unrelated tables.

This is the minimal risk fix because it preserves the existing contract while eliminating the duplicate-key failure on retry.

## 5. Complete Proposed SQL Migration

PROPOSED — NOT APPLIED

```sql
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
    existing_secret_id UUID;
BEGIN
    -- If no name is provided, fall back to the default Vault behavior.
    IF new_name IS NULL OR new_name = '' THEN
        SELECT vault.create_secret(new_secret, new_name, new_description)
        INTO secret_id;

        RETURN secret_id;
    END IF;

    -- Reuse the existing secret for this user if it already exists.
    SELECT id
    INTO existing_secret_id
    FROM vault.secrets
    WHERE name = new_name
    LIMIT 1;

    IF existing_secret_id IS NOT NULL THEN
        UPDATE vault.secrets
        SET secret = new_secret,
            description = new_description,
            updated_at = now()
        WHERE id = existing_secret_id
        RETURNING id INTO secret_id;

        RETURN secret_id;
    END IF;

    -- Otherwise create the secret once for this user.
    SELECT vault.create_secret(new_secret, new_name, new_description)
    INTO secret_id;

    RETURN secret_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.store_vault_secret(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.store_vault_secret(TEXT, TEXT, TEXT) TO service_role;
```

Notes:
- This keeps the same return type: `UUID`.
- It continues to use Supabase Vault encryption.
- It prevents unlimited duplicate Vault entries created by repeated OAuth attempts.
- It preserves `SECURITY DEFINER` behavior.

If the project exposes a more explicit Vault update method in its runtime, that can be used instead of direct `UPDATE vault.secrets`, but the principle remains the same: same user + same secret name => update existing secret, not duplicate create.

## 6. Required TypeScript Changes

PROPOSED — NOT APPLIED

No TypeScript behavior change is strictly required. The current call site is already correct in structure and naming pattern. The Edge Function can keep its existing code shape.

The current logic in [supabase/functions/google-auth/index.ts](../supabase/functions/google-auth/index.ts#L331-L347) is already aligned with the intended idempotent contract:

```ts
const { data: newSecretId, error: vaultErr } = await supabaseAdmin.rpc(
  "store_vault_secret",
  {
    new_secret: refreshToken,
    new_name: `google_rf_${user_id}`,
    new_description: "Google Drive OAuth refresh token",
  }
);
```

No secret value logging is necessary. The only required runtime behavior is that the RPC itself becomes idempotent.

If desired, the TypeScript code can remain unchanged and only the SQL migration layer is adjusted. That is the safest minimal fix.

## 7. Deployment and Testing Steps

PROPOSED — NOT APPLIED

1. Review the migration in the target Supabase project and confirm the Vault schema is available.
2. Apply the SQL migration above in the Supabase Dashboard SQL Editor or via Supabase CLI only after approval.
3. Deploy the updated `google-auth` function only if the function call contract remains unchanged.
4. Run the Google OAuth flow once for the same user.
5. Confirm the first attempt stores the refresh token once.
6. Repeat the same OAuth flow for the same user.
7. Confirm the second attempt no longer triggers `23505` and no duplicate Vault secret is created.
8. Confirm the callback reaches success and the app connects normally.
9. Confirm `user_integrations` is updated with the same `vault_refresh_token_id` or refreshed value as expected.

Important: do not log or expose tokens, secret values, or client secrets during testing.

## 8. Rollback Plan

PROPOSED — NOT APPLIED

If the fix fails after deployment:

1. Preserve all current Vault secret records; do not delete or rotate anything blindly.
2. Revert the SQL function to the previous create-only version if necessary.
3. Keep the Edge Function as-is unless the production issue persists after the SQL fix.
4. Re-test the single-user OAuth retry flow before any broader rollout.
5. If rollback is required, restore the previous `public.store_vault_secret` definition and redeploy the function only if necessary.

Rollback should be limited to the Vault helper function only. Do not modify unrelated OAuth schema, database tables, or app behavior.

---

This document describes a proposed, not-yet-applied fix. It preserves encryption, security model, and OAuth behavior while making duplicate Vault secret storage idempotent per user.
