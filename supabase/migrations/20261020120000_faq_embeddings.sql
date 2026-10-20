-- FAQ knowledge base for Prohori, the in-app AI assistant (RAG).
--
-- Name in the Supabase SQL editor: "Prohori FAQ embeddings (20261020120000)"
--
-- One row per question in instruction/probashi_guard_ai_flow_{english,bangla}.txt:
-- the question with its answer, plus the 384-number vector that lets a worker's
-- own wording find it. backend_service fills the table (npm run seed:faqs) and
-- searches it for POST /api/chat. Nothing in the app can touch it:
--
--   faq_embeddings   RLS on, no policies, no grants to anon/authenticated
--   match_faqs()     executable by service_role only
--
-- Run it in the Supabase dashboard SQL editor. NEVER `supabase db push` on this
-- project. It is short enough to paste in one go, and safe to run again.
--
-- THEN: cd backend_service && npm run seed:faqs   (fills the table; needs the
-- SUPABASE_SERVICE_ROLE_KEY in backend_service/.env)

-- The extension lives in the `extensions` schema, as Supabase does it; the
-- search path lets this script (and match_faqs, below) find its type and <=>.
create extension if not exists vector with schema extensions;
set search_path to public, extensions;

create table if not exists public.faq_embeddings (
  id              bigint generated always as identity primary key,
  -- Stable id from the seeder, e.g. en-s3-q12, so re-seeding updates in place.
  chunk_key       text not null unique,
  language        text not null check (language in ('bn', 'en')),
  section         text,
  -- "Q: ...\nA: ..." as shown to the language model.
  content         text not null,
  embedding       vector(384) not null,
  -- Which model made `embedding`. Vectors from different models cannot be
  -- compared, so the API refuses to answer from a table built by another one.
  embedding_model text not null,
  created_at      timestamptz not null default now()
);

alter table public.faq_embeddings enable row level security;
revoke all on table public.faq_embeddings from public, anon, authenticated;
grant select, insert, update, delete on table public.faq_embeddings to service_role;

comment on table public.faq_embeddings is
  'Prohori FAQ chunks and their embeddings. Read and written by backend_service with the service role only.';

-- Closest FAQ entries to a question vector. Cosine similarity, 1 = identical.
-- Below match_threshold nothing is returned. The table holds a few dozen rows,
-- so an exact scan is instant and an index would only make it approximate.
create or replace function public.match_faqs(
  query_embedding  vector(384),
  match_threshold  double precision default 0.3,
  match_count      integer default 3,
  filter_language  text default null
)
returns table (
  id              bigint,
  chunk_key       text,
  language        text,
  section         text,
  content         text,
  similarity      double precision,
  embedding_model text
)
language sql
stable
set search_path = public, extensions
as $fn$
  select f.id,
         f.chunk_key,
         f.language,
         f.section,
         f.content,
         1 - (f.embedding <=> query_embedding) as similarity,
         f.embedding_model
  from public.faq_embeddings f
  where (filter_language is null or f.language = filter_language)
    and 1 - (f.embedding <=> query_embedding) > match_threshold
  order by f.embedding <=> query_embedding
  limit least(greatest(match_count, 1), 20);
$fn$;

revoke all on function public.match_faqs(vector, double precision, integer, text)
  from public, anon, authenticated;
grant execute on function public.match_faqs(vector, double precision, integer, text)
  to service_role;

-- ===========================================================================
-- VERIFY (read-only; run after the seeder)
-- ===========================================================================
-- 1. 39 questions per language, all from the same model:
--    select language, count(*) as questions, min(embedding_model) as model
--    from public.faq_embeddings group by 1 order by 1;          -- bn 39, en 39
-- 2. The app's roles can reach neither the table nor the function:
--    select has_table_privilege('authenticated', 'public.faq_embeddings', 'select') as table_ok,
--           (select has_function_privilege('authenticated', p.oid, 'execute')
--            from pg_proc p where p.proname = 'match_faqs') as fn_ok;   -- false, false
-- 3. A self-match returns its own row first, with similarity 1:
--    select chunk_key, similarity from public.match_faqs(
--      (select embedding from public.faq_embeddings order by id limit 1), 0.0, 3);
