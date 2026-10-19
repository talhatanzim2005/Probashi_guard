-- Migration: 20261019170000_verified_phone_gate.sql
-- Description: Makes a phone number something that must be PROVEN, not merely
-- claimed, and refuses to move money for an account that has not proven one.
--
-- THE HOLE THIS CLOSES
-- 20261019140000_p2p_core.sql granted EXECUTE on set_my_phone() to
-- `authenticated`. Any signed-in client could therefore POST
-- /rest/v1/rpc/set_my_phone and bind any number with no verification at all.
-- Because p2p_transfer resolves a recipient by profiles.phone, that was not
-- just an identity problem: claiming somebody else's number redirected their
-- incoming money to you.
--
-- WHY VERIFICATION IS NOT DONE IN HERE
-- Firebase Phone Auth issues an RS256 ID token signed by Google, whose public
-- keys rotate at a Google JWKS endpoint. Checking one means an outbound HTTPS
-- fetch plus RS256 verification: `pgjwt` only does HS256 with a shared secret,
-- `http` would block the transaction on a network call, and `pg_net` is async
-- so it cannot return a verdict inline. None of them are installed here either.
--
-- So the token is verified in backend_service (POST /api/auth/bind-phone,
-- using `jose` against Google's rotating JWKS), and only then does it call
-- bind_verified_phone() with the service-role key — the same shape as
-- deposit_to_wallet. This function therefore takes the user id and
-- phone as ARGUMENTS and is reachable by service_role alone. If
-- `authenticated` is ever granted EXECUTE on it, the whole Firebase flow
-- becomes decorative, because the client can simply call this instead.
--
-- WHERE THE GATE IS *NOT* APPLIED, DELIBERATELY
-- deposit_to_wallet() stays ungated. It runs from the Stripe webhook AFTER the
-- person has already been charged; refusing there would take their money and
-- credit nothing. An unverified account is stopped earlier, when the Checkout
-- session is created, where refusing costs nobody anything.
--
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- 1. WHEN THE NUMBER WAS PROVEN
-- Not in the `authenticated` column grant (which is full_name, avatar_url
-- only), so a client cannot set this on itself with a plain UPDATE.
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS phone_verified_at timestamptz;

COMMENT ON COLUMN public.profiles.phone_verified_at IS
  'Set only by bind_verified_phone() after an SMS OTP was proven. NULL means the number is claimed but unproven, and no money may move.';

-- Only a proven number can be addressed, so the uniqueness that matters is
-- across proven numbers. An unproven claim must never block a real one.
DROP INDEX IF EXISTS public.profiles_phone_uk;
CREATE UNIQUE INDEX IF NOT EXISTS profiles_verified_phone_uk
  ON public.profiles (phone) WHERE phone IS NOT NULL AND phone_verified_at IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 2. BINDING A PROVEN NUMBER — service_role only.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bind_verified_phone(
  p_user_id uuid,
  p_phone   text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $bind$
DECLARE
  v_phone text;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'A phone binding needs the account it belongs to'
      USING ERRCODE = '22023';
  END IF;

  -- Same normalisation the rest of the system uses, so a number proven here
  -- matches the one a sender types.
  v_phone := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g');
  IF v_phone !~ '^\+?[0-9]{6,15}$' THEN
    RAISE EXCEPTION 'That phone number does not look right'
      USING ERRCODE = '22023';
  END IF;

  -- A number proven by one account cannot be taken by another. Re-proving the
  -- same number on the same account is fine (re-install, number re-confirmed).
  IF EXISTS (
    SELECT 1 FROM public.profiles
    WHERE phone = v_phone
      AND phone_verified_at IS NOT NULL
      AND user_id <> p_user_id
  ) THEN
    RAISE EXCEPTION 'Another account has already verified that number'
      USING ERRCODE = '23505';
  END IF;

  -- Someone else may be sitting on this number as an UNPROVEN claim. Proof
  -- beats a claim, so their claim is released rather than blocking.
  UPDATE public.profiles
  SET phone = NULL
  WHERE phone = v_phone
    AND phone_verified_at IS NULL
    AND user_id <> p_user_id;

  INSERT INTO public.profiles (user_id, phone, phone_verified_at)
  VALUES (p_user_id, v_phone, now())
  ON CONFLICT (user_id) DO UPDATE
    SET phone = EXCLUDED.phone,
        phone_verified_at = now(),
        updated_at = now();

  -- A verified account needs somewhere to be paid.
  INSERT INTO public.wallets (user_id, balance) VALUES (p_user_id, 0)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN jsonb_build_object('phone', v_phone, 'verified', true);
END;
$bind$;

REVOKE ALL ON FUNCTION public.bind_verified_phone(uuid, text)
  FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bind_verified_phone(uuid, text) TO service_role;

-- ---------------------------------------------------------------------------
-- 3. CLOSE set_my_phone() TO CLIENTS.
-- Kept (not dropped) so an operator can still bind by hand with the
-- service-role key, but no longer reachable from the app.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.set_my_phone(text) FROM public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. THE GATE — no transfer to or from an unproven number.
-- Identical to the p2p_core version except for the two checks marked below.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.p2p_transfer(
  p_recipient_phone  text,
  p_amount           numeric,
  p_description      text DEFAULT '',
  p_idempotency_key  text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $xfer$
DECLARE
  caller          uuid := auth.uid();
  v_recipient     uuid;
  v_amount        numeric(14, 2);
  v_phone         text;
  v_sender_before numeric(14, 2);
  v_recip_before  numeric(14, 2);
  v_sender_name   text;
  v_recip_name    text;
  v_reference     uuid := gen_random_uuid();
  v_existing      public.transactions%ROWTYPE;
BEGIN
  IF caller IS NULL OR EXISTS (
    SELECT 1 FROM auth.users WHERE id = caller AND is_anonymous
  ) THEN
    RAISE EXCEPTION 'Sign in to an account before sending money'
      USING ERRCODE = '42501';
  END IF;

  -- GATE 1: the sender must have proven their own number.
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE user_id = caller AND phone_verified_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Verify your phone number before sending money'
      USING ERRCODE = '42501';
  END IF;

  v_amount := round(p_amount, 2);
  IF v_amount IS NULL OR v_amount <= 0 THEN
    RAISE EXCEPTION 'Enter an amount greater than zero'
      USING ERRCODE = '22023';
  END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM public.transactions
    WHERE user_id = caller AND idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'reference', v_existing.reference,
        'amount', v_existing.amount,
        'balance', v_existing.balance_after,
        'repeated', true
      );
    END IF;
  END IF;

  v_phone := regexp_replace(coalesce(p_recipient_phone, ''), '[^0-9+]', '', 'g');

  -- GATE 2: only a PROVEN number can be paid. Without this, claiming someone
  -- else's number quietly redirects their incoming money.
  SELECT user_id, full_name INTO v_recipient, v_recip_name
  FROM public.profiles
  WHERE phone = v_phone AND phone_verified_at IS NOT NULL;

  IF v_recipient IS NULL THEN
    RAISE EXCEPTION 'No Probashi Guard account uses that number'
      USING ERRCODE = 'P0002';
  END IF;
  IF v_recipient = caller THEN
    RAISE EXCEPTION 'You cannot send money to yourself'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.wallets (user_id, balance) VALUES (caller, 0)
  ON CONFLICT (user_id) DO NOTHING;
  INSERT INTO public.wallets (user_id, balance) VALUES (v_recipient, 0)
  ON CONFLICT (user_id) DO NOTHING;

  PERFORM 1 FROM public.wallets
  WHERE user_id IN (caller, v_recipient)
  ORDER BY user_id
  FOR UPDATE;

  SELECT balance INTO v_sender_before FROM public.wallets WHERE user_id = caller;
  SELECT balance INTO v_recip_before  FROM public.wallets WHERE user_id = v_recipient;

  IF v_sender_before < v_amount THEN
    RAISE EXCEPTION 'Your balance is not enough for this transfer'
      USING ERRCODE = '22023';
  END IF;

  SELECT full_name INTO v_sender_name FROM public.profiles WHERE user_id = caller;

  UPDATE public.wallets
  SET balance = balance - v_amount, updated_at = now()
  WHERE user_id = caller;

  UPDATE public.wallets
  SET balance = balance + v_amount, updated_at = now()
  WHERE user_id = v_recipient;

  INSERT INTO public.transactions (
    reference, user_id, direction, purpose, amount,
    balance_before, balance_after,
    counterparty_id, counterparty_name, counterparty_phone,
    description, idempotency_key
  ) VALUES (
    v_reference, caller, 'debit', 'transfer', v_amount,
    v_sender_before, v_sender_before - v_amount,
    v_recipient, coalesce(v_recip_name, ''), v_phone,
    coalesce(p_description, ''), p_idempotency_key
  );

  INSERT INTO public.transactions (
    reference, user_id, direction, purpose, amount,
    balance_before, balance_after,
    counterparty_id, counterparty_name, counterparty_phone,
    description
  ) VALUES (
    v_reference, v_recipient, 'credit', 'transfer', v_amount,
    v_recip_before, v_recip_before + v_amount,
    caller, coalesce(v_sender_name, ''), NULL,
    coalesce(p_description, '')
  );

  RETURN jsonb_build_object(
    'reference', v_reference,
    'amount', v_amount,
    'balance', v_sender_before - v_amount,
    'recipient_name', coalesce(v_recip_name, ''),
    'repeated', false
  );
END;
$xfer$;

-- ---------------------------------------------------------------------------
-- 5. lookup_recipient() must agree with the gate, or the confirmation step
-- would name somebody the transfer then refuses to pay.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.lookup_recipient(p_phone text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  caller  uuid := auth.uid();
  v_phone text;
  v_name  text;
BEGIN
  IF caller IS NULL THEN
    RAISE EXCEPTION 'Sign in first' USING ERRCODE = '42501';
  END IF;

  v_phone := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g');
  SELECT full_name INTO v_name FROM public.profiles
  WHERE phone = v_phone
    AND phone_verified_at IS NOT NULL
    AND user_id <> caller;

  IF v_name IS NULL THEN
    RETURN jsonb_build_object('found', false);
  END IF;
  RETURN jsonb_build_object('found', true, 'full_name', v_name);
END;
$fn$;

-- ---------------------------------------------------------------------------
-- 6. Tell the app whether it still owes a verification, without exposing
-- anybody else's state.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.my_phone_status()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  caller uuid := auth.uid();
  v_row  public.profiles%ROWTYPE;
BEGIN
  IF caller IS NULL THEN
    RAISE EXCEPTION 'Sign in first' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row FROM public.profiles WHERE user_id = caller;
  RETURN jsonb_build_object(
    'phone',    v_row.phone,
    'verified', v_row.phone_verified_at IS NOT NULL
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.my_phone_status() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.my_phone_status() TO authenticated;

-- ---------------------------------------------------------------------------
-- 7. THE DEPOSIT GATE — defence in depth, and why the order matters.
--
-- The gate that actually protects people is in backend_service: a Checkout
-- session is refused for an unverified account, BEFORE Stripe charges
-- anything. This one should therefore never fire.
--
-- If it ever does, the person has already paid. Refusing here means their
-- money was taken and not credited, so it raises a distinctive SQLSTATE
-- (P0003) that the webhook logs as needing manual reconciliation rather than
-- swallowing as an ordinary failure. That is the lesser evil versus crediting
-- a wallet whose owner was never verified, but it is still money in limbo —
-- which is exactly why the real check sits before the charge.
-- ---------------------------------------------------------------------------
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
AS $dep$
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

  v_amount := round(p_amount, 2);
  IF v_amount IS NULL OR v_amount <= 0 THEN
    RAISE EXCEPTION 'A deposit must be greater than zero'
      USING ERRCODE = '22023';
  END IF;

  -- Replay check comes BEFORE the gate: a deposit already booked must keep
  -- reporting its first result even if the account's state changed since.
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

  -- THE GATE.
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE user_id = p_user_id AND phone_verified_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION
      'Paid but not credited: account % has no verified phone', p_user_id
      USING ERRCODE = 'P0003';
  END IF;

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
$dep$;

REVOKE ALL ON FUNCTION public.deposit_to_wallet(uuid, numeric, text, text)
  FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.deposit_to_wallet(uuid, numeric, text, text)
  TO service_role;

-- ---------------------------------------------------------------------------
-- 8. THE VERIFICATION COLUMN IS NOT CLIENT-WRITABLE.
--
-- Re-asserted rather than assumed. A column-level GRANT UPDATE does not
-- extend to columns added later, so `phone_verified_at` is already outside
-- the (full_name, avatar_url) grant from 20261019150000 — but starting from
-- REVOKE ALL makes that a stated guarantee instead of a side effect, and
-- survives someone re-running an older grant by hand.
--
-- `phone` is excluded too: it may only change through bind_verified_phone().
-- ---------------------------------------------------------------------------
REVOKE ALL ON public.profiles FROM anon, authenticated;
GRANT SELECT ON public.profiles TO authenticated;
GRANT UPDATE (full_name, avatar_url) ON public.profiles TO authenticated;
