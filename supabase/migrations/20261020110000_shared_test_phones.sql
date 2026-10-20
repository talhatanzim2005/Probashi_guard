-- Shared pool of accounts for Firebase TEST phone numbers.
--
-- A phone number normally belongs to exactly one account: p2p_transfer() pays a
-- number, so two owners would make a payment ambiguous. A Firebase console test
-- number is the opposite: it sends no SMS, costs nothing, and every tester types
-- the same one. So backend_service marks a number from FIREBASE_TEST_PHONES as
-- SHARED when it binds it, and up to 50 accounts may then hold it at once; the
-- 51st evicts the oldest holder (first in, first out). A real number is never
-- shared: it stays strictly one account.
--
--   profiles.phone_is_shared        true on the rows holding a shared test number
--   profiles_verified_phone_uk      unique per number, EXCEPT for shared rows
--   bind_verified_phone(...)        takes p_shared / p_shared_cap; evicts FIFO
--   p2p_transfer / lookup_recipient never resolve a shared number to anybody
--
-- It also repairs a bug in sub_wallets: bind_verified_phone() still upserted
-- wallets ON CONFLICT (user_id), a constraint that migration dropped, so binding
-- ANY phone would fail with "no unique or exclusion constraint matching". It now
-- opens all three card wallets.
--
-- Run AFTER 20261020100000_sub_wallets.sql. APPLY VIA THE SUPABASE DASHBOARD SQL
-- EDITOR, one numbered part at a time. NEVER supabase db push. Safe to re-run.

-- ===========================================================================
-- PART 1: SCHEMA
-- ===========================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS phone_is_shared boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.profiles.phone_is_shared IS
  'True when phone is a Firebase test number shared by up to 50 accounts. Set only by bind_verified_phone(). Such a number never resolves to a recipient.';

-- One account per VERIFIED number, but a shared test number may repeat.
DROP INDEX IF EXISTS public.profiles_verified_phone_uk;
CREATE UNIQUE INDEX IF NOT EXISTS profiles_verified_phone_uk
  ON public.profiles (phone)
  WHERE phone IS NOT NULL AND phone_verified_at IS NOT NULL AND NOT phone_is_shared;

-- Finding the holders of a shared number (eviction, counting) stays cheap.
CREATE INDEX IF NOT EXISTS profiles_shared_phone_idx
  ON public.profiles (phone, phone_verified_at)
  WHERE phone_is_shared;

-- ===========================================================================
-- PART 2: BINDING
-- ===========================================================================

-- The two-argument version is dropped first: left beside the new one, a call
-- with two arguments would match both and fail as ambiguous.
DROP FUNCTION IF EXISTS public.bind_verified_phone(uuid, text);

CREATE OR REPLACE FUNCTION public.bind_verified_phone(
  p_user_id     uuid,
  p_phone       text,
  p_shared      boolean DEFAULT false,
  p_shared_cap  integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $bind$
DECLARE
  v_phone   text;
  v_holders integer;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'A phone binding needs the account it belongs to'
      USING ERRCODE = '22023';
  END IF;

  v_phone := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g');
  IF v_phone !~ '^\+?[0-9]{6,15}$' THEN
    RAISE EXCEPTION 'That phone number does not look right'
      USING ERRCODE = '22023';
  END IF;

  IF coalesce(p_shared, false) THEN
    IF p_shared_cap IS NULL OR p_shared_cap < 1 THEN
      RAISE EXCEPTION 'A shared number needs a pool size of at least 1'
        USING ERRCODE = '22023';
    END IF;

    -- Two accounts verifying at the same instant must not both see room for one
    -- more: take a lock keyed on the number for the rest of this transaction.
    PERFORM pg_advisory_xact_lock(hashtext('shared_phone:' || v_phone));

    SELECT count(*) INTO v_holders FROM public.profiles
    WHERE phone = v_phone AND phone_verified_at IS NOT NULL AND user_id <> p_user_id;

    -- Full: make room by releasing the oldest holders (first in, first out).
    -- This account is not counted, so after it joins the total is exactly the
    -- cap. An account that already holds the number just refreshes below and
    -- moves to the back of the queue.
    IF v_holders >= p_shared_cap THEN
      UPDATE public.profiles
      SET phone = NULL, phone_verified_at = NULL, phone_is_shared = false,
          updated_at = now()
      WHERE user_id IN (
        SELECT user_id FROM public.profiles
        WHERE phone = v_phone AND phone_verified_at IS NOT NULL
          AND user_id <> p_user_id
        ORDER BY phone_verified_at ASC, user_id ASC
        LIMIT v_holders - p_shared_cap + 1
      );
    END IF;

    -- A holder from before this number was marked shared joins the pool.
    UPDATE public.profiles SET phone_is_shared = true
    WHERE phone = v_phone AND phone_verified_at IS NOT NULL AND user_id <> p_user_id;
  ELSE
    -- A real number belongs to one account. Re-proving it on the same account
    -- is fine (re-install, number re-confirmed).
    IF EXISTS (
      SELECT 1 FROM public.profiles
      WHERE phone = v_phone
        AND phone_verified_at IS NOT NULL
        AND user_id <> p_user_id
    ) THEN
      RAISE EXCEPTION 'Another account has already verified that number'
        USING ERRCODE = '23505';
    END IF;
  END IF;

  -- Someone else may be sitting on this number as an UNPROVEN claim. Proof
  -- beats a claim, so their claim is released rather than blocking.
  UPDATE public.profiles
  SET phone = NULL
  WHERE phone = v_phone
    AND phone_verified_at IS NULL
    AND user_id <> p_user_id;

  INSERT INTO public.profiles (user_id, phone, phone_verified_at, phone_is_shared)
  VALUES (p_user_id, v_phone, now(), coalesce(p_shared, false))
  ON CONFLICT (user_id) DO UPDATE
    SET phone = EXCLUDED.phone,
        phone_verified_at = now(),
        phone_is_shared = EXCLUDED.phone_is_shared,
        updated_at = now();

  -- A verified account needs somewhere to be paid. (One wallet per card now.)
  INSERT INTO public.wallets (user_id, balance, card_id)
  VALUES (p_user_id, 0, 'card_wps'),
         (p_user_id, 0, 'card_probashi'),
         (p_user_id, 0, 'card_visa')
  ON CONFLICT (user_id, card_id) DO NOTHING;

  RETURN jsonb_build_object(
    'phone', v_phone,
    'verified', true,
    'shared', coalesce(p_shared, false)
  );
END;
$bind$;

REVOKE ALL ON FUNCTION public.bind_verified_phone(uuid, text, boolean, integer)
  FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bind_verified_phone(uuid, text, boolean, integer)
  TO service_role;

-- ===========================================================================
-- PART 3: A SHARED NUMBER NEVER NAMES A RECIPIENT
-- ===========================================================================
-- Many accounts hold it, so "send to this number" would pick one at random.

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
    RAISE EXCEPTION 'Enter an amount greater than zero' USING ERRCODE = '22023';
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

  -- GATE 2: only a PROVEN number can be paid, and only one that belongs to a
  -- single account. A shared Firebase test number is held by many accounts, so
  -- it names nobody in particular and can never receive a transfer.
  SELECT user_id, full_name INTO v_recipient, v_recip_name
  FROM public.profiles
  WHERE phone = v_phone AND phone_verified_at IS NOT NULL
    AND NOT phone_is_shared;

  IF v_recipient IS NULL THEN
    RAISE EXCEPTION 'No Probashi Guard account uses that number' USING ERRCODE = 'P0002';
  END IF;
  IF v_recipient = caller THEN
    RAISE EXCEPTION 'You cannot send money to yourself' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.wallets (user_id, balance, card_id)
  VALUES (caller, 0, 'card_wps'), (v_recipient, 0, 'card_wps')
  ON CONFLICT (user_id, card_id) DO NOTHING;

  PERFORM 1 FROM public.wallets
  WHERE card_id = 'card_wps' AND user_id IN (caller, v_recipient)
  ORDER BY user_id
  FOR UPDATE;

  SELECT balance INTO v_sender_before FROM public.wallets
  WHERE user_id = caller AND card_id = 'card_wps';
  SELECT balance INTO v_recip_before FROM public.wallets
  WHERE user_id = v_recipient AND card_id = 'card_wps';

  IF v_sender_before < v_amount THEN
    RAISE EXCEPTION 'Your balance is not enough for this transfer' USING ERRCODE = '22023';
  END IF;

  SELECT full_name INTO v_sender_name FROM public.profiles WHERE user_id = caller;

  UPDATE public.wallets
  SET balance = balance - v_amount, updated_at = now()
  WHERE user_id = caller AND card_id = 'card_wps';

  UPDATE public.wallets
  SET balance = balance + v_amount, updated_at = now()
  WHERE user_id = v_recipient AND card_id = 'card_wps';

  INSERT INTO public.transactions (
    reference, user_id, direction, purpose, amount,
    balance_before, balance_after,
    counterparty_id, counterparty_name, counterparty_phone,
    description, idempotency_key, card_id
  ) VALUES (
    v_reference, caller, 'debit', 'transfer', v_amount,
    v_sender_before, v_sender_before - v_amount,
    v_recipient, coalesce(v_recip_name, ''), v_phone,
    coalesce(p_description, ''), p_idempotency_key, 'card_wps'
  );

  INSERT INTO public.transactions (
    reference, user_id, direction, purpose, amount,
    balance_before, balance_after,
    counterparty_id, counterparty_name, counterparty_phone,
    description, card_id
  ) VALUES (
    v_reference, v_recipient, 'credit', 'transfer', v_amount,
    v_recip_before, v_recip_before + v_amount,
    caller, coalesce(v_sender_name, ''), NULL,
    coalesce(p_description, ''), 'card_wps'
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

  PERFORM public.enforce_rate_limit(caller, 'lookup_recipient', 20, interval '1 minute');

  v_phone := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g');
  SELECT full_name INTO v_name FROM public.profiles
  WHERE phone = v_phone
    AND phone_verified_at IS NOT NULL
    AND NOT phone_is_shared
    AND user_id <> caller;

  IF v_name IS NULL THEN
    RETURN jsonb_build_object('found', false);
  END IF;
  RETURN jsonb_build_object('found', true, 'full_name', v_name);
END;
$fn$;

-- ===========================================================================
-- VERIFY (read-only; run after all parts)
-- ===========================================================================
-- 1. Nobody is verified twice on a real number:
--    select phone, count(*) from public.profiles
--    where phone_verified_at is not null and not phone_is_shared
--    group by 1 having count(*) > 1;                                 -- 0 rows
-- 2. A shared number never exceeds 50 holders:
--    select phone, count(*) from public.profiles
--    where phone_verified_at is not null and phone_is_shared
--    group by 1 having count(*) > 50;                                -- 0 rows
-- 3. The old two-argument function is gone and only service_role can run the new one:
--    select oidvectortypes(p.proargtypes) as args,
--           has_function_privilege('authenticated', p.oid, 'EXECUTE') as authed
--    from pg_proc p where p.proname = 'bind_verified_phone';         -- 1 row, authed = false
