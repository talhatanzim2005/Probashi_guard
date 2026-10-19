-- Migration: 20261019150000_tighten_client_grants.sql
-- Description: Narrows the table grants left over on profiles and
-- payment_methods after 20261019140000_p2p_core.sql.
--
-- Why this is a separate migration: a column-level `GRANT UPDATE (cols)` is
-- ADDED to whatever table-level UPDATE the role already holds — it does not
-- replace it. p2p_core revoked INSERT/DELETE/TRUNCATE on `profiles` but not
-- UPDATE, so `authenticated` kept UPDATE on every column, `phone` and
-- `user_id` included. A client could then set its own phone number with a
-- plain UPDATE and skip set_my_phone(), which is what enforces the format and
-- the one-number-one-account rule.
--
-- `anon` also still held INSERT/UPDATE/DELETE on payment_methods and UPDATE on
-- profiles. RLS already denied it (every policy is TO authenticated, and a
-- table with RLS on and no matching policy denies), but the grant should not
-- be there either: if anyone later adds a permissive policy, the grant is what
-- decides whether it becomes reachable.
--
-- Safe to run more than once.

-- Start from nothing so the column grant below is the whole of it.
REVOKE ALL ON public.profiles FROM anon, authenticated;
GRANT SELECT ON public.profiles TO authenticated;
GRANT UPDATE (full_name, avatar_url) ON public.profiles TO authenticated;

REVOKE ALL ON public.payment_methods FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payment_methods TO authenticated;

REVOKE ALL ON public.wallets FROM anon, authenticated;
GRANT SELECT ON public.wallets TO authenticated;

REVOKE ALL ON public.transactions FROM anon, authenticated;
GRANT SELECT ON public.transactions TO authenticated;
