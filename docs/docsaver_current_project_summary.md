# DocsSaver Current Project Summary

## 1. Project Overview

DocsSaver is a Flutter second-brain application for capturing, organizing, searching, and reviewing personal memories.

### Technology stack

- Flutter/Dart.
- `flutter_bloc` for BLoC/Cubit state management.
- Supabase Auth, Postgres, Edge Functions, Storage, and Realtime.
- Isar for offline-first local persistence.
- Gemini-backed ingestion and embeddings.
- Google Drive/Docs OAuth integration.
- Camera, OCR, document scanning, audio, file, and link metadata tooling.

### Major modules

- `auth`: sign-up, sign-in, sign-out, and session restoration.
- `capture`: notes, photos, documents, voice, links, local cache, sync, and realtime updates.
- `brain_ai`: OCR/AI ingestion, summaries, tags, categories, and entities.
- `search`: semantic search, offline fallback, and relevance filtering.
- `home`: categories, dashboard, memory navigation, and capture entry points.
- `saved`: saved/pinned memory views.
- `integrations`: Google OAuth and Drive/Docs import.
- `navigation`: main application shell.
- `settings`: account, integration, and app information.

Application dependency wiring is centralized in `lib/main.dart`.

## 2. Completed Features

### Authentication and data isolation

Implemented through the auth data source, repository, use cases, and `AuthBloc`.

Verified capabilities include sign-up, sign-in, sign-out, session restoration, authenticated routing, logout clearing, user-scoped local reads, and user-scoped remote synchronization.

The live `public.memories` policy is:

```sql
auth.uid() = user_id
```

### Capture workflows

Implemented workflows include:

- Text notes.
- Photos and OCR.
- Document scanning and PDF imports.
- Voice recording and audio playback.
- URL and social-link capture.
- Offline-first Isar persistence.
- Remote synchronization and realtime updates.
- Supabase Storage media uploads.

### AI and ingestion

Implemented capabilities include AI title/category generation, tag extraction, semantic summaries, embeddings, voice/document ingestion, AI status tracking, and extracted `LivingEntityItem` values.

The backend ingestion function is `supabase/functions/process-ingestion/index.ts`.

### Search

Implemented capabilities include:

- Remote semantic search through the `semantic-search` Edge Function.
- PostgreSQL RPCs `match_memories`, `match_memories_v2`, and `search_memories_text`.
- Gemini query embeddings.
- Client-side semantic relevance filtering.
- Offline Isar keyword fallback.
- Token refresh and authentication handling.
- Loading, empty, error, retry, and stale-response protection.

### Google Drive/Docs

Implemented capabilities include OAuth, deep-link callbacks, integration status, Google Docs import, Drive file import, MIME handling, and error handling.

### Home and navigation

Implemented capabilities include the main tab shell, category dashboard, category detail views, saved/pinned navigation, capture bottom sheet, memory cards, empty states, onboarding routing, and theme switching.

### Analytics and monetization

The project declares `purchases_flutter`, but no active purchase implementation was found. An `ai_usage_logs` database table exists, but no confirmed user-facing analytics dashboard was found.

Status: partial/incomplete.

## 3. Living Memory Status

### Implemented locally

`RelatedMemoryMatcher` remains implemented and supports:

- Same-user filtering.
- Current-memory exclusion.
- Duplicate-ID prevention.
- Meaningful-tag matching.
- Broad/generic tag filtering.
- Category evidence.
- Scoring and result limits.
- Shared-tag and category match evidence.

`LivingEntityItem` remains part of AI ingestion results and is displayed in review/detail flows.

### Partial

AI entity extraction is available, but entities are displayed through screen state and are not persisted as graph nodes.

The “Living Memory Knowledge Graph” card is an entity/tag display concept, not a persistent graph database view.

### Removed or missing locally

The following relationship layer is no longer in the local codebase:

- `MemoryRelationship` entity and enum.
- Relationship repository and implementation.
- Supabase relationship datasource.
- Relationship extraction service/use case.
- Knowledge graph Cubit/state.
- Persistent relationship UI integration.
- Relationship-specific tests.
- Local relationship migration.
- Automatic relationship generation.

### Remote-only state

The connected Supabase project still contains `public.memory_relationships`, its indexes, constraints, and RLS policies. The local app no longer references this table, creating schema/code drift.

## 4. Recent Changes

The latest relationship implementation was removed from the local working tree.

Removed relationship-only files included the relationship entity, repository, datasource, extraction service/use case, knowledge graph Cubit/state, migration, and exclusive tests.

Relationship-only additions were also removed from `main.dart`, `SaveMemoryUseCase`, `CaptureBloc`, and `MemoryDetailScreen`.

Preserved functionality includes Search, the existing matcher, memory detail behavior, authentication, Supabase security, Home UI, capture workflows, Google integration, unrelated changes, and unrelated tests.

No Search files depended on the removed relationship symbols.

## 5. Database Status

### Live public tables

The connected Supabase project contains:

- `ai_usage_logs`
- `attributes`
- `entities`
- `memories`
- `memory_relationships`
- `oauth_sessions`
- `user_integrations`

### Live functions

Relevant live routines include:

- `match_memories`
- `match_memories_v2`
- `search_memories_text`
- `store_vault_secret`
- `get_vault_secret`
- `delete_vault_secret`
- `consume_oauth_session`
- `handle_new_memory_ingestion`
- `update_server_timestamp`

### RLS and indexes

Live policies exist for core user-owned tables, including memories, entities, attributes, AI usage logs, integrations, and the remote relationship table.

Live memory indexes include embedding HNSW, full-text, tags GIN, and primary-key indexes. Relationship indexes also remain remotely present.

### Database drift

Migration `20260923100000` is recorded remotely, but the local migration file and Flutter relationship implementation were removed. The remote database and local source are therefore not aligned for persistent Living Memory relationships.

## 6. Testing and Validation

### Flutter analyzer

`flutter analyze` passed with no issues during the audit.

### Full suite

The full current suite produced:

```text
391 passed
4 failed
```

The four failures are unrelated UI expectation failures:

- `home_screen_ui_test.dart`: expected two `Scan Document` widgets, found one.
- `main_navigation_shell_test.dart`: expected one `Add Note` widget, found two.
- `note_compose_flow_test.dart`: expected one `Add Note` widget, found two in two tests.

These failures do not reference the removed relationship layer. They cannot be proven pre-existing from the repository alone, but they are unrelated to Living Memory removal.

### Focused validation

The focused batch covering matcher, isolation, Search, Google, auth, and Home tests produced:

```text
24 passed
1 failed
```

The failure was the Home Screen `Scan Document` count assertion.

The former relationship-specific tests no longer exist. The existing matcher test remains and passes.

No live two-user relationship CRUD tests were run.

## 7. Remaining Work

- Resolve broad unstaged worktree changes safely. Complexity: High.
- Decide whether to retain or formally retire the remote relationship schema. Complexity: High.
- Fix the four unrelated Home/capture UI test failures. Complexity: Medium.
- Verify Supabase Auth, Storage, Realtime, and Edge Functions in staging. Complexity: High.
- Verify Google OAuth/Drive/Docs with real provider configuration. Complexity: Medium.
- Add generated database types. Complexity: Medium.
- Decide whether AI entities should be persisted. Complexity: Medium.
- Add analytics behavior if required. Complexity: Medium.
- Remove or validate unused `purchases_flutter`. Complexity: Low.

## 8. Current Project Completion

| Feature | Status |
|---|---|
| Authentication | Complete at app/code level; live deployment verification pending |
| User data isolation | Implemented and live RLS exists; two-user runtime proof pending |
| Offline-first capture | Complete and tested |
| Text notes | Complete |
| Photo capture | Complete |
| OCR/document capture | Complete at app/AI flow level |
| Voice capture | Complete at app/test level; device verification pending |
| Link capture | Complete at app/test level |
| Isar persistence | Complete |
| Supabase memory sync | Implemented; production runtime verification pending |
| Realtime updates | Implemented |
| Semantic search | Implemented with remote RPC/Edge Function and offline fallback |
| Search relevance filtering | Implemented and tested |
| Google OAuth | Implemented; provider deployment verification pending |
| Google Docs import | Implemented and fixture-tested |
| Google Drive import | Implemented and fixture-tested |
| Home dashboard | Implemented |
| Category browsing | Implemented |
| Saved/pinned memories | Implemented |
| Settings/account UI | Implemented |
| Analytics dashboard | Not implemented or not found |
| AI ingestion | Implemented at app/backend code level |
| AI entity extraction | Partial; extracted/displayed but not persisted as graph data |
| Local related-memory matcher | Implemented and tested |
| Persistent relationship repository | Removed locally |
| Persistent relationship UI | Removed locally |
| Relationship migration locally | Removed locally |
| Relationship table remotely | Exists remotely |
| End-to-end Living Memory graph | Not implemented locally |
| Two-user relationship RLS runtime test | Needs verification |

## 9. Recommended Next Steps

1. Freeze the current worktree and inventory user changes.
2. Decide whether the remote relationship schema should be retained or retired.
3. Do not reintroduce relationship code unless persistent Living Memory is an active requirement.
4. Fix the four unrelated capture/Home test failures.
5. Run the full suite again.
6. Verify Google and Supabase integrations in staging.
7. Add or confirm generated database types.
8. Decide whether AI entities require persistence.
9. Define analytics requirements before adding analytics code.
10. Stage changes selectively after the worktree is understood.
11. Commit only after tests, schema review, and staging review are clean.

## Overall Assessment

The local DocsSaver app is a substantial Flutter/Supabase capture, sync, AI ingestion, search, and integration application.

The current local Living Memory feature is not a persistent relationship feature. It consists primarily of AI-extracted entity display and local related-memory matching. The remote relationship table remains in Supabase but is not used by the current local app.

No unsupported overall completion percentage is claimed.
