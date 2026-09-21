# Google Vault Idempotent Fix Proposal

Project: DocsSaver / Second Brain  
Supabase project ref: `vsqzsirrdkaxjdqmmwac`  
Status: Proposal only. No SQL was executed, no migration was applied, no Vault function was called, and no production file was modified.

## Confirmed Facts

- The production failure is `vault_storage_failed` from the Google OAuth callback.
- The failing RPC is `public.store_vault_secret`.
- PostgreSQL returns HTTP `409` with SQLSTATE `23505` because `vault.secrets.name` is protected by the unique index `secrets_name_idx`.
- The Google OAuth callback constructs the deterministic name `google_rf_${user_id}`.
- The current helper calls `vault.create_secret` on every request.
- The deployed Vault API provides `vault.update_secret(uuid, text, text, text, uuid)` and returns `void`.
- `vault.update_secret` is `SECURITY DEFINER` and executable by `service_role`; `anon` and `authenticated` cannot execute it.
- The current public helper is `SECURITY DEFINER`, uses `SET search_path = ''`, and grants execution only to `service_role`.
- `public.user_integrations.vault_refresh_token_id` references `vault.secrets(id)`.
- `user_integrations` enforces one row per `(user_id, provider)`.
- The current Edge Function reads `vault_refresh_token_id` but does not pass it to `store_vault_secret`.
- The current `store_vault_secret` contract is:

```text
public.store_vault_secret(new_secret text, new_name text, new_description text) returns uuid
```

## Current Limitation

The existing RPC does not receive `vault_refresh_token_id`. Therefore, it cannot directly call:

```text
vault.update_secret(
  existing_secret_id,
  new_secret,
  new_name,
  new_description,
  new_key_id
)
```

using the ID already stored in `user_integrations`.

There are two possible designs:

1. Preserve the existing RPC contract and resolve the existing Vault ID inside the helper by the stable unique name `google_rf_${user_id}`.
2. Change the RPC contract or add a separate helper that accepts an existing Vault UUID, requiring a corresponding Edge Function change.

The first option minimizes application changes. The second option makes the existing integration reference explicit and may be preferable if name-to-ID consistency must be strictly validated.

## Proposed Migration SQL

The following is proposed SQL only. It is not applied and must not be executed until reviewed, tested, and approved.

### Preferred contract-preserving approach

This version keeps the existing three-argument RPC contract. It serializes callbacks for the same name with a transaction-scoped advisory lock, looks up the existing Vault row by its unique name, updates it when found, and creates it only when absent.

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
    IF new_name IS NULL OR new_name = '' THEN
        SELECT vault.create_secret(new_secret, new_name, new_description, NULL)
        INTO secret_id;

        RETURN secret_id;
    END IF;

    -- Serialize create/update operations for the same logical Vault name.
    PERFORM pg_advisory_xact_lock(hashtextextended(new_name, 0));

    SELECT id
    INTO secret_id
    FROM vault.secrets
    WHERE name = new_name
    FOR UPDATE;

    IF secret_id IS NOT NULL THEN
        PERFORM vault.update_secret(
            secret_id,
            new_secret,
            new_name,
            new_description,
            NULL
        );

        RETURN secret_id;
    END IF;

    SELECT vault.create_secret(new_secret, new_name, new_description, NULL)
    INTO secret_id;

    RETURN secret_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.store_vault_secret(TEXT, TEXT, TEXT)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.store_vault_secret(TEXT, TEXT, TEXT)
TO service_role;
```

### Required review points for the proposed SQL

The SQL above is a design proposal, not a claim that it is ready for production. Before applying it, verify:

- `vault.create_secret` accepts `NULL` for its fourth `uuid` key-ID argument.
- `vault.update_secret` accepts `NULL` for its fifth `uuid` key-ID argument and preserves the existing encryption key as intended.
- The `service_role` execution context can read the required non-secret metadata from `vault.secrets`.
- `pg_advisory_xact_lock` is permitted in the deployment and is appropriate for this transaction boundary.
- `FOR UPDATE` is valid for the deployed `vault.secrets` relation.
- The Vault update operation does not change the secret UUID.
- A duplicate-name conflict cannot still occur through another writer that does not take the same advisory lock.
- The `vault.create_secret` four-argument signature is the exact deployed signature.

If any of these checks fail, do not apply this SQL unchanged.

## Alternative RPC Contract

If the existing Vault UUID must be passed explicitly, introduce a separately reviewed RPC contract rather than silently changing the meaning of the current one. For example, the helper could accept an additional optional ID, but adding a parameter changes PostgreSQL function identity and may affect PostgREST RPC resolution.

A safer design review question is whether to add a new named helper, such as a project-specific update-or-create operation, while retaining the current three-argument RPC for compatibility. The exact name and signature should be selected only after reviewing all callers and the deployed PostgREST behavior.

Conceptually, the helper would:

1. Receive the existing `vault_refresh_token_id` when available.
2. Lock the logical user/provider or secret-name key.
3. Validate that the referenced secret exists and matches the expected name.
4. Call the officially supported `vault.update_secret` with the existing UUID.
5. Preserve that UUID in `user_integrations`.
6. Create a new secret only when no valid reference exists.

This alternative requires a corresponding Edge Function change because the current RPC invocation does not send `vault_refresh_token_id`.

## Required Edge Function Changes

### Contract-preserving option

No immediate TypeScript change is required if the helper keeps the current three-argument contract and safely resolves the existing Vault row by `google_rf_${user_id}`. The existing Edge Function call can remain structurally unchanged.

The helper would return the same UUID on update, and the current upsert would continue to write that UUID into `user_integrations.vault_refresh_token_id`.

### Explicit-ID option

A TypeScript change is required if the approved RPC accepts an existing Vault UUID or uses a separate update helper. The callback would need to pass the already-read `existingIntegration.vault_refresh_token_id` without logging its value.

That change must preserve the current behavior when no new refresh token is returned: skip storage and retain the existing reference.

## Transaction and Concurrency Considerations

- The update/create decision must be atomic with respect to other OAuth callbacks using the same logical name.
- A plain `SELECT` followed by `CREATE` is insufficient because two callbacks can both observe no row and then race to create it.
- A transaction-scoped advisory lock keyed by the stable name is one possible serialization mechanism, subject to deployment review.
- Any alternative must protect both the lookup/update path and the create path.
- The integration upsert occurs after Vault storage in the current Edge Function. A successful Vault update followed by a failed integration upsert should not delete the existing secret.
- If a new secret is created and the later integration upsert fails, recovery must preserve the secret and classify it for controlled review rather than automatically deleting it.
- The design should preserve the existing Vault UUID on update so references remain stable.
- The helper must not rely on client roles or client-provided authorization for Vault access.

## Security Requirements

- Retain `SECURITY DEFINER`.
- Retain `SET search_path = ''`.
- Retain service-role-only execution.
- Do not grant Vault update or storage access to `anon` or `authenticated`.
- Do not log access tokens, refresh tokens, authorization codes, client secrets, or secret values.
- Do not include secret values in SQL comments, test fixtures, error messages, or diagnostics.
- Do not expose decrypted Vault data through the RPC response.
- Do not delete Vault secrets automatically.

## Why Unique Names Per Retry Are Not Recommended

Generating a random name for every OAuth callback would avoid `secrets_name_idx`, but it would create an unbounded secret lifecycle problem. Old records could become orphaned when an integration upsert fails, and cleanup would require additional sensitive deletion logic.

The preferred design is one logical current secret per user/provider, with the existing UUID preserved during update.

## Required Tests

### First authorization

- No existing integration or valid Vault reference.
- A new secret is created once.
- The returned UUID is stored in `user_integrations`.
- The callback completes successfully.

### Repeated authorization with a new refresh token

- An existing `vault_refresh_token_id` and matching stable name are present.
- The helper calls `vault.update_secret`, not `vault.create_secret`.
- The UUID remains unchanged.
- No `23505` or `vault_storage_failed` occurs.

### Authorization without a new refresh token

- The storage RPC is not called.
- The existing `vault_refresh_token_id` is preserved.
- The callback can complete using the existing reference.

### Concurrent OAuth callbacks

- Two callbacks use the same user and stable name concurrently.
- At most one secret row exists for that name.
- Both successful paths resolve to the same intended UUID.
- No duplicate-name error occurs.

### Failed integration upsert

- Vault update/create succeeds but the metadata upsert fails.
- The existing secret is not deleted.
- The failure is observable without exposing the secret value.
- Recovery does not blindly create another secret.

### Refresh-token retrieval

- `get_vault_secret` reads the referenced UUID through the privileged path.
- The operation succeeds without returning or logging the secret value in diagnostic output.
- Google Drive operations continue to use the preserved UUID.

## Rollback Plan

If the migration causes a regression:

1. Stop further rollout and preserve all Vault rows.
2. Revert only the helper definition through an approved rollback migration.
3. Restore the prior create-only helper only if that is the explicitly approved rollback behavior.
4. Do not delete secrets, rotate credentials, or recreate names during rollback.
5. Re-test first authorization, repeated authorization, no-new-token authorization, retrieval, and disconnect flows.
6. Review any records created during a failed rollout through metadata-only inspection before any separately approved cleanup.

Rollback must not erase the existing `user_integrations.vault_refresh_token_id` reference or delete its referenced secret automatically.

## Confirmed Facts

- `vault.update_secret(uuid, text, text, text, uuid)` exists, returns `void`, is `SECURITY DEFINER`, and is executable by `service_role` only among the reviewed roles.
- `public.store_vault_secret` currently calls `vault.create_secret` only.
- The repeated name is `google_rf_${user_id}`.
- `vault.secrets.name` has a unique index, causing PostgreSQL `23505` on the repeated create.
- The current Edge Function reads an existing Vault ID but does not pass it to the RPC.

## Proposed Migration SQL

The contract-preserving `CREATE OR REPLACE FUNCTION` block above is the proposed migration SQL. It is not applied, executed, or validated against the production database in this document.

## Required Edge Function Changes

- None are required if the existing three-argument RPC remains and resolves by stable name under a reviewed, concurrency-safe implementation.
- A TypeScript change is required if the approved design passes `vault_refresh_token_id` explicitly or introduces a separate RPC.

## Risks and Unresolved Questions

- Whether `NULL` is valid for the `new_key_id` parameter in both deployed Vault functions.
- Whether direct metadata lookup and row locking on `vault.secrets` are supported under the deployed Vault permissions and relation type.
- Whether all writers use the same advisory-lock convention.
- How to reconcile an existing integration UUID whose Vault name does not match `google_rf_${user_id}`.
- Whether changing or adding an RPC signature affects PostgREST function resolution.
- Whether the current migration’s create-only behavior has already produced orphaned records requiring a separately approved inventory review.

## Testing Plan

Use a controlled environment and the actual app before claiming resolution. The complete OAuth flow must succeed for first authorization, repeated authorization with a new refresh token, authorization without a new refresh token, concurrent callbacks, failed integration upsert, and refresh-token retrieval. No token or secret value should appear in logs or test output.

## Current Status

This is a review proposal only. No SQL was executed, no migration was applied, no Vault function was called, no existing migration or Edge Function was modified, and no deployment occurred. The duplicate-key issue remains diagnosed but is not claimed to be fixed.
