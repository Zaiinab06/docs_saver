-- Migration: Full-Text Search & GIN Indexes for Second Brain
-- Adds full-text search capability and GIN indexing over title, category, tags, and content.
-- Strictly enforces user data isolation via auth.uid() and security invoker.

-- 1. Create GIN indexes for high-speed full-text search across textual memory fields
create index if not exists memories_fts_eng_idx
on public.memories
using gin (to_tsvector('english'::regconfig, coalesce(title, '') || ' ' || coalesce(category, '') || ' ' || coalesce(content, '')));

create index if not exists memories_fts_simple_idx
on public.memories
using gin (to_tsvector('simple'::regconfig, coalesce(title, '') || ' ' || coalesce(category, '') || ' ' || coalesce(content, '')));

create index if not exists memories_tags_gin_idx
on public.memories
using gin (tags);

-- 2. Create versioned search_memories_text RPC function
-- Uses weighted ts_rank_cd combining English stemmed and simple literal dictionaries.
-- Handles natural language multi-word queries via disjunctive OR tsquery and word matching.
create or replace function public.search_memories_text(
  search_query text,
  match_count int default 15
)
returns table (
  id uuid,
  title text,
  content text,
  category text,
  tags text[],
  media_url text,
  client_created_at timestamptz,
  text_rank float
)
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  clean_q text := trim(search_query);
  query_ts_eng tsquery;
  query_ts_simple tsquery;
begin
  if clean_q = '' then
    return;
  end if;

  -- Build disjunctive OR tsquery for English stemmed dictionary
  begin
    query_ts_eng := to_tsquery('english', replace(plainto_tsquery('english', clean_q)::text, '&', '|'));
  exception when others then
    query_ts_eng := null;
  end;

  -- Build disjunctive OR tsquery for Simple literal dictionary
  begin
    query_ts_simple := to_tsquery('simple', replace(plainto_tsquery('simple', clean_q)::text, '&', '|'));
  exception when others then
    query_ts_simple := null;
  end;

  return query
  select
    m.id,
    m.title,
    m.content,
    m.category,
    m.tags,
    m.media_url,
    m.client_created_at,
    greatest(
      case when query_ts_eng is not null then
        ts_rank_cd(
          setweight(to_tsvector('english', coalesce(m.title, '')), 'A') ||
          setweight(to_tsvector('english', coalesce(m.category, '')), 'A') ||
          setweight(to_tsvector('english', coalesce(m.content, '')), 'C'),
          query_ts_eng
        )
      else 0.0 end,
      case when query_ts_simple is not null then
        ts_rank_cd(
          setweight(to_tsvector('simple', coalesce(m.title, '')), 'A') ||
          setweight(to_tsvector('simple', coalesce(m.category, '')), 'A') ||
          setweight(to_tsvector('simple', coalesce(m.content, '')), 'C'),
          query_ts_simple
        )
      else 0.0 end,
      0.1
    )::float as text_rank
  from public.memories m
  where m.user_id = auth.uid()
    and (
      (query_ts_eng is not null and (
        to_tsvector('english', coalesce(m.title, '') || ' ' || coalesce(m.category, '') || ' ' || coalesce(m.content, ''))
      ) @@ query_ts_eng)
      or (query_ts_simple is not null and (
        to_tsvector('simple', coalesce(m.title, '') || ' ' || coalesce(m.category, '') || ' ' || coalesce(m.content, ''))
      ) @@ query_ts_simple)
      or (m.title ilike '%' || clean_q || '%')
      or (m.category ilike '%' || clean_q || '%')
      or exists (
        select 1 from unnest(string_to_array(lower(clean_q), ' ')) word
        where length(word) >= 3 and (
          m.title ilike '%' || word || '%' or
          m.category ilike '%' || word || '%' or
          exists (select 1 from unnest(m.tags) t where t ilike '%' || word || '%')
        )
      )
    )
  order by text_rank desc, m.client_created_at desc
  limit match_count;
end;
$$;
