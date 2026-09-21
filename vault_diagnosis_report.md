## Read-only remote Supabase / Vault diagnosis

### Confirmed findings
- The migration list confirms the OAuth migration is present on the linked remote project:
  - [supabase/migrations/20260920163000_create_oauth_sessions_and_user_integrations.sql](supabase/migrations/20260920163000_create_oauth_sessions_and_user_integrations.sql)
- Evidence: `npx supabase migration list` returned the migration entry for `20260920163000` as `remote: 20260920163000`.

### Exact code path causing `vault_storage_failed`
The error is raised in the callback handler in [supabase/functions/google-auth/index.ts](supabase/functions/google-auth/index.ts#L294-L347).

The flow is:

1. After Google redirects back to the callback, the function validates the OAuth state and exchanges the code for tokens:
   - [supabase/functions/google-auth/index.ts](supabase/functions/google-auth/index.ts#L218-L289)

2. It reads the refresh token from the Google token response:
   - [supabase/functions/google-auth/index.ts](supabase/functions/google-auth/index.ts#L294-L297)

3. Then it attempts to store that refresh token in Supabase Vault:
   - [supabase/functions/google-auth/index.ts](supabase/functions/google-auth/index.ts#L331-L347)

The exact failure condition is:

- `const { data: newSecretId, error: vaultErr } = await supabaseAdmin.rpc("store_vault_secret", ...)`
- if `vaultErr || !newSecretId`, it returns:
  - `secondbrain://oauth/callback?status=error&reason=vault_storage_failed`

This is the exact source of the user-facing error.

---

### What is supported by evidence
The following is strongly supported:

- The failure happens after OAuth succeeds far enough to receive a refresh token and before the integration row is written.
- The failing operation is not a Flutter-side issue; it is the server-side Vault insertion path in the Edge Function.
- The database migration defines the required Vault helper functions:
  - [supabase/migrations/20260920163000_create_oauth_sessions_and_user_integrations.sql](supabase/migrations/20260920163000_create_oauth_sessions_and_user_integrations.sql#L79-L118)

The migration defines:
- `public.store_vault_secret`
- `public.get_vault_secret`

and grants execution to `service_role`.

---

### What could not be confirmed in this environment
The direct metadata check against the remote Postgres objects was not possible from this machine because the CLI attempted to connect to the local Supabase Postgres instance and failed with:
- `connect ECONNREFUSED 127.0.0.1:54322`
- suggestion: `Make sure Docker is running, then run: supabase start`

So the following remain unverified from this environment:
- whether the vault schema is present in the remote DB
- whether `vault.create_secret` exists remotely
- whether the RPC is callable with service-role rights
- whether the remote DB object signature matches exactly

This means we cannot honestly claim the remote Vault metadata is confirmed, only that the code expects it and the migration is present.

---

### Likely root cause
The strongest evidence-based likely root cause is:
- a remote Supabase Vault / RPC runtime failure while persisting the Google refresh token, not a Flutter bug and not the `start_picker` routing bug

This is consistent with:
- the exact error branch in [supabase/functions/google-auth/index.ts](supabase/functions/google-auth/index.ts#L331-L347)
- the migration-created Vault helper definition in [supabase/migrations/20260920163000_create_oauth_sessions_and_user_integrations.sql](supabase/migrations/20260920163000_create_oauth_sessions_and_user_integrations.sql#L79-L118)
- the safety test that explicitly models this failure path:
  - [test/google_oauth_callback_safety_test.dart](test/google_oauth_callback_safety_test.dart#L199-L211)

---

### Safe error message observed
The safe application-level error is:
- `vault_storage_failed`

That is the message returned by the Edge Function, and it was the observed runtime symptom.

---

### Smallest safe remediation
The smallest safe remediation is not a code change; it is a remote DB/Vault validation step:

1. Confirm the remote project migration is applied
2. Confirm the Vault schema and `vault.create_secret` exist in the project DB
3. Confirm the `public.store_vault_secret` function exists and is callable with service-role permissions
4. Confirm the Google callback flow is not hitting a mismatched redirect or missing secret issue
5. Re-run the OAuth callback only after Vault + DB metadata are confirmed

This should be done without changing app code unless the remote DB/Vault is confirmed to be misconfigured.

> No code changes were made here. This is a read-only diagnosis based on the exact runtime branch that emits `vault_storage_failed`.

---

## Read-only SQL for Supabase Dashboard SQL Editor

### 1) Check whether the `vault` schema exists
```sql
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name = 'vault';
```

What it checks:
- Whether the Vault schema exists in the remote database.

Read-only:
- Yes.

Interpretation:
- If it returns one row, Vault is installed.
- If it returns zero rows, the Vault schema is missing and Vault-dependent RPCs will fail.

---

### 2) Check whether `vault.create_secret` exists
```sql
SELECT
  routine_schema,
  routine_name,
  specific_name,
  data_type
FROM information_schema.routines
WHERE routine_schema = 'vault'
  AND routine_name = 'create_secret';
```

What it checks:
- Whether the Vault secret creation function exists.

Read-only:
- Yes.

Interpretation:
- If it returns a row, the vault-backed secret constructor exists.
- If it returns no rows, the Vault object required by `public.store_vault_secret` is missing or not enabled.

---

### 3) Check whether `public.store_vault_secret` exists
```sql
SELECT
  specific_schema,
  specific_name,
  routine_name,
  routine_schema,
  data_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name = 'store_vault_secret';
```

What it checks:
- Whether the RPC exists and what its internal signature metadata reports.

Read-only:
- Yes.

Interpretation:
- If it returns a row, the function exists.
- If no row appears, the migration-created function is missing or not visible in the current database.

---

### 4) Check whether `public.get_vault_secret` exists
```sql
SELECT
  specific_schema,
  specific_name,
  routine_name,
  routine_schema,
  data_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name = 'get_vault_secret';
```

What it checks:
- Whether the decryption helper RPC exists.

Read-only:
- Yes.

Interpretation:
- If it returns a row, the function is present.
- If no row appears, the remote DB is missing this migration-created helper.

---

### 5) Inspect the argument signatures of both RPC functions
```sql
SELECT
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS arguments,
  pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('store_vault_secret', 'get_vault_secret');
```

What it checks:
- The actual Postgres function signatures and definitions.

Read-only:
- Yes.

Interpretation:
- This confirms whether the functions have the expected parameter list, such as:
  - `store_vault_secret(TEXT, TEXT, TEXT)`
  - `get_vault_secret(UUID)`
- If the signature differs, the caller may fail even if the function exists.

---

### 6) Check whether the functions are `SECURITY DEFINER`
```sql
SELECT
  n.nspname AS schema_name,
  p.proname AS function_name,
  p.prosecdef AS is_security_definer
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('store_vault_secret', 'get_vault_secret');
```

What it checks:
- Whether the RPCs are defined with `SECURITY DEFINER`.

Read-only:
- Yes.

Interpretation:
- `prosecdef = true` means the function runs with the definer’s privileges.
- If the expected functions are not marked as `SECURITY DEFINER`, they may not be able to access Vault as intended.

---

### 7) Check EXECUTE permissions for `service_role`
```sql
SELECT
  n.nspname AS schema_name,
  p.proname AS function_name,
  has_function_privilege('service_role', quote_ident(n.nspname) || '.' || quote_ident(p.proname), 'EXECUTE') AS service_role_can_execute
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('store_vault_secret', 'get_vault_secret');
```

What it checks:
- Whether the `service_role` role has EXECUTE permission on the RPCs.

Read-only:
- Yes.

Interpretation:
- If it returns `false`, the Edge Function cannot run this RPC even if the function exists.
- This is a strong signal for a permission problem.

---

### 8) Check whether the migration-created objects exist in the remote database
```sql
SELECT
  'public.oauth_sessions' AS object_name,
  to_regclass('public.oauth_sessions') IS NOT NULL AS exists
UNION ALL
SELECT
  'public.user_integrations',
  to_regclass('public.user_integrations') IS NOT NULL
UNION ALL
SELECT
  'public.store_vault_secret',
  to_regprocedure('public.store_vault_secret') IS NOT NULL
UNION ALL
SELECT
  'public.get_vault_secret',
  to_regprocedure('public.get_vault_secret') IS NOT NULL
UNION ALL
SELECT
  'vault.create_secret',
  to_regprocedure('vault.create_secret') IS NOT NULL;
```

What it checks:
- Whether the migration-created schema objects and helper functions exist.

Read-only:
- Yes.

Interpretation:
- If any row is `false`, the remote project is missing required objects from the migration.
- This is the cleanest validation for whether the migration actually landed.

---

### 9) Check the migration tracking row specifically for the OAuth migration
```sql
SELECT
  version,
  name,
  inserted_at
FROM supabase_migrations.schema_migrations
WHERE version = '20260920163000';
```

What it checks:
- Whether the remote migration table records the OAuth/Vault migration as applied.

Read-only:
- Yes.

Interpretation:
- If it returns one row, the migration was applied to the connected project.
- If no row appears, the migration may not have been executed in the remote environment.

---

### 10) Safe combined metadata check for the Vault / OAuth dependency set
```sql
SELECT
  'vault schema' AS check_name,
  EXISTS (
    SELECT 1 FROM information_schema.schemata WHERE schema_name = 'vault'
  ) AS result
UNION ALL
SELECT
  'vault.create_secret',
  EXISTS (
    SELECT 1
    FROM information_schema.routines
    WHERE routine_schema = 'vault'
      AND routine_name = 'create_secret'
  )
UNION ALL
SELECT
  'public.store_vault_secret',
  EXISTS (
    SELECT 1
    FROM information_schema.routines
    WHERE routine_schema = 'public'
      AND routine_name = 'store_vault_secret'
  )
UNION ALL
SELECT
  'public.get_vault_secret',
  EXISTS (
    SELECT 1
    FROM information_schema.routines
    WHERE routine_schema = 'public'
      AND routine_name = 'get_vault_secret'
  )
UNION ALL
SELECT
  'public.oauth_sessions',
  EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'oauth_sessions'
  )
UNION ALL
SELECT
  'public.user_integrations',
  EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'user_integrations'
  );
```

What it checks:
- The full dependency set required by the Google auth callback path.

Read-only:
- Yes.

Interpretation:
- If any row is `false`, the remote Supabase project is missing a required dependency required to complete the Vault token persistence path.

---

These queries are all metadata-only and do not query secret values, access tokens, refresh tokens, or execute any write operation.
