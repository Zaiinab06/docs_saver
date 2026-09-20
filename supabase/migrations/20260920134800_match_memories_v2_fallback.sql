-- Migration: Update match_memories_v2 RPC with client_created_at fallback
-- Ensures client_created_at falls back to created_at if null
-- Preserves function signature, return columns, auth.uid() user isolation, and search path

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
