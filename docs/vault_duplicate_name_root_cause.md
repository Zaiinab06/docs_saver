# Vault Duplicate Name Root Cause Report

Project: DocsSaver / Second Brain  
Supabase project ref: `vsqzsirrdkaxjdqmmwac`  
Scope: Local code inspection only; no code, schema, SQL, or remote function changes were made.

## Executive Summary

The local Google OAuth callback generates the Vault secret name deterministically as:

```text
google_rf_<user_id>
```

Specifically, `supabase/functions/google-auth/index.ts` passes:

```ts
new_name: `google_rf_${user_id}`
```

to `public.store_vault_secret`.

The local SQL migration defines `public.store_vault_secret` as a thin wrapper around `vault.create_secret`. It does not look up an existing Vault secret by name, update an existing secret, or use the existing `user_integrations.vault_refresh_token_id` to select an existing secret. Therefore, every callback that receives a non-empty new refresh token attempts a new Vault create using the same per-user name.

Because the remote Vault index enforces uniqueness on `vault.secrets.name` through `secrets_name_idx`, a later create using the same name can fail with PostgreSQL `23505` (`unique_violation`).

The design is conditional rather than unconditional:

- First authorization with a refresh token: creates a Vault secret.
- Re-authorization with a new refresh token: calls the create-only RPC again with the same name and can produce the duplicate-name failure.
- Re-authorization without a new refresh token: does not call the storage RPC and preserves the existing `vault_refresh_token_id`.

## Confirmed Facts

The following facts are confirmed by the supplied remote evidence and the local source inspection:

- The remote Vault table is `vault.secrets`.
- The remote unique index is `secrets_name_idx`.
- The unique column is `vault.secrets.name`.
- The observed database error is PostgreSQL `23505`, a duplicate-key/unique-violation error.
- The affected RPC is `public.store_vault_secret(new_secret, new_name, new_description)`.
- The deployed Edge Function involved in the failure is `google-auth`.
- The local migration defines `public.store_vault_secret` with `SECURITY DEFINER`.
- The local migration defines `public.get_vault_secret` with `SECURITY DEFINER`.
- The local migration declares `user_integrations.vault_refresh_token_id UUID REFERENCES vault.secrets(id) ON DELETE SET NULL`.
- The local migration enforces one integration row per user and provider with `UNIQUE (user_id, provider)`.
- The remote RPC call receives `new_name` from the Edge Function; the migration does not generate the name.
- The Edge Function reads `vault_refresh_token_id` from the existing `user_integrations` row before token storage.
- The Edge Function writes the selected Vault ID back to `user_integrations.vault_refresh_token_id` during its upsert.
- The Edge Function reads the stored ID later for token retrieval and disconnect/revocation flows.

No token values, client secrets, or personal information are needed to establish these facts.

## Code Findings

### 1. Exact `new_name` generation

In [supabase/functions/google-auth/index.ts](../supabase/functions/google-auth/index.ts#L331-L347), the callback calls the RPC with:

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

The name is therefore:

```text
google_rf_ + user_id
```

It is deterministic and stable for a given user. There is no timestamp, random suffix, OAuth state value, or existing Vault ID in the name.

A repository-wide search found no other local generator for `google_rf_` or another `new_name` passed to `store_vault_secret`. The source of the name is the callback code above.

### 2. Existing integration is read before storage

In [supabase/functions/google-auth/index.ts](../supabase/functions/google-auth/index.ts#L317-L334), the callback reads:

```ts
.select("vault_refresh_token_id, account_email, account_name")
.eq("user_id", user_id)
.eq("provider", "google_drive")
.maybeSingle();
```

It initializes the local reference with the existing ID:

```ts
let vaultSecretId = existingIntegration?.vault_refresh_token_id ?? null;
```

This is useful for preserving a previously stored secret when Google does not return a new refresh token. However, when a new refresh token is present, the code does not pass that existing ID to `store_vault_secret` and does not use it to update the existing Vault row.

### 3. The SQL helper is create-only

In [supabase/migrations/20260920163000_create_oauth_sessions_and_user_integrations.sql](../supabase/migrations/20260920163000_create_oauth_sessions_and_user_integrations.sql#L79-L98), the helper is:

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

The function always calls `vault.create_secret`. It does not:

- query `vault.secrets` by `name`
- query `user_integrations` by user/provider
- accept an existing secret ID
- update an existing Vault secret
- handle a duplicate-name conflict
- return the existing secret ID after a conflict

### 4. The stored ID is persisted and read later

The callback upserts `vault_refresh_token_id: vaultSecretId` into `user_integrations` in [supabase/functions/google-auth/index.ts](../supabase/functions/google-auth/index.ts#L376-L387).

The same function reads that ID for later operations:

- disconnect/revocation selects `vault_refresh_token_id`, then calls `get_vault_secret` and `delete_vault_secret` in [supabase/functions/google-auth/index.ts](../supabase/functions/google-auth/index.ts#L588-L640)
- Google Drive file access selects `vault_refresh_token_id`, then calls `get_vault_secret` in [supabase/functions/google-auth/index.ts](../supabase/functions/google-auth/index.ts#L716-L758)

Thus, `user_integrations.vault_refresh_token_id` is the application’s reference to the Vault row. It is not currently used to make the storage operation idempotent.

## Why the Same Name Can Be Inserted More Than Once

The name is intentionally stable per user, but the storage operation is not idempotent:

1. A callback receives a non-empty `refreshToken`.
2. The function constructs `google_rf_<user_id>`.
3. The function calls `public.store_vault_secret`.
4. The RPC calls `vault.create_secret` unconditionally.
5. Vault attempts to create a row with that name.
6. A later callback for the same user can repeat steps 1 through 5.
7. The second create conflicts with the unique index on `vault.secrets.name`.

The existing `vault_refresh_token_id` does not stop the second create because the ID is only initialized locally and later written to `user_integrations`; it is not supplied to the RPC and is not consulted by the SQL helper.

## Does Every OAuth Retry Create a New Vault Secret?

Not every retry unconditionally. The exact behavior is conditional on whether Google returns a new refresh token.

### Retry with a new refresh token

Yes. Each such retry enters:

```ts
if (refreshToken) {
  // call store_vault_secret
}
```

and calls the create-only `public.store_vault_secret` using the same `google_rf_<user_id>` name. Therefore, the current design attempts to create a new Vault secret on every OAuth callback that contains a non-empty refresh token, including repeated authorization attempts for the same user.

### Retry without a new refresh token

No. The storage RPC is skipped. The previously read `existingIntegration.vault_refresh_token_id` is preserved and then written back during the integration upsert.

This distinction matters because Google OAuth commonly does not return a refresh token on every subsequent authorization. The duplicate-name failure specifically requires a callback that reaches the storage branch with a refresh token while the deterministic name already exists.

## `user_integrations` Storage and Read Behavior

The migration defines:

```sql
vault_refresh_token_id UUID REFERENCES vault.secrets(id) ON DELETE SET NULL
```

The callback reads the field before storage and upserts it afterward. The application also reads it for:

- decrypting the refresh token through `get_vault_secret`
- revoking the Google token during disconnect
- deleting the Vault secret during disconnect
- refreshing Google access for Drive operations

Confirmed conclusion: an existing Vault secret ID is stored in `user_integrations`, but the current create path does not reuse that ID when a new refresh token arrives.

## Assumptions and Unconfirmed Details

The following are working assumptions, not independently confirmed facts:

- The duplicate conflict is caused specifically by the repeated `name` value `google_rf_<user_id>`.
- The conflicting row belongs to the same user represented by the current OAuth callback.
- The duplicate occurs on a retry or re-authorization rather than another caller using the same naming convention.
- The intended product behavior is to keep one current Google refresh token per user/provider.
- The Vault installation exposes a supported update mechanism suitable for changing the encrypted value while preserving the secret ID.

The first assumption is strongly supported by the deterministic name, the remote unique index on `name`, and the create-only helper, but it should still be confirmed against the complete remote error context or controlled metadata inspection. No exact constraint name beyond the verified `secrets_name_idx` should be inferred.

## Safe Fix Options

### Option A: Reuse or update the existing secret

Preferred when the product intends one current Google refresh token per user/provider.

Possible design:

- use the existing `user_integrations.vault_refresh_token_id` when available
- update the existing Vault secret value through a supported Vault-safe operation
- preserve the existing secret ID in `user_integrations`
- create a new secret only when no existing integration/secret reference exists
- keep the operation protected by the existing service-role and `SECURITY DEFINER` boundaries

An alternative is to make `public.store_vault_secret` idempotent by name, but that function must handle concurrent callbacks safely. A simple check-then-create sequence can still race: two callbacks can both observe no row and then both attempt to create the same name. Any implementation should use an atomic or conflict-aware strategy supported by the installed Vault schema and function APIs.

Advantages:

- preserves the stable name and existing reference model
- avoids accumulating obsolete duplicate secrets
- keeps `user_integrations` pointing to one logical secret
- minimizes changes to the OAuth caller contract

Risks to validate:

- the supported Vault update API and its permissions
- whether updating a Vault row directly is supported by the project’s Vault version
- concurrent callback behavior
- behavior when `user_integrations` references a missing or deleted Vault row

### Option B: Generate a unique name for every new secret

This would append a unique value to each name, such as a generated identifier, and would avoid the name collision.

Advantages:

- avoids the unique-name conflict for each create
- requires less change to the create-only helper

Risks:

- creates a new Vault secret on every token rotation or retry
- leaves old secrets unless a separate cleanup process removes them
- can cause unbounded Vault row growth
- requires reliable cleanup and careful reference updates
- may leave orphaned secrets if the later `user_integrations` upsert fails
- does not align naturally with the existing deterministic per-user name or the existing stored-ID model

This option should not be the default fix for the current design. It solves the index collision by creating more records, but it introduces lifecycle and cleanup problems.

### Option C: Avoid automatic deletion and defer cleanup

Regardless of the chosen storage strategy:

- do not delete Vault secrets automatically as part of duplicate-key recovery
- do not delete the existing secret before the replacement is confirmed and referenced
- do not delete secrets merely because a create attempt failed
- preserve existing `vault_refresh_token_id` until a replacement is known to be valid
- use a separately reviewed, read-only inventory and an explicit cleanup process for confirmed orphaned records

This protects the currently referenced credential and avoids data loss during recovery.

## Recommended Next Implementation Step

The recommended next step is a narrowly scoped design and migration review for an idempotent update-or-create operation:

1. Confirm the supported, encrypted Vault update mechanism for the deployed Supabase Vault version.
2. Decide whether the canonical identity is the existing `user_integrations.vault_refresh_token_id`, the stable per-user name, or both.
3. Implement an atomic conflict-aware helper that updates/reuses the existing secret when appropriate and creates one only when no valid existing secret exists.
4. Keep the deterministic name `google_rf_<user_id>` unless there is a deliberate lifecycle reason to change it.
5. Preserve the existing `user_integrations.vault_refresh_token_id` reference when updating.
6. Handle concurrent OAuth callbacks without relying on a non-atomic check followed by create.
7. Add a focused test for repeated OAuth callbacks with a new refresh token.
8. Test the no-new-refresh-token path to ensure the existing ID remains unchanged.
9. Test failure between Vault storage and the integration upsert without deleting the existing secret.

No implementation should be applied until the supported Vault update API and concurrency behavior are verified. The next implementation should be limited to the helper/callback contract required for idempotent storage; unrelated OAuth, schema, and cleanup behavior should remain unchanged.

## Testing Checklist

After an approved implementation, validate:

- [ ] First authorization with a new refresh token creates one Vault secret.
- [ ] Re-authorization with a new refresh token does not produce `23505`.
- [ ] Re-authorization updates or reuses the intended existing secret.
- [ ] The same Vault secret is not duplicated by concurrent callback attempts.
- [ ] `user_integrations.vault_refresh_token_id` points to the intended secret after success.
- [ ] Authorization without a new refresh token preserves the existing ID.
- [ ] Token retrieval through `get_vault_secret` still works.
- [ ] Disconnect/revocation still uses the stored ID correctly.
- [ ] A failed storage attempt does not delete the existing secret.
- [ ] No token values, client secrets, or personal information appear in logs or test output.

## Change Safety Boundaries

For this investigation and the proposed next step:

- no local files other than this report were modified
- no SQL writes were executed
- no Vault secret-storage function was manually executed
- no Vault secrets were deleted
- no application code, migration, database schema, or Supabase Edge Function was deployed or changed
- no secret values were inspected or included in this report
