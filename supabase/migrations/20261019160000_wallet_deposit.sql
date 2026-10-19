-- Migration: 20261019160000_wallet_deposit.sql
-- Description: The one sanctioned way a balance can go UP — a deposit booked
-- by the Stripe webhook after Stripe reports a Checkout session paid.
--
-- 20261019140000_p2p_core.sql left this hole open on purpose: it says
-- "funding stays behind the Stripe webhook", but shipped no function for the
-- webhook to call, so backend_service was still writing the pre-P2P columns
-- (amount_bdt, balance_bdt) on tables that have since been renamed to
-- *_legacy_20261019. Funding has therefore been dead since that migration.
--
-- Mirrors p2p_transfer: the wallet row is locked FOR UPDATE before the balance
-- is read, the amount is rounded to paisa and must be positive, and the ledger
-- row snapshots balance_before / balance_after. One credit row, purpose
-- 'deposit', with no counterparty — the money comes from outside the system.
--
-- WHO MAY CALL THIS
-- Only `service_role`. A new function starts with EXECUTE granted to PUBLIC,
-- so the REVOKE at the foot of this file is not decoration: without it any
-- signed-in person could POST /rest/v1/rpc/deposit_to_wallet and credit
-- themselves any amount. This function takes the user id as an argument and
-- deliberately does NOT read auth.uid(), because it runs from the webhook
-- under the service-role key where there is no JWT — which is exactly why it
-- must never be reachable by `authenticated` or `anon`.
--
-- p_idempotency_key is required, not optional: it carries the Stripe session
-- id, so a webhook Stripe retries (it retries for up to three days) credits
-- the wallet once. transactions_idempotency_uk enforces it at the index level
-- as well.
--
-- Safe to run more than once.

CREATE OR REPLACE FUNCTION public.deposit_to_wallet(
  p_user_id         uuid,
  p_amount          numeric,
  p_idempotency_key text,
  p_description     text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_amount    numeric(14, 2);
  v_before    numeric(14, 2);
  v_reference uuid := gen_random_uuid();
  v_existing  public.transactions%ROWTYPE;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'A deposit needs the account it belongs to'
      USING ERRCODE = '22023';
  END IF;

  IF p_idempotency_key IS NULL OR length(btrim(p_idempotency_key)) = 0 THEN
    RAISE EXCEPTION 'A deposit needs an idempotency key'
      USING ERRCODE = '22023';
  END IF;

  -- Rounded first, so a fractional paisa cannot drift the balance.
  v_amount := round(p_amount, 2);
  IF v_amount IS NULL OR v_amount <= 0 THEN
    RAISE EXCEPTION 'A deposit must be greater than zero'
      USING ERRCODE = '22023';
  END IF;

  -- A webhook Stripe sent twice books the money once and reports the first
  -- result, rather than failing (which would make Stripe retry again).
  SELECT * INTO v_existing FROM public.transactions
  WHERE user_id = p_user_id AND idempotency_key = p_idempotency_key;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'reference', v_existing.reference,
      'amount',    v_existing.amount,
      'balance',   v_existing.balance_after,
      'repeated',  true
    );
  END IF;

  -- The account may predate the P2P migration, or be brand new.
  INSERT INTO public.wallets (user_id, balance) VALUES (p_user_id, 0)
  ON CONFLICT (user_id) DO NOTHING;

  PERFORM 1 FROM public.wallets WHERE user_id = p_user_id FOR UPDATE;
  SELECT balance INTO v_before FROM public.wallets WHERE user_id = p_user_id;

  UPDATE public.wallets
  SET balance = balance + v_amount, updated_at = now()
  WHERE user_id = p_user_id;

  INSERT INTO public.transactions (
    reference, user_id, direction, purpose, amount,
    balance_before, balance_after, description, idempotency_key
  ) VALUES (
    v_reference, p_user_id, 'credit', 'deposit', v_amount,
    v_before, v_before + v_amount, coalesce(p_description, ''), p_idempotency_key
  );

  RETURN jsonb_build_object(
    'reference', v_reference,
    'amount',    v_amount,
    'balance',   v_before + v_amount,
    'repeated',  false
  );
END;
$$;

-- The whole security of funding is this grant. Do not widen it.
REVOKE ALL ON FUNCTION public.deposit_to_wallet(uuid, numeric, text, text)
  FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.deposit_to_wallet(uuid, numeric, text, text)
  TO service_role;
