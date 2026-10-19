-- Migration: 20261019005601_revoke_client_references_trigger.sql
-- Description: Takes the last two privileges no client role should hold on the
-- news feed or the document vault.
--
-- Applied to project xfwxiawapksepskcevwe on 2026-10-19 (recorded version
-- 20261019005601). The remainder of the RLS fix applied as
-- 20261019005049_fix_rls_saved_documents_notices.sql; picked up from a parallel
-- draft of the same fix (20261019140000_fix_notices_and_vault_grants.sql, since
-- deleted as a duplicate).
--
-- REFERENCES lets a role point a foreign key at these tables, which leaks the
-- existence of rows through constraint violations. TRIGGER lets a role attach a
-- trigger function that then runs on the table owner's writes. Neither is
-- subject to row level security, so no policy can stand in for revoking them.
--
-- `anon` deliberately keeps SELECT on saved_documents: row level security
-- already returns zero rows to a caller with no session, and
-- backend_service/scripts/pentest_supabase_rls.ts asserts on that empty
-- result. Revoking the grant would make it an error instead, and that test
-- would report a false failure. This is the one point where the deleted
-- duplicate disagreed, and it is the reason this file, not that one, is the
-- version kept.
--
-- Safe to run more than once. Changes no rows, only grants.

REVOKE REFERENCES, TRIGGER ON public.notices FROM anon, authenticated;
REVOKE REFERENCES, TRIGGER ON public.saved_documents FROM anon, authenticated;

-- Restated so the surviving privilege is explicit in one place.
GRANT SELECT ON public.notices TO anon, authenticated;
GRANT SELECT ON public.saved_documents TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- Verify (read-only):
--
--   SELECT table_name, grantee, privilege_type
--   FROM information_schema.role_table_grants
--   WHERE table_schema = 'public'
--     AND table_name IN ('saved_documents', 'notices')
--     AND grantee IN ('anon', 'authenticated')
--   ORDER BY table_name, grantee, privilege_type;
--
-- Expected: SELECT, and nothing else, for both roles on both tables.
-- ---------------------------------------------------------------------------
