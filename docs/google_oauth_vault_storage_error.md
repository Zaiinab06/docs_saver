# Google OAuth Vault Storage Error Diagnostic Report

Project: DocsSaver / Second Brain  
Supabase project ref: `vsqzsirrdkaxjdqmmwac`

## Summary

The Google OAuth flow reaches the Vault storage step, but the operation fails before the app can complete the callback successfully. The remote Supabase Edge Function `google-auth` is active and running version `5`. The failure occurs when the function invokes the PostgreSQL RPC `public.store_vault_secret`, which returns an HTTP `409` response and PostgreSQL error `23505` with the message `duplicate key value violates unique constraint`.

This is a storage-layer failure rather than a general OAuth failure. The function successfully reaches the point where it attempts to persist the secret, but the persistence attempt is rejected by PostgreSQL because a duplicate value violates a unique constraint in the Vault-backed storage path.

This document separates confirmed facts from reasonable but unconfirmed hypotheses. No application code, migrations, schema, or Supabase function logic has been changed, and no Vault secrets have been deleted or rewritten.

---

## Confirmed Evidence

The following items were verified in the active remote Supabase project:

- Supabase Edge Function: `google-auth`
- Deployed function version: `5`
- RPC invoked: `public.store_vault_secret`
- RPC response: HTTP `409`
- PostgreSQL error code: `23505`
- Error message: `duplicate key value violates unique constraint`
- Remote functions exist:
  - `public.store_vault_secret`
  - `public.get_vault_secret`
- Both functions are marked `SECURITY DEFINER`
- Vault helper exists: `vault.create_secret`
- PostgreSQL permission checks returned `true`
- The function successfully reaches the Vault storage step but fails with `vault_storage_failed`

This evidence establishes that the failure is not a missing function or missing permission problem. The failure is occurring inside the actual Vault insert/update path, after the function has progressed far enough to call the storage RPC.

---

## What PostgreSQL error 23505 means

PostgreSQL error `23505` is the standard SQLSTATE for:

- `unique_violation`
- duplicate key value violates unique constraint

In practical terms, the database rejected the attempted insert because the target row would conflict with an existing unique index or unique constraint. This normally happens when:

- a duplicate value is being inserted into a unique column or unique composite key
- a secret name is reused in a system that enforces uniqueness
- an idempotency issue is present in a create-only path

The important point is that the error indicates a uniqueness conflict in the database layer, not a generic OAuth authentication failure. The OAuth code successfully reaches the point where it tries to persist the secret, and then the database rejects that operation.

---

## Likely Root Cause (Unconfirmed)

The most likely root cause is a duplicate value in the Vault storage path, most plausibly caused by repeated attempts to store a secret using a stable or repeated secret identifier under a uniqueness-enforced Vault table or helper flow.

This is a strong working hypothesis because:

- the database is rejecting the write with `23505`
- the call is specifically `public.store_vault_secret`
- the function reaches the storage step and then returns a failure reason of `vault_storage_failed`
- the system requires a successful Vault persistence before the OAuth callback can be considered successful

However, this root cause remains unconfirmed in the strictest sense because the full constraint name is truncated in the available output. The exact database object that raised the unique-constraint violation has not been fully disclosed, so the exact target constraint cannot be named with certainty.

This means the following statement is appropriate:

- Confirmed: a duplicate-key unique violation occurred during `public.store_vault_secret`.
- Unconfirmed: the exact underlying constraint name and the precise duplicate field/value combination.

---

## Relevant Code Flow

The likely operational flow is as follows:

1. The client initiates the Google OAuth flow.
2. The Edge Function `google-auth` receives the OAuth callback.
3. The function exchanges the authorization code for tokens.
4. The function prepares the refresh-token payload for storage.
5. The function calls `public.store_vault_secret`.
6. PostgreSQL rejects the write with `23505`.
7. The function records the Vault failure and returns an error path that ultimately surfaces as `vault_storage_failed`.
8. The user-facing OAuth flow does not complete successfully.

The critical point is that the failure is not at the start of the OAuth flow or at the redirect URI validation layer, but at the final persistence step where the refresh token is written into Vault.

Relevant remote checks indicate the function, RPC, Vault helper, and required permissions are all present. The failure occurs at runtime when the function attempts to write the secret.

---

## Security Considerations

This issue concerns secret persistence in Supabase Vault and must be handled carefully:

- Do not expose access tokens, refresh tokens, client secrets, or personal user data in logs or diagnostic output.
- Do not include raw token values in SQL, code comments, or bug reports.
- Do not manually execute secret-storage functions.
- Do not delete Vault secrets as part of diagnosis.
- Keep the investigation limited to metadata, function existence, permissions, and error semantics.
- Do not infer or disclose personal data from the OAuth callback outcome.

The investigation should remain focused on the database constraint and idempotency behavior, not on user identities or token content.

---

## Recommended Diagnostic SQL Queries

The following queries are appropriate for a controlled, read-only investigation in the Supabase Dashboard SQL editor. They do not perform writes and do not execute the secret storage functions.

### 1. Confirm schema and function existence

```sql
SELECT
  routine_schema,
  routine_name,
  security_definer,
  routine_definition IS NOT NULL AS has_definition
FROM information_schema.routines
WHERE routine_schema IN ('public', 'vault')
  AND routine_name IN ('store_vault_secret', 'get_vault_secret', 'create_secret');
```

### 2. Confirm Vault schema presence

```sql
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name = 'vault';
```

### 3. Confirm function definitions are present

```sql
SELECT
  routine_schema,
  routine_name,
  specific_name,
  routine_definition
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN ('store_vault_secret', 'get_vault_secret');
```

### 4. Confirm permissions metadata

```sql
SELECT
  n.nspname AS schema_name,
  p.proname AS function_name,
  p.proargnames,
  pg_get_function_identity_arguments(p.oid) AS arguments,
  p.prosecdef AS is_security_definer
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('store_vault_secret', 'get_vault_secret');
```

### 5. Inspect Vault secret table metadata without reading values

```sql
SELECT
  table_schema,
  table_name,
  column_name,
  data_type
FROM information_schema.columns
WHERE table_schema = 'vault'
  AND table_name = 'secrets';
```

These queries are intentionally limited to metadata and structure. They do not read secret contents and do not trigger storage operations.

---

## Safe Fix Strategy

The safe fix strategy is narrow, reversible, and focused on the duplicate-key behavior. The likely objective is to make the Vault write idempotent when the same logical secret is being stored repeatedly.

Recommended principles:

- keep the existing public RPC contract unchanged unless a strict, necessary change is required
- treat the storage issue as a unique-constraint/idempotency problem rather than broad OAuth logic failure
- verify whether the same logical secret name is being reused across retries
- prefer an update-or-create pattern for the same logical secret instead of a blind create-only insert
- keep the fix limited to the Vault helper and/or the calling flow
- validate the fix in a non-production environment or on a controlled target before any broad rollout

This is the safest path because the issue has already been localized to the storage layer, and the contract of `public.store_vault_secret` is known to be used by the Google OAuth callback path.

Important: This strategy is intentionally constrained and does not include schema changes, migration execution, direct Vault manipulation, or secret deletion.

---

## Testing Checklist

Use this checklist once a fix is approved and implemented in a controlled environment:

- [ ] Verify the OAuth flow starts successfully.
- [ ] Verify the callback reaches the token exchange step.
- [ ] Verify the function calls `public.store_vault_secret`.
- [ ] Verify the first storage attempt succeeds.
- [ ] Repeat the same OAuth flow for the same user.
- [ ] Confirm the second attempt does not trigger PostgreSQL `23505`.
- [ ] Confirm the app does not receive `vault_storage_failed`.
- [ ] Confirm no duplicate secret records are created for the same logical secret key.
- [ ] Confirm `user_integrations` or related OAuth metadata still updates correctly.
- [ ] Confirm no tokens or personal information are logged in runtime output.
- [ ] Confirm no rollback or cleanup is required after successful validation.

---

## Rollback Considerations

If a fix is implemented and later proves unstable, rollback should be narrow and reversible:

- revert only the Vault storage idempotency change
- avoid broad rollback of the OAuth flow or unrelated migrations
- do not delete or rotate existing Vault secrets during rollback unless there is a very specific operational requirement
- preserve the current function contract and callback flow while restoring the previous behavior
- re-test the same retry scenario before re-enabling broader OAuth usage

Rollback should remain limited to the duplicate-key fix path. The goal is to restore the previous behavior without deleting data or broadening the blast radius.

---

## Conclusion

The evidence confirms a Vault-storage-level uniqueness failure in the Google OAuth callback path. The function `google-auth` is active, version `5` is deployed, and the runtime is reaching `public.store_vault_secret` before failing with HTTP `409` and PostgreSQL `23505`.

The issue is clearly a duplicate-key rejection during secret persistence, and the most likely underlying cause is repeated or conflicting secret naming in a uniqueness-enforced Vault storage flow. The exact constraint name remains unconfirmed because the output is truncated, and the investigation should continue without guessing at that object name.

The recommended next step is a narrow, read-only metadata investigation and a carefully scoped idempotency fix in the Vault storage path, with no code, schema, or function changes made until that review is complete.
