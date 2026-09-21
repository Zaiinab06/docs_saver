# Google OAuth Vault Duplicate-Key Diagnosis

Project: DocsSaver / Second Brain  
Supabase project ref: `vsqzsirrdkaxjdqmmwac`  
Status: Diagnostic report and proposed fix only. No database writes, secret deletion, code changes, or deployments were performed.

## Confirmed Root Cause

Repeated Google OAuth attempts can call `public.store_vault_secret` with the same Vault secret name:

```text
google_rf_<user_id>
```

The Edge Function constructs that name with:

```ts
new_name: `google_rf_${user_id}`
```

The current SQL implementation of `public.store_vault_secret` always calls `vault.create_secret(...)`. It does not look up an existing secret by name, update an existing secret, or use the existing `user_integrations.vault_refresh_token_id` to select a Vault row.

The remote Vault table has a unique index named `secrets_name_idx` on `vault.secrets.name`. Therefore, when a later OAuth callback attempts another create with the same name, PostgreSQL rejects the insert with:

- HTTP status: `409`
- PostgreSQL error code: `23505`
- Constraint: `secrets_name_idx`
- Error: `duplicate key value violates unique constraint "secrets_name_idx"`

This is the confirmed root cause of the reported duplicate-name failure: a stable per-user name is being sent through a create-only storage path protected by a unique name index.

The complete Google OAuth flow has not been re-tested successfully after a fix. The issue must not be described as fixed until that validation is completed.

## Relevant Error Details

The production failure is associated with:

- Supabase RPC: `public.store_vault_secret`
- Edge Function: `google-auth`
- HTTP status: `409`
- PostgreSQL SQLSTATE: `23505`
- Unique constraint/index: `secrets_name_idx`
- Failure reason returned by the OAuth callback: `vault_storage_failed`

`23505` is PostgreSQL’s `unique_violation` SQLSTATE. It means the attempted write conflicts with an existing value protected by a unique constraint or index. Here, the confirmed unique column is `vault.secrets.name`.

No token value or secret value is required to establish this diagnosis, and none is included in this report.

## Current OAuth Token Storage Flow

### 1. Existing integration lookup

The callback first queries `public.user_integrations` for the Google Drive integration and selects:

```ts
vault_refresh_token_id, account_email, account_name
```

It initializes the local Vault reference from the existing row:

```ts
let vaultSecretId = existingIntegration?.vault_refresh_token_id ?? null;
```

### 2. New refresh-token branch

When Google returns a non-empty refresh token, the callback invokes:

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

The returned ID replaces the local `vaultSecretId`. If the RPC fails, the callback redirects with:

```text
secondbrain://oauth/callback?status=error&reason=vault_storage_failed
```

### 3. Existing-token preservation branch

When Google does not return a new refresh token, the callback skips `store_vault_secret` and preserves the previously loaded `vault_refresh_token_id`. If neither a new token nor an existing ID is available, it returns `missing_refresh_token`.

### 4. Integration upsert

After successful storage or preservation, the callback upserts `public.user_integrations` with:

```ts
vault_refresh_token_id: vaultSecretId
```

The table has one row per `(user_id, provider)` through its unique constraint.

### 5. Later secret reads

The same stored UUID is used by `get_vault_secret` for Google Drive operations and token revocation. Disconnect also uses the stored ID when it removes the integration’s Vault secret. The ID is therefore the application-level reference to the Vault row, but it is currently not used to make a new-token write idempotent.

## Why Repeated OAuth Attempts Fail

The current migration defines the storage helper as:

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

This function is create-only. It does not:

- query `vault.secrets` by name
- update an existing Vault secret
- accept an existing Vault secret ID
- catch or resolve a duplicate-name conflict
- consult `user_integrations`

Consequently, an OAuth callback that receives a new refresh token attempts a new create every time. Because the name is deterministic for the user, the second create conflicts with `secrets_name_idx`.

Not every OAuth retry enters this failing path. A retry without a new refresh token skips storage and reuses the existing ID. The duplicate-key failure applies to repeated callbacks that contain a non-empty new refresh token.

## Existing Database and Vault Checks

The following production checks have been confirmed:

- `vault.create_secret` exists.
- `public.store_vault_secret` exists.
- `public.get_vault_secret` exists.
- `SECURITY DEFINER` is enabled for the relevant public helper functions.
- Required `EXECUTE` privilege checks returned `true`.
- The Vault table is `vault.secrets`.
- The unique index is `secrets_name_idx` on column `name`.

The local migration additionally confirms:

```sql
vault_refresh_token_id UUID REFERENCES vault.secrets(id) ON DELETE SET NULL
```

and:

```sql
CONSTRAINT uq_user_provider UNIQUE (user_id, provider)
```

These checks rule out the primary alternatives of a missing Vault object, missing helper, missing security-definer configuration, or missing execute privilege. The observed failure occurs during a valid runtime call that reaches the Vault create operation.

## Vault Function Signature Inspection

Before changing a database function, the available Vault function signatures must be inspected. The required read-only catalog query is:

```sql
SELECT
  n.nspname AS schema_name,
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS arguments,
  pg_get_function_result(p.oid) AS return_type
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'vault'
ORDER BY p.proname, arguments;
```

A further focused query for likely update operations is:

```sql
SELECT
  n.nspname AS schema_name,
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS arguments,
  pg_get_function_result(p.oid) AS return_type
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'vault'
  AND p.proname ILIKE ANY (ARRAY['%update%', '%secret%', '%create%'])
ORDER BY p.proname, arguments;
```

The local migration proves that `vault.create_secret` is the function currently used by the application helper. It does not prove that the deployed Vault package exposes an official update function. A remote catalog query was attempted from the local Supabase CLI, but the CLI connected to local Postgres at `127.0.0.1:54322` and failed because Docker/local Postgres was unavailable. Therefore, the existence and signature of an official Vault update operation remain pending remote verification.

No update function should be assumed, and no direct write to `vault.secrets` should be introduced until the deployed Vault API and permissions are confirmed.

## Safe Solution Options

### Option A: Reuse or update the existing secret

This is the preferred design if the product intends one current Google refresh token per user/provider.

The implementation would:

- preserve the stable name `google_rf_<user_id>`
- identify the existing secret using `user_integrations.vault_refresh_token_id` and/or the stable name
- use an official Vault update operation if one is available and supported
- create a new secret only when no valid existing reference exists
- preserve the resulting UUID in `user_integrations`

This avoids duplicate names and avoids accumulating obsolete secrets.

The implementation must be concurrency-safe. A simple `SELECT` followed by `CREATE` can race when two OAuth callbacks execute simultaneously. The final design must use an atomic or conflict-aware database operation supported by the deployed Vault implementation.

### Option B: Generate a unique name for every create

This would avoid the name collision by making every secret name unique. It is not recommended as the default fix because it would:

- create a new Vault row on every token rotation or retry
- require reliable cleanup of old rows
- risk orphaned secrets if the later integration upsert fails
- create unbounded Vault storage growth
- weaken the current one-logical-secret-per-user model

It addresses the index conflict by creating more records rather than making the operation idempotent.

### Option C: Delete and recreate automatically

This is not recommended. Deleting the existing secret before a replacement is fully stored and referenced can cause credential loss. A duplicate-key error is not sufficient justification to delete any Vault row.

The system should never automatically delete Vault secrets as part of duplicate-key recovery. Existing secrets should be retained until a reviewed replacement and reference update have succeeded. Any cleanup of confirmed orphaned secrets should be a separate, explicit, audited operation.

## Security Considerations

- Never log access tokens, refresh tokens, authorization codes, client secrets, or decrypted Vault values.
- Keep diagnostic output limited to status, SQLSTATE, constraint/index metadata, function names, and non-secret IDs only where operationally necessary.
- Preserve `SECURITY DEFINER` and service-role-only `EXECUTE` boundaries.
- Do not expose `vault.decrypted_secrets` through client-accessible APIs.
- Do not manually invoke secret-storage functions during diagnosis.
- Do not copy token values into SQL queries, tests, issue reports, or documentation.
- Do not delete or rotate existing Vault credentials during diagnosis.
- Ensure any update helper cannot be called by `anon` or `authenticated` roles.
- Treat the Vault secret UUID as sensitive operational metadata even though it is not the secret value.

## Recommended Implementation Plan

1. Run the read-only Vault catalog queries above against the remote project or Supabase Dashboard SQL Editor.
2. Confirm whether the deployed Vault package provides an official update operation and record its exact signature.
3. Confirm the supported way to update an encrypted Vault secret while preserving its UUID.
4. Design a service-role-only, `SECURITY DEFINER` helper that reuses/updates the existing secret when appropriate and creates one only when no valid secret exists.
5. Use `user_integrations.vault_refresh_token_id` as the primary reference where valid; retain the stable per-user name as the uniqueness identity if that matches the deployed Vault contract.
6. Make the create path atomic or conflict-aware so simultaneous callbacks cannot both create the same name.
7. Keep the Edge Function free of token logging and preserve its current error handling.
8. Add focused tests for first authorization, repeated authorization with a new refresh token, repeated authorization without a new refresh token, concurrent callbacks, and integration-upsert failure.
9. Apply the smallest approved database change only after the signature review.
10. Deploy or update the Edge Function only if the final RPC contract requires it.
11. Test the complete OAuth flow from the actual app, including callback handling and a repeated authorization attempt.

The recommended implementation is Option A: reuse/update the existing secret with an official Vault API when available, otherwise use a carefully reviewed project-supported approach. Do not use unique-per-retry names as the primary fix and do not delete secrets automatically.

## Testing Plan

After an approved implementation, test in a controlled environment first:

- [ ] First Google authorization with a new refresh token succeeds.
- [ ] Exactly one logical Vault secret is associated with the user/provider.
- [ ] Repeated authorization with a new refresh token succeeds without `23505`.
- [ ] The existing secret is updated or safely reused according to the approved design.
- [ ] `user_integrations.vault_refresh_token_id` points to the intended secret after success.
- [ ] Authorization without a new refresh token preserves the existing ID and skips unnecessary storage.
- [ ] Concurrent callback attempts do not create duplicate names.
- [ ] Google Drive operations can read the secret through `get_vault_secret`.
- [ ] Disconnect/revocation continues to use the stored ID correctly.
- [ ] A failure after storage but before integration upsert does not delete the existing secret.
- [ ] Logs contain no access tokens, refresh tokens, authorization codes, client secrets, or Vault secret values.
- [ ] The actual app completes the full OAuth callback flow successfully.

A successful RPC call alone is insufficient to claim the issue is fixed. The complete Google OAuth flow must pass, including a repeat attempt that previously produced the duplicate-name error.

## Rollback Plan

If the approved change causes a regression:

- revert only the new helper or RPC behavior
- preserve existing Vault rows and `user_integrations` references
- do not delete secrets as part of rollback
- do not rotate credentials blindly
- restore the prior function definition only through an approved migration or controlled SQL change
- re-run the first-authorization and repeated-authorization tests
- verify token retrieval and disconnect behavior before resuming production use

If a new secret was created during a failed rollout, classify it through read-only metadata review before any separately approved cleanup. Do not automatically delete it based only on the OAuth error.

## Current Status

The duplicate-name root cause is confirmed from the remote unique index/error evidence and the local create-only implementation. The safe fix is proposed but not applied. The availability of an official Vault update function is not yet confirmed because the available CLI attempted to connect to unavailable local Postgres rather than the remote project.

No application code, migration, database function, schema, Vault secret, or Supabase Edge Function was modified or deployed for this report.
