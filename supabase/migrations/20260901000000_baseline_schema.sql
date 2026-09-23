-- ==============================================================================
-- Baseline Schema Migration: Second Brain (DocsSaver)
-- File: supabase/migrations/20260901000000_baseline_schema.sql
-- Description:
--   Complete baseline schema for public.memories, vector similarity search,
--   full-text search, Row-Level Security (RLS), and private Supabase storage
--   isolation for the 'memories' bucket.
-- ==============================================================================

-- 1. Required Extensions
create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;
create extension if not exists vector;

-- 2. Core Table: public.memories
create table if not exists public.memories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default '',
  content text not null default '',
  category text not null default 'General',
  tags text[] not null default '{}',
  file_url text,
  media_url text,
  file_type text,
  source_type text not null default 'note',
  ai_status text not null default 'pending', -- 'pending', 'processed', 'failed'
  is_conflict_copy boolean not null default false,
  embedding vector(768),
  client_created_at timestamptz not null default now(),
  client_updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  server_updated_at timestamptz not null default now()
);

-- 3. Trigger: Automatically update updated_at and server_updated_at
create or replace function public.handle_memories_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  new.server_updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists set_memories_updated_at on public.memories;
create trigger set_memories_updated_at
before update on public.memories
for each row
execute function public.handle_memories_updated_at();

-- 4. Trigger: Bidirectional sync between file_url and media_url
create or replace function public.sync_memory_file_urls()
returns trigger as $$
begin
  if new.file_url is null and new.media_url is not null then
    new.file_url := new.media_url;
  elsif new.media_url is null and new.file_url is not null then
    new.media_url := new.file_url;
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists sync_memory_file_urls_trigger on public.memories;
create trigger sync_memory_file_urls_trigger
before insert or update on public.memories
for each row
execute function public.sync_memory_file_urls();

-- 5. Performance Indexes
create index if not exists memories_user_id_idx
  on public.memories(user_id);

create index if not exists memories_user_client_created_at_idx
  on public.memories(user_id, client_created_at desc);

create index if not exists memories_category_idx
  on public.memories(user_id, category);

create index if not exists memories_ai_status_idx
  on public.memories(user_id, ai_status);

-- Vector Cosine Distance Index (HNSW for Gemini 768-d embeddings)
create index if not exists memories_embedding_hnsw_idx
  on public.memories
  using hnsw (embedding vector_cosine_ops);

-- GIN Index for Tag Filtering
create index if not exists memories_tags_gin_idx
  on public.memories
  using gin (tags);

-- GIN Indexes for Full-Text Search
create index if not exists memories_fts_eng_idx
  on public.memories
  using gin (to_tsvector('english'::regconfig, coalesce(title, '') || ' ' || coalesce(category, '') || ' ' || coalesce(content, '')));

create index if not exists memories_fts_simple_idx
  on public.memories
  using gin (to_tsvector('simple'::regconfig, coalesce(title, '') || ' ' || coalesce(category, '') || ' ' || coalesce(content, '')));

-- 6. Row-Level Security (RLS) on public.memories
alter table public.memories enable row level security;

-- Drop existing policies if already defined to guarantee idempotent re-runs
drop policy if exists "Users can read own memories" on public.memories;
create policy "Users can read own memories"
  on public.memories for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own memories" on public.memories;
create policy "Users can insert own memories"
  on public.memories for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own memories" on public.memories;
create policy "Users can update own memories"
  on public.memories for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own memories" on public.memories;
create policy "Users can delete own memories"
  on public.memories for delete
  to authenticated
  using (auth.uid() = user_id);

-- 7. Supabase Realtime Publication
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'memories'
  ) then
    alter publication supabase_realtime add table public.memories;
  end if;
end $$;

-- 8. Supabase Storage Security: 'memories' Bucket
-- Ensure private storage bucket exists
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'memories',
  'memories',
  false,
  52428800, -- 50 MB file size limit per upload
  null      -- Allow images, audio (.m4a), and documents (.pdf)
)
on conflict (id) do update set
  public = false;

-- Storage Objects RLS Policies: Authenticated users can only access their own user directory
drop policy if exists "Authenticated users can read own memory files" on storage.objects;
create policy "Authenticated users can read own memory files"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'memories'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Authenticated users can upload own memory files" on storage.objects;
create policy "Authenticated users can upload own memory files"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'memories'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Authenticated users can update own memory files" on storage.objects;
create policy "Authenticated users can update own memory files"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'memories'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'memories'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Authenticated users can delete own memory files" on storage.objects;
create policy "Authenticated users can delete own memory files"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'memories'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
