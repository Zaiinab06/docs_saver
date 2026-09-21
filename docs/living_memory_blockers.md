# Living Memory Implementation Blockers

Status: blocked pending read-only verification of the deployed Supabase schema.

No Living Memory migration has been created or applied. No mock data, synthetic memories, or placeholder UI has been added.

## Verified Repository Evidence

The repository contains these Supabase migrations:

- `20260915153526_match_memories_v2.sql`
- `20260916140000_hybrid_search_memories.sql`
- `20260920134800_match_memories_v2_fallback.sql`
- `20260920163000_create_oauth_sessions_and_user_integrations.sql`
- `20260921120000_make_store_vault_secret_idempotent.sql`
- `20260921153000_fix_store_vault_secret_definer_permissions.sql`

The first three migrations reference an existing `public.memories` table and define or update search objects. They do not define the base `memories` table.

The repository contains table DDL and RLS for `oauth_sessions` and `user_integrations`, but no checked-in DDL or policies for `memories`.

Flutter code expects memory fields including identifiers, ownership, title/content, media URL, tags, category, embedding, AI status, conflict state, client/server timestamps, and sync state. These are application expectations, not verified production schema evidence.

There are no generated Supabase database types containing `memories` or Living Memory tables. There is no checked-in `supabase/config.toml` providing a schema definition. The linked project metadata identifies a Supabase project, but it is not a schema snapshot.

## Missing Database Evidence

Before creating Living Memory migrations, obtain read-only catalog evidence for the deployed project covering:

1. Exact `public.memories` columns, types, nullability, defaults, and generated values.
2. Primary key definition and whether `id` is UUID.
3. Foreign keys, especially whether `user_id` references `auth.users(id)`.
4. Existing unique constraints and check constraints.
5. RLS enabled status for `public.memories`.
6. Existing `SELECT`, `INSERT`, `UPDATE`, and `DELETE` policies, including their roles and expressions.
7. Existing triggers and trigger functions on `public.memories`.
8. Existing indexes, including the deployed embedding index and its vector dimension.
9. Existing RPC signatures and grants for `match_memories`, `match_memories_v2`, and `search_memories_text`.
10. Existing storage policies relevant to memory media.
11. Existing row counts and data-quality checks needed before adding foreign keys or not-null constraints.
12. Existing migration history and whether production contains migrations absent from this repository.

Do not infer any of these from Flutter models, Edge Function payloads, comments, or RPC return types.

## Why Migration Creation Is Blocked

The requested `memory_versions`, `memory_relationships`, `memory_evidence`, and `memory_freshness` tables require foreign keys, ownership policies, delete behavior, and transaction boundaries tied to the real `memories` schema. Without that schema, any migration could:

- reference the wrong key type or column name;
- weaken or conflict with existing RLS;
- break semantic-search RPC dependencies;
- create unsafe cascade behavior;
- fail against existing production data; or
- preserve an incorrect ownership model.

A review-ready SQL draft is therefore not safe to produce from the current repository evidence.

## Current Security Preparation

`supabase/functions/process-ingestion/index.ts` has been hardened without changing database schema:

- Requests require a valid Supabase Bearer token.
- The authenticated user ID is derived from the verified token.
- A request `user_id` cannot differ from the authenticated user.
- Existing target memories are loaded and ownership-checked before service-role processing.
- The bulk `reembed_all` action is disabled until an explicit administrative authorization boundary exists.

Static diagnostics pass for the changed Edge Function. Deno-based authorization tests have not run because Deno is unavailable. Live RLS and integration tests have not run.

## Safe Next Steps

1. Install Docker Desktop or Podman, or use the Supabase Dashboard SQL Editor with read-only catalog queries.
2. Produce a metadata-only schema report. Do not include memory content, tokens, service-role keys, or decrypted secrets.
3. Compare the deployed schema with all checked-in migrations and record any drift.
4. Verify `process-ingestion` deployment JWT settings and test its ownership boundary against a real Supabase test project.
5. Add or generate authoritative database types from the verified schema.
6. Only then design a migration that preserves the existing `memories` table and semantic-search RPC contracts.
7. Run migration/RLS/concurrency tests in a disposable Supabase environment before any production application.

## Current Readiness

Living Memory database foundation: not implemented.

Living Memory versioned writes: not implemented.

Living Memory relationships, evidence, and freshness: not implemented.

Living Memory Flutter UI/cache: not implemented.

Existing Google Drive/Google Docs integration: unchanged.

Production readiness: not claimed.
