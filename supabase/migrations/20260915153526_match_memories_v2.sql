-- Enable the pgvector extension to work with embedding vectors
create extension if not exists vector;

-- 1. Create HNSW index on public.memories.embedding for fast cosine vector similarity search
-- Uses vector_cosine_ops with cosine distance (<=>)
create index if not exists memories_embedding_hnsw_idx
on public.memories
using hnsw (embedding vector_cosine_ops);

-- 2. Create versioned match_memories_v2 RPC function
-- Returns full memory card fields including category, media_url, and client_created_at
-- Strictly enforces user data isolation via auth.uid() and security invoker
create or replace function public.match_memories_v2(
  query_embedding vector(768),
  match_threshold float default 0.3,
  match_count int default 10
)
returns table (
  id uuid,
  title text,
  content text,
  category text,
  tags text[],
  media_url text,
  client_created_at timestamptz,
  similarity float
)
language plpgsql
security invoker
set search_path = public, extensions
as $$
begin
  return query
  select
    m.id,
    m.title,
    m.content,
    m.category,
    m.tags,
    m.media_url,
    coalesce(m.client_created_at, m.created_at) as client_created_at,
    (1 - (m.embedding <=> query_embedding))::float as similarity
  from public.memories m
  where m.user_id = auth.uid()
    and m.embedding is not null
    and (1 - (m.embedding <=> query_embedding)) >= match_threshold
  order by m.embedding <=> query_embedding asc
  limit match_count;
end;
$$;
