-- Notice feed: Open Graph metadata scraped from public news articles and cached
-- here, so the app never calls the news sites itself and the feed stays free.
-- Rows are written by backend_service/scripts/seed_notices.ts with the service
-- role key; clients only ever read.

create table if not exists public.notices (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  image_url text,
  -- The article this row was scraped from. Unique so re-running the seeder
  -- refreshes a notice instead of adding a duplicate card to the feed.
  source_url text not null unique,
  created_at timestamptz not null default now()
);

-- The feed is read newest-first.
create index if not exists notices_created_at_idx
  on public.notices (created_at desc);

alter table public.notices enable row level security;

-- The app signs in anonymously at launch, and an anonymous Supabase session
-- still carries the `authenticated` role, so this covers every app user.
-- Notices are public news: no per-user scoping, read-only for clients.
drop policy if exists "Notices are readable by signed-in users" on public.notices;
create policy "Notices are readable by signed-in users"
  on public.notices
  for select
  to authenticated
  using (true);
