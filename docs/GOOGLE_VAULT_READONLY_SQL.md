# Google Vault Read-Only SQL

Project: DocsSaver / Second Brain  
Supabase project ref: `vsqzsirrdkaxjdqmmwac`

This file contains read-only PostgreSQL catalog queries for manual execution in the Supabase Dashboard SQL Editor. The queries inspect function metadata only. They do not call Vault functions and do not read Vault secret values.

Do not execute these queries through application code or an Edge Function. Run them manually in the Supabase Dashboard SQL Editor against the remote project.

## 1. List Every Vault Function

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

## 2. Find Secret, Create, Update, and Delete Functions

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

## 3. Inspect Exact Function Definitions

This query returns function definitions for metadata review. Do not copy or publish output that contains sensitive configuration or secret material.

```sql
SELECT
  n.nspname AS schema_name,
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS arguments,
  pg_get_function_result(p.oid) AS return_type,
  pg_get_functiondef(p.oid) AS function_definition
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'vault'
  AND p.proname ~* '(secret|create|update|delete)'
ORDER BY p.proname, arguments;
```

## 4. Inspect Vault Function Permissions

```sql
SELECT
  n.nspname AS schema_name,
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS arguments,
  p.proacl AS access_control_list,
  has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_can_execute,
  has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'vault'
ORDER BY p.proname, arguments;
```

## 5. Inspect Existing Public Vault Helpers

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

## 6. Inspect Public Helper Permissions

```sql
SELECT
  n.nspname AS schema_name,
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS arguments,
  p.proacl AS access_control_list,
  has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_can_execute,
  has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('store_vault_secret', 'get_vault_secret')
ORDER BY p.proname, arguments;
```

## Manual Execution Order

Run the six `SELECT` queries above manually in the Supabase Dashboard SQL Editor for project `vsqzsirrdkaxjdqmmwac`.

Use the results to determine whether an officially supported Vault update function exists. Do not infer an update API from a function name, and do not execute any returned function. No conclusion about an update function is made by this document until the catalog results are reviewed.

These queries do not insert, update, or delete rows, create or delete Vault secrets, deploy functions, or expose secret values.
