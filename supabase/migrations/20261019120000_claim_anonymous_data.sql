-- Migration: 20261019120000_claim_anonymous_data.sql
-- Description: Lets a device that used the app anonymously carry its data into
-- the account it later logs in to or registers.
--
-- Before login existed, every install signed in anonymously (26 such users on
-- this project), and its scanned documents and saved recipients belong to that
-- anonymous user id. Logging in switches to a different user id, and row-level
-- security then hides the old rows. The client cannot move them itself (RLS
-- again), so:
--
--   1. While still anonymous, the app calls issue_anonymous_claim() and keeps
--      the one-time token it returns.
--   2. Once signed in to the real account, it calls
--      claim_anonymous_data(token), which moves the rows across.
--
-- Only the anonymous session can mint a token for itself, and only a
-- non-anonymous session can spend one, once, within a day — so holding the
-- token is proof the caller was that anonymous device.
--
-- SCOPE: saved_documents and beneficiaries ONLY.
-- Wallet balances and transaction history are deliberately NOT carried over.
-- The P2P ledger (20261019140000_p2p_core.sql) starts every account at a zero
-- balance with no history, so there is nothing of value to move and the old
-- rows do not fit the new shape.
--
-- Safe to run more than once.

CREATE TABLE IF NOT EXISTS public.anonymous_claims (
  token        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  anon_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- Reachable only through the two functions below.
ALTER TABLE public.anonymous_claims ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.anonymous_claims FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.issue_anonymous_claim()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller uuid := auth.uid();
  claim  uuid;
BEGIN
  IF caller IS NULL OR NOT EXISTS (
    SELECT 1 FROM auth.users WHERE id = caller AND is_anonymous
  ) THEN
    RAISE EXCEPTION 'Only an anonymous session can issue a claim'
      USING ERRCODE = '42501';
  END IF;

  -- Only the newest token per device is live.
  DELETE FROM public.anonymous_claims WHERE anon_user_id = caller;
  INSERT INTO public.anonymous_claims (anon_user_id)
  VALUES (caller)
  RETURNING token INTO claim;
  RETURN claim;
END;
$$;

-- Returns how many rows moved. 0 means there was nothing to do: an unknown,
-- spent or expired token, or an anonymous user with no documents or contacts.
CREATE OR REPLACE FUNCTION public.claim_anonymous_data(claim_token uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller  uuid := auth.uid();
  anon_id uuid;
  moved   integer := 0;
  n       integer;
BEGIN
  IF caller IS NULL OR EXISTS (
    SELECT 1 FROM auth.users WHERE id = caller AND is_anonymous
  ) THEN
    RAISE EXCEPTION 'Sign in to an account before claiming data'
      USING ERRCODE = '42501';
  END IF;

  -- Spent on first use, whatever happens next.
  DELETE FROM public.anonymous_claims
  WHERE token = claim_token
    AND created_at > now() - interval '1 day'
  RETURNING anon_user_id INTO anon_id;

  IF anon_id IS NULL OR anon_id = caller THEN
    RETURN 0;
  END IF;
  -- The anonymous user may since have been upgraded into a real account of
  -- its own; that account keeps its data.
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = anon_id AND is_anonymous) THEN
    RETURN 0;
  END IF;

  UPDATE public.saved_documents SET user_id = caller WHERE user_id = anon_id;
  GET DIAGNOSTICS n = ROW_COUNT; moved := moved + n;

  -- A contact the person already has wins, so re-claiming cannot duplicate one.
  DELETE FROM public.beneficiaries a
  WHERE a.user_id = anon_id
    AND EXISTS (
      SELECT 1 FROM public.beneficiaries b
      WHERE b.user_id = caller
        AND b.phone_number IS NOT DISTINCT FROM a.phone_number
    );
  UPDATE public.beneficiaries SET user_id = caller WHERE user_id = anon_id;
  GET DIAGNOSTICS n = ROW_COUNT; moved := moved + n;

  RETURN moved;
END;
$$;

REVOKE ALL ON FUNCTION public.issue_anonymous_claim() FROM public, anon;
REVOKE ALL ON FUNCTION public.claim_anonymous_data(uuid) FROM public, anon;
-- Anonymous sign-ins use the authenticated role too; the functions themselves
-- check which kind of user is calling.
GRANT EXECUTE ON FUNCTION public.issue_anonymous_claim() TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_anonymous_data(uuid) TO authenticated;
