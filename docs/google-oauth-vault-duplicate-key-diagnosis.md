# Google OAuth Vault Duplicate-Key Diagnosis

Project: DocsSaver / Second Brain  
Supabase project ref: `vsqzsirrdkaxjdqmmwac`  
Status: Diagnosis and proposed next step only. No production code, schema, database function, Vault secret, or Edge Function was modified.

## Problem Summary

The Google OAuth callback fails with `vault_storage_failed` when it attempts to store a refresh token through the Supabase RPC `public.store_vault_secret`.

The confirmed production error is:


The local implementation passes a deterministic Vault name:

```text
google_rf_<user_id>
```

No application code, migration, database function, schema, Vault secret, or Supabase Edge Function was modified or deployed for this report.

## READ-ONLY Vault API Investigation

This section defines the catalog inspection required before implementing an idempotent storage fix. These queries inspect PostgreSQL metadata only. They must be run against the remote project by an authorized operator and must not be replaced with calls to Vault functions.

### 1. List every function in the `vault` schema

```sql
SELECT
	n.nspname AS schema_name,
	p.proname AS function_name,
	pg_get_function_identity_arguments(p.oid) AS arguments,
	pg_get_function_result(p.oid) AS return_type,
	CASE p.provolatile
		WHEN 'i' THEN 'IMMUTABLE'
		WHEN 's' THEN 'STABLE'
		WHEN 'v' THEN 'VOLATILE'
	END AS volatility,
	p.prosecdef AS is_security_definer,
	has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_can_execute
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'vault'
ORDER BY p.proname, arguments;
```

### 2. List functions related to secret creation, updates, or deletion

```sql
SELECT
	n.nspname AS schema_name,
	p.proname AS function_name,
	pg_get_function_identity_arguments(p.oid) AS arguments,
	pg_get_function_result(p.oid) AS return_type,
	CASE p.provolatile
		WHEN 'i' THEN 'IMMUTABLE'
		WHEN 's' THEN 'STABLE'
		WHEN 'v' THEN 'VOLATILE'
	END AS volatility,
	p.prosecdef AS is_security_definer,
	has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_can_execute
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'vault'
	AND p.proname ~* '(secret|create|update|delete)'
ORDER BY p.proname, arguments;
```

### 3. Inspect exact definitions without executing them

```sql
SELECT
	n.nspname AS schema_name,
	p.proname AS function_name,
	pg_get_function_identity_arguments(p.oid) AS arguments,
	pg_get_function_result(p.oid) AS return_type,
	pg_get_functiondef(p.oid) AS definition
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'vault'
	AND p.proname ~* '(secret|create|update|delete)'
ORDER BY p.proname, arguments;
```

Review definitions for function metadata only. Do not copy any output that contains a secret value or sensitive configuration.

### 4. Inspect function ACLs and role privileges

```sql
SELECT
	n.nspname AS schema_name,
	p.proname AS function_name,
	pg_get_function_identity_arguments(p.oid) AS arguments,
	p.proacl AS acl,
	has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_can_execute,
	has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_execute,
	has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'vault'
ORDER BY p.proname, arguments;
```

### 5. Inspect the existing public helpers

```sql
SELECT
	n.nspname AS schema_name,
	p.proname AS function_name,
	pg_get_function_identity_arguments(p.oid) AS arguments,
	pg_get_function_result(p.oid) AS return_type,
	CASE p.provolatile
		WHEN 'i' THEN 'IMMUTABLE'
		WHEN 's' THEN 'STABLE'
		WHEN 'v' THEN 'VOLATILE'
	END AS volatility,
	p.prosecdef AS is_security_definer,
	has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_can_execute
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
	AND p.proname IN ('store_vault_secret', 'get_vault_secret')
ORDER BY p.proname, arguments;
```

## Official Update Function Decision

The catalog results must establish whether the deployed Vault package provides an official update operation, its exact arguments and return type, volatility, `SECURITY DEFINER` status, and role permissions. No function name or signature should be inferred from naming conventions. If no supported update function exists, do not directly update Vault internals or invent a replacement API.

## Safe Implementation Plan

Only after the read-only catalog review and approval:

1. Use `user_integrations.vault_refresh_token_id` as the primary reference when valid.
2. Reuse or update that secret only through an officially supported Vault operation.
3. Create a new secret only when no valid reference exists.
4. Preserve the current RPC contract if possible.
5. Make the operation atomic or conflict-aware for concurrent OAuth callbacks.
6. Preserve `SECURITY DEFINER`, service-role-only execution, and `search_path` hardening.
7. Do not automatically delete the old secret, including after a failed upsert.
8. Do not use random per-retry names as a substitute for idempotency.

## Required Test Cases

- **First authorization:** no integration reference exists; one secret is created and its UUID is stored.
- **Repeated authorization with a new refresh token:** the existing secret is updated or safely reused without `23505`.
- **Authorization without a new refresh token:** storage is skipped and the existing `vault_refresh_token_id` is preserved.
- **Concurrent OAuth callbacks:** simultaneous requests cannot create duplicate names or leave an unintended reference.
- **Failed integration upsert:** the prior referenced secret is not automatically deleted.
- **Refresh-token retrieval:** `get_vault_secret` continues through the privileged path without exposing its value.

## READ-ONLY Restrictions

- Do not execute any Vault function.
- Do not insert, update, or delete database rows.
- Do not modify production code, migrations, database functions, or schema.
- Do not create or delete Vault secrets.
- Do not deploy anything.
- Do not expose tokens, passwords, authorization codes, client secrets, or secret values.

## Investigation Outcome

1. **Created file path:** `docs/GOOGLE_VAULT_API_INVESTIGATION.md` (Windows resolves this case-insensitively to this existing Markdown path).
2. **Files created:** no additional file was created because the requested path already existed under a case-insensitive equivalent; the existing investigation document was updated in place.
3. **Confirmed findings:** `google_rf_${user_id}` is reused; `store_vault_secret` calls `vault.create_secret` on each new-token callback; `secrets_name_idx` produces PostgreSQL `23505`; and the callback returns `vault_storage_failed`.
4. **Pending verification:** the complete remote `vault` function catalog, any official update operation, exact signatures, volatility, security-definer status, and role permissions remain to be reviewed with the queries above.
5. **Recommended next step:** run the catalog queries against the remote project, record the verified Vault API, then review an atomic idempotent helper design before any database change.

The issue remains diagnosed, not fixed. No implementation or complete OAuth retest has been performed.

The issue is diagnosed but not fixed. The complete Google OAuth flow has not been successfully re-tested after a fix.

## Confirmed Evidence

The following production facts were supplied from the Supabase Dashboard:

- The `vault` schema exists.
- `vault.create_secret(text, text, text, uuid)` exists.
- `public.store_vault_secret(new_secret text, new_name text, new_description text)` exists.
- `public.get_vault_secret` exists.
- Both relevant public helper functions use `SECURITY DEFINER`.
- Required function permissions are true.
- `vault.secrets` has the unique index `secrets_name_idx`.
- The unique field involved is `vault.secrets.name`.
- Edge Function logs show HTTP `409`.
- Edge Function logs show PostgreSQL SQLSTATE `23505`.
- Edge Function logs show a duplicate-key violation.
- The failing RPC is `store_vault_secret`.
- The Google OAuth Edge Function returns `vault_storage_failed`.

These facts establish a uniqueness conflict during the Vault storage RPC. They do not require reading or exposing any secret value.

## Exact Root Cause

### Exact secret name being reused

In [supabase/functions/google-auth/index.ts](../supabase/functions/google-auth/index.ts#L331-L347), the callback sends:

```ts
new_name: `google_rf_${user_id}`
```

For one user, this produces the same logical name on each callback:

```text
google_rf_<that user's id>
```

The name contains no timestamp, random suffix, OAuth state, or existing Vault secret ID.

### Why the unique index rejects the insert

The migration defines `public.store_vault_secret` as a wrapper around `vault.create_secret`:

```sql
SELECT vault.create_secret(new_secret, new_name, new_description)
INTO secret_id;
```

There is no lookup by name and no update branch. Therefore, a second call with the same `new_name` attempts a second insert into `vault.secrets`. Since `secrets_name_idx` uniquely indexes `name`, PostgreSQL raises `23505`.

### Why the existing integration row does not prevent it

The callback reads `vault_refresh_token_id` from `user_integrations` before storage, but the ID is only used as the initial local value:

```ts
let vaultSecretId = existingIntegration?.vault_refresh_token_id ?? null;
```

When a new refresh token is present, the callback still calls `store_vault_secret` with the deterministic name. It does not pass the existing ID to the RPC or ask the SQL helper to update that Vault row.

The later `user_integrations` upsert occurs only after Vault storage succeeds. Its unique constraint on `(user_id, provider)` prevents duplicate integration rows, but it cannot prevent the earlier duplicate Vault insert.

## Why Repeated OAuth Attempts Fail

The current design is conditional:

- First authorization with a new refresh token: attempts a Vault create.
- Re-authorization with a new refresh token: attempts another Vault create using the same name and can fail with `23505`.
- Re-authorization without a new refresh token: skips the RPC and preserves the existing `vault_refresh_token_id`.

Thus, not every OAuth retry creates a Vault secret, but every retry that contains a non-empty new refresh token currently attempts a new create.

## Relevant Edge Function Flow

### Edge Function

[ supabase/functions/google-auth/index.ts](../supabase/functions/google-auth/index.ts#L317-L394)

Relevant behavior:

- selects `vault_refresh_token_id` from `user_integrations`
- calls `store_vault_secret` when `refreshToken` is present
- passes `google_rf_${user_id}` as `new_name`
- redirects with `vault_storage_failed` when the RPC returns an error
- upserts the returned Vault UUID into `user_integrations`

## Relevant Database Function Flow

The migration defines `public.store_vault_secret` as a create-only `SECURITY DEFINER` wrapper around `vault.create_secret`. `public.get_vault_secret` reads the encrypted value by the UUID stored in `user_integrations`.

### SQL migration and helper functions

[ supabase/migrations/20260920163000_create_oauth_sessions_and_user_integrations.sql](../supabase/migrations/20260920163000_create_oauth_sessions_and_user_integrations.sql#L20-L118)

Relevant schema and behavior:

```sql
vault_refresh_token_id UUID REFERENCES vault.secrets(id) ON DELETE SET NULL
```

```sql
CONSTRAINT uq_user_provider UNIQUE (user_id, provider)
```

```sql
SELECT vault.create_secret(new_secret, new_name, new_description)
INTO secret_id;
```

`get_vault_secret` reads `vault.decrypted_secrets` using the stored UUID. The application’s ID reference model is present, but the storage helper does not use that reference for idempotent updates.

## What PostgreSQL Error `23505` Means

PostgreSQL SQLSTATE `23505` is `unique_violation`. It means an insert or update attempted to create a value that already exists in a column or key protected by a unique constraint.

In this incident, the confirmed protected value is the Vault secret `name`, indexed by `secrets_name_idx`. The error is therefore consistent with the same deterministic secret name being submitted to a create operation more than once.

## Is This Caused by Duplicate Secret Names?

Yes. Based on the confirmed production index and error, plus the local code path, the failure is caused by a duplicate Vault secret name.

The name is not random per OAuth attempt. It is stable per user: `google_rf_${user_id}`. The create-only helper does not reuse or update the existing secret. This combination directly explains the `secrets_name_idx` violation.

## Possible Implementation Options

### Preferred: Reuse or update the existing Vault secret

For the current data model, the safest design is one current Google refresh-token secret per user/provider:

1. Read the existing `user_integrations.vault_refresh_token_id`.
2. If it references the intended existing secret, update that secret using an official, supported Vault update operation.
3. Preserve the same Vault UUID in `user_integrations`.
4. Create a new secret only when there is no valid existing reference.
5. Keep the stable name unless a reviewed lifecycle design requires otherwise.

The update mechanism must be verified against the deployed Vault function signatures before implementation. Do not assume that a direct update of `vault.secrets` is supported or safe.

The operation must also be atomic or conflict-aware. A simple check-then-create sequence can race when two OAuth callbacks run at the same time.

### Unique name per user/provider or attempt

A unique name could avoid the index collision, but it is not the safest default. Creating a new secret for every retry would:

- accumulate obsolete or orphaned Vault rows
- require cleanup logic
- risk deletion of a still-referenced credential
- create a new secret if the later integration upsert fails
- weaken the one-logical-secret-per-user/provider model

A unique name should be considered only if the product intentionally needs historical token versions and has an explicit, audited retention policy.

### Remove or replace an old secret safely

Do not delete the old secret before the replacement is successfully stored and referenced. In particular:

- do not delete a secret merely because a duplicate-name error occurred
- do not delete the existing secret as a first step in OAuth retry handling
- do not remove a secret while `user_integrations` still references it
- do not add automatic cleanup without a separate orphan-identification and retention design

If replacement is ever required, the safe order must be established and tested so a failed replacement cannot destroy the only usable credential.

### Prevent duplicate OAuth integrations

The existing `uq_user_provider UNIQUE (user_id, provider)` constraint already prevents duplicate integration rows. The Edge Function also uses an upsert with `onConflict: "user_id,provider"`.

This is useful protection, but it does not solve the Vault failure because Vault storage occurs before the integration upsert. No additional integration uniqueness change is indicated by this incident.

## Security Considerations

- Do not log access tokens, refresh tokens, authorization codes, client secrets, or Vault secret values.
- Keep diagnostics limited to function names, SQLSTATE, constraint metadata, and non-secret control-flow details.
- Preserve `SECURITY DEFINER` and service-role-only execution boundaries.
- Do not expose `vault.decrypted_secrets` to client roles.
- Do not manually execute secret-storage functions during diagnosis.
- Do not use raw token values in tests, SQL, logs, or documentation.
- Treat Vault UUIDs as sensitive operational metadata and expose them only where required.
- Do not delete Vault secrets automatically during duplicate-key recovery.
- Validate any future update helper against concurrent requests and privilege escalation risks.

## Safest Recommended Solution

The recommended next step is a narrowly scoped database-function design review, not an immediate production change:

1. Inspect the deployed Vault catalog for official update functions and their exact signatures.
2. Confirm the supported encrypted update mechanism for an existing Vault secret.
3. Design an idempotent, service-role-only helper that updates/reuses the existing secret when appropriate and creates one only when no valid secret exists.
4. Make the create path atomic or conflict-aware for concurrent OAuth callbacks.
5. Keep the current Edge Function call contract if possible, so the application code does not need to handle Vault internals.
6. Add focused tests for first authorization, repeated authorization with a new refresh token, repeated authorization without a new refresh token, concurrent callbacks, and failed integration upsert.
7. Apply the smallest approved migration only after the Vault API review.
8. Test the complete OAuth flow in the actual app, including the repeated authorization case that previously failed.

The safest fix is therefore reuse/update of the existing Vault secret, using an official supported Vault operation if available. Generating a new name on every retry is not recommended, and automatic deletion is not recommended.

## Required Vault API Verification

Before changing any database function, inspect the deployed Vault function signatures with a read-only catalog query:

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

Pay particular attention to an official update operation for an existing secret. Confirm its exact signature, encryption behavior, and service-role permissions before implementation. The confirmed `vault.create_secret(text, text, text, uuid)` signature does not by itself prove that an update API exists.

## Are Code Changes Required?

A database-function or migration change is required to make the storage operation idempotent because the current `store_vault_secret` implementation is create-only.

The Edge Function does not necessarily require a code change if the existing RPC signature is preserved and the database helper handles reuse/update internally. The current call already supplies the stable logical name and the new secret value.

If the approved design requires the RPC to accept an existing Vault UUID or a separate update operation, then a corresponding Edge Function change will be required. That decision depends on the verified Vault update API and concurrency design.

No such changes have been applied.

## Testing Plan

After implementation approval:

- [ ] First-time Google OAuth succeeds and stores one logical Vault secret.
- [ ] Repeated OAuth with a new refresh token succeeds without `409` or `23505`.
- [ ] The existing Vault secret is updated or safely reused.
- [ ] `user_integrations.vault_refresh_token_id` points to the intended UUID.
- [ ] OAuth without a new refresh token preserves the existing UUID.
- [ ] Concurrent callbacks do not create duplicate names.
- [ ] Google Drive token retrieval through `get_vault_secret` still succeeds.
- [ ] Disconnect and revocation still operate on the referenced secret.
- [ ] Failure after storage but before integration upsert does not delete the existing credential.
- [ ] No sensitive credential values appear in logs or test output.
- [ ] The actual Flutter app completes the full OAuth callback successfully.

A successful RPC call alone is not enough to claim resolution. The complete app flow and the repeated OAuth scenario must pass.

## Rollback Plan

If the idempotency change causes a regression:

- revert only the new helper behavior through an approved migration or controlled database change
- preserve existing Vault secrets and integration references
- do not delete or rotate credentials during rollback
- do not blindly recreate secrets with new names
- re-run first authorization, repeated authorization, token retrieval, and disconnect tests
- separately review any apparently orphaned rows before considering cleanup

## Current Status and Pending Work

Confirmed:

- The duplicate name is `google_rf_${user_id}`.
- The create-only helper calls `vault.create_secret` on every new-token callback.
- The unique index is `secrets_name_idx` on `vault.secrets.name`.
- PostgreSQL returns `23505` and the OAuth callback returns `vault_storage_failed`.
- Existing integration uniqueness is already enforced by `(user_id, provider)`.

Not yet done:

- no database function or schema change
- no application code change
- no destructive SQL
- no Vault secret deletion
- no deployment
- no complete post-fix OAuth test

The next operational action should be read-only verification of the official Vault update API, followed by review and approval of an idempotent implementation.
