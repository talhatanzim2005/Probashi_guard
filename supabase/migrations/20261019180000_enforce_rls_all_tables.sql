-- Migration: 20261019180000_enforce_rls_all_tables.sql
-- Description: Pre-push security gate. Confirms and enforces that every base
-- table in the `public` schema has Row Level Security turned ON.
--
-- WHY THIS IS DYNAMIC: several tables in this project (saved_documents,
-- beneficiaries, and possibly others) were created in the Supabase dashboard,
-- not by a migration in this repo. A hard-coded list would silently miss them,
-- so the sweep below walks pg_class instead.
--
-- READ THIS BEFORE RUNNING
-- ------------------------
-- Enabling RLS on a table that has NO policies denies every row to `anon` and
-- `authenticated` (service_role still bypasses RLS). That is the safe direction
-- to fail, but it CAN take a feature offline. So run STEP 1 on its own first and
-- look at the output. If a table shows up with rls_enabled = false, decide what
-- its policy should be before you let STEP 2 switch it on.
--
-- DO NOT PASTE THIS WHOLE FILE INTO THE SUPABASE SQL EDITOR. The editor runs a
-- script as one batch and displays only the LAST result, so STEP 1's audit
-- would scroll past unread while STEP 2 wrote to the database anyway. Run each
-- step as its own query, in order, reading the output of each before the next.

-- =============================================================================
-- STEP 1 - AUDIT (read-only; run this alone first)
-- =============================================================================

-- 1a. Every base table in `public`, whether RLS is on, and how many policies it
--     has. The rows that matter are:
--       rls_enabled = false            -> unprotected, STEP 2 will fix
--       rls_enabled = true, policies 0 -> protected but totally closed to
--                                         clients; needs a policy, not RLS
SELECT
  c.relname                                               AS table_name,
  c.relrowsecurity                                        AS rls_enabled,
  c.relforcerowsecurity                                   AS rls_forced,
  (SELECT count(*) FROM pg_policy p WHERE p.polrelid = c.oid) AS policy_count,
  CASE
    WHEN NOT c.relrowsecurity THEN 'UNPROTECTED - RLS OFF'
    WHEN (SELECT count(*) FROM pg_policy p WHERE p.polrelid = c.oid) = 0
      THEN 'RLS ON, NO POLICIES - closed to all clients'
    ELSE 'ok'
  END                                                     AS verdict
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p')  -- tables and partitioned tables; skips views
ORDER BY c.relrowsecurity ASC, c.relname;

-- 1b. The hole RLS cannot plug: a privilege held directly by anon/authenticated.
--     TRUNCATE and REFERENCES in particular are NOT filtered by row policies, so
--     a table can have flawless RLS and still be wipeable by an anonymous client.
--
--     has_table_privilege() is used rather than information_schema, because the
--     information_schema view lists only grants made TO the role by name and so
--     misses anything the role inherits through PUBLIC - which would report a
--     reachable table as clean.
SELECT
  c.relname AS table_name,
  (SELECT string_agg(priv, ', ')
     FROM unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE',
                       'TRUNCATE','REFERENCES','TRIGGER']) AS priv
    WHERE has_table_privilege('anon', c.oid, priv))          AS anon_can,
  (SELECT string_agg(priv, ', ')
     FROM unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE',
                       'TRUNCATE','REFERENCES','TRIGGER']) AS priv
    WHERE has_table_privilege('authenticated', c.oid, priv)) AS authenticated_can
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p')
  AND (has_table_privilege('anon', c.oid, 'TRUNCATE')
    OR has_table_privilege('authenticated', c.oid, 'TRUNCATE')
    OR has_table_privilege('anon', c.oid, 'REFERENCES')
    OR has_table_privilege('authenticated', c.oid, 'REFERENCES')
    OR has_table_privilege('anon', c.oid, 'TRIGGER')
    OR has_table_privilege('authenticated', c.oid, 'TRIGGER'))
ORDER BY c.relname;

-- =============================================================================
-- STEP 2 - ENFORCE (writes; run after you have read STEP 1)
--
-- IN THE SQL EDITOR: copy from this header down to the end of 2c, and run that
-- alone as a query named "Enforce RLS - enable and revoke risky grants".
-- =============================================================================

-- 2a. Turn RLS on wherever it is off. Idempotent: a table that already has it
--     on is skipped, and each change is announced so the log shows exactly what
--     moved.
DO $$
DECLARE
  rec record;
  changed int := 0;
BEGIN
  FOR rec IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p')
      AND NOT c.relrowsecurity
    ORDER BY c.relname
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', rec.relname);
    RAISE NOTICE 'RLS enabled on public.%', rec.relname;
    changed := changed + 1;
  END LOOP;

  IF changed = 0 THEN
    RAISE NOTICE 'No change: every table in public already had RLS enabled.';
  ELSE
    RAISE NOTICE 'RLS enabled on % table(s).', changed;
  END IF;
END
$$;

-- 2b. Strip the privileges row policies cannot restrain. SELECT/INSERT/UPDATE
--     are deliberately left alone here - those are governed by the policies the
--     earlier migrations define, and revoking them wholesale would log everyone
--     out of their own data.
DO $$
DECLARE
  rec record;
BEGIN
  FOR rec IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p')
      AND (has_table_privilege('anon', c.oid, 'TRUNCATE')
        OR has_table_privilege('authenticated', c.oid, 'TRUNCATE')
        OR has_table_privilege('anon', c.oid, 'REFERENCES')
        OR has_table_privilege('authenticated', c.oid, 'REFERENCES')
        OR has_table_privilege('anon', c.oid, 'TRIGGER')
        OR has_table_privilege('authenticated', c.oid, 'TRIGGER'))
    ORDER BY c.relname
  LOOP
    -- PUBLIC is revoked as well as the two named roles. A privilege inherited
    -- through PUBLIC is NOT removed by revoking it from anon, so naming only
    -- the roles would report success and leave the table just as exposed.
    -- service_role keeps its own explicit grants and is unaffected.
    EXECUTE format(
      'REVOKE TRUNCATE, REFERENCES, TRIGGER ON public.%I FROM PUBLIC, anon, authenticated',
      rec.relname
    );
    RAISE NOTICE 'Revoked TRUNCATE/REFERENCES/TRIGGER on public.%', rec.relname;
  END LOOP;
END
$$;

-- 2c. A table added later starts with no client privileges, so it is closed by
--     default instead of open.
--
--     SCOPE, which is narrower than it looks: a default-privileges rule applies
--     only to tables created by the role that RUNS this statement. In the SQL
--     editor that role is `postgres`, which is also the role the dashboard
--     creates tables as, so the normal case is covered. A table created by any
--     other role is NOT covered and still has to be checked by hand - which is
--     what STEP 1 is for.
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon, authenticated;

-- =============================================================================
-- STEP 3 - VERIFY (re-run 1a; every row should read 'ok')
-- =============================================================================
SELECT
  c.relname                                               AS table_name,
  c.relrowsecurity                                        AS rls_enabled,
  (SELECT count(*) FROM pg_policy p WHERE p.polrelid = c.oid) AS policy_count,
  CASE
    WHEN NOT c.relrowsecurity THEN 'STILL UNPROTECTED'
    WHEN (SELECT count(*) FROM pg_policy p WHERE p.polrelid = c.oid) = 0
      THEN 'RLS ON, NO POLICIES - closed to all clients'
    ELSE 'ok'
  END                                                     AS verdict
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p')
ORDER BY c.relrowsecurity ASC, c.relname;
