-- Migration: 20261019005049_fix_rls_saved_documents_notices.sql
-- Applied to project xfwxiawapksepskcevwe on 2026-10-19 (recorded version 20261019005049).
-- Description: Brings the RLS on `saved_documents` and `notices` in line with
-- how the app actually talks to them, and closes the grant/policy mismatches
-- the live database had drifted into.
--
-- What was wrong (live database, 2026-10-19):
--
--   notices
--     * anon AND authenticated still held table-level INSERT, UPDATE, DELETE,
--       TRUNCATE grants, while the table has no INSERT/UPDATE/DELETE policy at
--       all. Every client write therefore failed at the RLS check with 42501
--       ("new row violates row-level security policy") instead of being
--       refused at the grant, and the day anyone adds a FOR ALL policy here the
--       feed becomes client-writable. Writes belong to the seeder
--       (backend_service/scripts/seed_notices.ts, service-role key) only.
--     * The live SELECT policy covers {anon, authenticated}, but the policy in
--       20261018120000_create_notices.sql is `to authenticated` only. Applying
--       that file as written would stop the feed loading before the app's
--       session is restored. This migration settles on anon + authenticated,
--       which is what the live feed already relies on.
--
--   saved_documents
--     * SELECT is scoped correctly (authenticated, own rows) and stays that way.
--     * INSERT/UPDATE/DELETE are revoked from anon and authenticated, so the
--       vault is writable only with the service-role key, via
--       backend_service /api/documents/*. That is the intended design (see the
--       table comment), so this migration keeps it and states it explicitly
--       rather than leaving it to a REVOKE buried in an older file. If the app
--       is ever meant to write its own rows, uncomment section 3.
--     * anon keeps its SELECT grant on purpose: RLS already returns 0 rows for
--       a session-less caller, and scripts/pentest_supabase_rls.ts asserts on
--       that empty result. Revoking the grant would turn it into an error.
--
-- Safe to run more than once. Changes no rows, only policies and grants.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. NOTICES — public read for every app user, no client writes.
-- ---------------------------------------------------------------------------
ALTER TABLE public.notices ENABLE ROW LEVEL SECURITY;

-- Both the old name and the new one, so re-running is clean.
DROP POLICY IF EXISTS "Notices are readable by signed-in users" ON public.notices;
DROP POLICY IF EXISTS "Notices are readable by every app user" ON public.notices;

-- The feed is public news: no per-user scoping. `anon` covers the launch window
-- before the session is restored; an anonymous sign-in arrives as
-- `authenticated`, which covers every signed-in user.
CREATE POLICY "Notices are readable by every app user"
  ON public.notices
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- Refuse client writes at the grant, so the intent is visible in \dp and a
-- future policy cannot accidentally open the feed.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.notices FROM anon, authenticated;
GRANT SELECT ON public.notices TO anon, authenticated;

-- The seeder's key. service_role bypasses RLS; the grants are stated anyway so
-- the table does not depend on Supabase's defaults staying put.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notices TO service_role;

-- ---------------------------------------------------------------------------
-- 2. SAVED_DOCUMENTS — each user reads their own rows; writes are
--    service-role only (backend_service holds the key).
-- ---------------------------------------------------------------------------
ALTER TABLE public.saved_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read their own saved documents" ON public.saved_documents;

-- `(SELECT auth.uid())` rather than a bare `auth.uid()`: Postgres then
-- evaluates it once per query instead of once per row.
CREATE POLICY "Users read their own saved documents"
  ON public.saved_documents
  FOR SELECT
  TO authenticated
  USING ((SELECT auth.uid()) = user_id);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.saved_documents FROM anon, authenticated;

-- anon keeps SELECT so a session-less read returns an empty list, not an error.
GRANT SELECT ON public.saved_documents TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_documents TO service_role;

COMMENT ON TABLE public.saved_documents IS
  'AI audits of scanned labor documents. Readable by the owning user; written only by backend_service (service-role key).';

-- ---------------------------------------------------------------------------
-- 3. OPTIONAL — client-side writes to the vault.
--    Uncomment ONLY if the app should insert/delete its own documents without
--    going through backend_service. It widens the attack surface: a stolen
--    access token could then write audit rows for its own user.
-- ---------------------------------------------------------------------------
-- GRANT INSERT, UPDATE, DELETE ON public.saved_documents TO authenticated;
--
-- DROP POLICY IF EXISTS "Users insert their own saved documents" ON public.saved_documents;
-- CREATE POLICY "Users insert their own saved documents"
--   ON public.saved_documents
--   FOR INSERT
--   TO authenticated
--   WITH CHECK ((SELECT auth.uid()) = user_id);
--
-- DROP POLICY IF EXISTS "Users update their own saved documents" ON public.saved_documents;
-- CREATE POLICY "Users update their own saved documents"
--   ON public.saved_documents
--   FOR UPDATE
--   TO authenticated
--   USING ((SELECT auth.uid()) = user_id)
--   WITH CHECK ((SELECT auth.uid()) = user_id);
--
-- DROP POLICY IF EXISTS "Users delete their own saved documents" ON public.saved_documents;
-- CREATE POLICY "Users delete their own saved documents"
--   ON public.saved_documents
--   FOR DELETE
--   TO authenticated
--   USING ((SELECT auth.uid()) = user_id);

COMMIT;

-- ---------------------------------------------------------------------------
-- Verify (read-only):
--
--   SELECT tablename, policyname, roles, cmd, qual
--   FROM pg_policies
--   WHERE schemaname = 'public' AND tablename IN ('saved_documents', 'notices')
--   ORDER BY tablename, cmd;
--
--   SELECT table_name, grantee, privilege_type
--   FROM information_schema.role_table_grants
--   WHERE table_schema = 'public'
--     AND table_name IN ('saved_documents', 'notices')
--     AND grantee IN ('anon', 'authenticated')
--   ORDER BY table_name, grantee, privilege_type;
-- ---------------------------------------------------------------------------
