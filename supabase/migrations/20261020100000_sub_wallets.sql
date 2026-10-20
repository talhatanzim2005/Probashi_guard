-- Sub-wallets: one ledger wallet per CARD instead of one per user.
--
-- The app shows three cards (WPS payroll, Probashi expatriate, Probashi Global
-- Visa), each with its own balance. The ledger only had one wallet per user, so
-- the app invented the other two balances locally and every write it tried
-- against the ledger failed. This migration gives each card a real wallet:
--
--   wallets.card_id            which card the balance belongs to
--   transactions.card_id       which card a ledger leg moved
--   internal_transfer()        move money between YOUR OWN cards (no Stripe)
--   settle_remittance()        book a paid Stripe remittance (webhook only)
--   deposit_to_wallet()        now card-aware (defaults to card_wps)
--   p2p_transfer()             unchanged API; always sends from / lands in card_wps
--   ensure_my_wallet()/handle_new_user()   open all three wallets
--
-- APPLY VIA THE SUPABASE DASHBOARD SQL EDITOR, in the numbered parts below, one
-- part at a time (the editor truncates long pastes). NEVER `supabase db push`:
-- this project's migration history has drifted.
-- Every part is safe to run more than once.

-- ===========================================================================
-- PART 1: SCHEMA
-- ===========================================================================

ALTER TABLE public.wallets
  ADD COLUMN IF NOT EXISTS card_id text NOT NULL DEFAULT 'card_wps';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'wallets_card_id_check'
  ) THEN
    ALTER TABLE public.wallets
      ADD CONSTRAINT wallets_card_id_check
      CHECK (card_id IN ('card_wps', 'card_probashi', 'card_visa'));
  END IF;
END $$;

ALTER TABLE public.wallets DROP CONSTRAINT IF EXISTS wallets_user_uk;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'wallets_user_card_uk'
  ) THEN
    ALTER TABLE public.wallets
      ADD CONSTRAINT wallets_user_card_uk UNIQUE (user_id, card_id);
  END IF;
END $$;

-- Existing accounts get the two wallets they were missing, at zero. An empty
-- wallet is an identity row, not a balance change.
INSERT INTO public.wallets (user_id, balance, card_id)
SELECT w.user_id, 0, c.card_id
FROM (SELECT DISTINCT user_id FROM public.wallets) w
CROSS JOIN (VALUES ('card_wps'), ('card_probashi'), ('card_visa')) AS c(card_id)
ON CONFLICT (user_id, card_id) DO NOTHING;

-- Null on rows written before this migration.
ALTER TABLE public.transactions
  ADD COLUMN IF NOT EXISTS card_id text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'transactions_card_id_check'
  ) THEN
    ALTER TABLE public.transactions
      ADD CONSTRAINT transactions_card_id_check
      CHECK (card_id IS NULL OR card_id IN ('card_wps', 'card_probashi', 'card_visa'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS transactions_user_card_created_idx
  ON public.transactions (user_id, card_id, created_at DESC);

-- ===========================================================================
-- PART 2: ACCOUNT CREATION OPENS ALL THREE WALLETS
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (user_id, full_name, phone)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name',
             NEW.raw_user_meta_data ->> 'name', ''),
    NULLIF(NEW.phone, '')
  )
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.wallets (user_id, balance, card_id)
  VALUES (NEW.id, 0, 'card_wps'),
         (NEW.id, 0, 'card_probashi'),
         (NEW.id, 0, 'card_visa')
  ON CONFLICT (user_id, card_id) DO NOTHING;

  RETURN NEW;
END;
$$;

-- Returns the WPS (primary) balance, as before. Opens whatever is missing.
CREATE OR REPLACE FUNCTION public.ensure_my_wallet()
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller  uuid := auth.uid();
  current numeric(14, 2);
BEGIN
  IF caller IS NULL THEN
    RAISE EXCEPTION 'Sign in first' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.profiles (user_id) VALUES (caller)
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.wallets (user_id, balance, card_id)
  VALUES (caller, 0, 'card_wps'),
         (caller, 0, 'card_probashi'),
         (caller, 0, 'card_visa')
  ON CONFLICT (user_id, card_id) DO NOTHING;

  SELECT balance INTO current FROM public.wallets
  WHERE user_id = caller AND card_id = 'card_wps';
  RETURN current;
END;
$$;

-- ===========================================================================
-- PART 3: MOVING MONEY BETWEEN YOUR OWN CARDS
-- ===========================================================================
-- Authenticated callers may run this: it can only ever move the CALLER's own
-- money between the CALLER's own wallets (the user is auth.uid(), never an
-- argument), so no balance can be created and nobody else's can be touched.
-- Not phone-gated for the same reason: the money never leaves its owner.

CREATE OR REPLACE FUNCTION public.internal_transfer(
  p_from_card        text,
  p_to_card          text,
  p_amount           numeric,
  p_idempotency_key  text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $int$
DECLARE
  caller        uuid := auth.uid();
  v_amount      numeric(14, 2);
  v_from_before numeric(14, 2);
  v_to_before   numeric(14, 2);
  v_reference   uuid := gen_random_uuid();
  v_existing    public.transactions%ROWTYPE;
  v_from_after  numeric(14, 2);
BEGIN
  IF caller IS NULL OR EXISTS (
    SELECT 1 FROM auth.users WHERE id = caller AND is_anonymous
  ) THEN
    RAISE EXCEPTION 'Sign in to an account before moving money'
      USING ERRCODE = '42501';
  END IF;

  IF p_from_card IS NULL OR p_to_card IS NULL
     OR p_from_card NOT IN ('card_wps', 'card_probashi', 'card_visa')
     OR p_to_card   NOT IN ('card_wps', 'card_probashi', 'card_visa') THEN
    RAISE EXCEPTION 'Unknown card' USING ERRCODE = '22023';
  END IF;
  IF p_from_card = p_to_card THEN
    RAISE EXCEPTION 'Choose two different cards' USING ERRCODE = '22023';
  END IF;

  v_amount := round(p_amount, 2);
  IF v_amount IS NULL OR v_amount <= 0 THEN
    RAISE EXCEPTION 'Enter an amount greater than zero' USING ERRCODE = '22023';
  END IF;

  -- A retried request reports the first result instead of moving money twice.
  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM public.transactions
    WHERE user_id = caller AND idempotency_key = p_idempotency_key || ':debit';
    IF FOUND THEN
      RETURN jsonb_build_object(
        'reference', v_existing.reference,
        'amount', v_existing.amount,
        'from_balance', v_existing.balance_after,
        'repeated', true
      );
    END IF;
  END IF;

  INSERT INTO public.wallets (user_id, balance, card_id)
  VALUES (caller, 0, p_from_card), (caller, 0, p_to_card)
  ON CONFLICT (user_id, card_id) DO NOTHING;

  -- Both rows locked in a fixed order, so two opposite swaps cannot deadlock.
  PERFORM 1 FROM public.wallets
  WHERE user_id = caller AND card_id IN (p_from_card, p_to_card)
  ORDER BY card_id
  FOR UPDATE;

  SELECT balance INTO v_from_before FROM public.wallets
  WHERE user_id = caller AND card_id = p_from_card;
  SELECT balance INTO v_to_before FROM public.wallets
  WHERE user_id = caller AND card_id = p_to_card;

  IF v_from_before < v_amount THEN
    RAISE EXCEPTION 'That card does not have enough balance'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.wallets
  SET balance = balance - v_amount, updated_at = now()
  WHERE user_id = caller AND card_id = p_from_card;

  UPDATE public.wallets
  SET balance = balance + v_amount, updated_at = now()
  WHERE user_id = caller AND card_id = p_to_card;

  v_from_after := v_from_before - v_amount;

  INSERT INTO public.transactions (
    reference, user_id, direction, purpose, amount,
    balance_before, balance_after, description, idempotency_key, card_id
  ) VALUES (
    v_reference, caller, 'debit', 'transfer', v_amount,
    v_from_before, v_from_after,
    'Transfer to ' || p_to_card,
    CASE WHEN p_idempotency_key IS NULL THEN NULL ELSE p_idempotency_key || ':debit' END,
    p_from_card
  );

  INSERT INTO public.transactions (
    reference, user_id, direction, purpose, amount,
    balance_before, balance_after, description, idempotency_key, card_id
  ) VALUES (
    v_reference, caller, 'credit', 'transfer', v_amount,
    v_to_before, v_to_before + v_amount,
    'Transfer from ' || p_from_card,
    CASE WHEN p_idempotency_key IS NULL THEN NULL ELSE p_idempotency_key || ':credit' END,
    p_to_card
  );

  RETURN jsonb_build_object(
    'reference', v_reference,
    'amount', v_amount,
    'from_balance', v_from_after,
    'to_balance', v_to_before + v_amount,
    'repeated', false
  );
END;
$int$;

REVOKE ALL ON FUNCTION public.internal_transfer(text, text, numeric, text)
  FROM public, anon;
GRANT EXECUTE ON FUNCTION public.internal_transfer(text, text, numeric, text)
  TO authenticated;

-- ===========================================================================
-- PART 4: FUNDING AND REMITTANCE (service_role only)
-- ===========================================================================

-- The old four-argument signature is dropped first: leaving it beside the new
-- one would make a four-argument call ambiguous.
DROP FUNCTION IF EXISTS public.deposit_to_wallet(uuid, numeric, text, text);

CREATE OR REPLACE FUNCTION public.deposit_to_wallet(
  p_user_id         uuid,
  p_amount          numeric,
  p_idempotency_key text,
  p_description     text DEFAULT '',
  p_card_id         text DEFAULT 'card_wps'
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
    RAISE EXCEPTION 'A deposit needs the account it belongs to' USING ERRCODE = '22023';
  END IF;
  IF p_idempotency_key IS NULL OR length(btrim(p_idempotency_key)) = 0 THEN
    RAISE EXCEPTION 'A deposit needs an idempotency key' USING ERRCODE = '22023';
  END IF;
  IF p_card_id IS NULL OR p_card_id NOT IN ('card_wps', 'card_probashi', 'card_visa') THEN
    RAISE EXCEPTION 'Unknown card' USING ERRCODE = '22023';
  END IF;

  v_amount := round(p_amount, 2);
  IF v_amount IS NULL OR v_amount <= 0 THEN
    RAISE EXCEPTION 'A deposit must be greater than zero' USING ERRCODE = '22023';
  END IF;

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

  INSERT INTO public.wallets (user_id, balance, card_id)
  VALUES (p_user_id, 0, p_card_id)
  ON CONFLICT (user_id, card_id) DO NOTHING;

  PERFORM 1 FROM public.wallets
  WHERE user_id = p_user_id AND card_id = p_card_id FOR UPDATE;
  SELECT balance INTO v_before FROM public.wallets
  WHERE user_id = p_user_id AND card_id = p_card_id;

  UPDATE public.wallets
  SET balance = balance + v_amount, updated_at = now()
  WHERE user_id = p_user_id AND card_id = p_card_id;

  INSERT INTO public.transactions (
    reference, user_id, direction, purpose, amount,
    balance_before, balance_after, description, idempotency_key, card_id
  ) VALUES (
    v_reference, p_user_id, 'credit', 'deposit', v_amount,
    v_before, v_before + v_amount, coalesce(p_description, ''), p_idempotency_key, p_card_id
  );

  RETURN jsonb_build_object(
    'reference', v_reference,
    'amount',    v_amount,
    'balance',   v_before + v_amount,
    'repeated',  false
  );
END;
$dep$;

REVOKE ALL ON FUNCTION public.deposit_to_wallet(uuid, numeric, text, text, text)
  FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.deposit_to_wallet(uuid, numeric, text, text, text)
  TO service_role;

-- A paid Stripe remittance. The card payment brings money in and the transfer
-- sends it on to the recipient, so the card's balance ends where it started and
-- the ledger shows both legs. Called by the webhook with the service-role key;
-- the session id makes Stripe's retries book it once.
CREATE OR REPLACE FUNCTION public.settle_remittance(
  p_user_id          uuid,
  p_card_id          text,
  p_session_id       text,
  p_amount_bdt       numeric,
  p_recipient_name   text DEFAULT '',
  p_recipient_phone  text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $rem$
DECLARE
  v_amount    numeric(14, 2);
  v_before    numeric(14, 2);
  v_reference uuid := gen_random_uuid();
  v_existing  public.transactions%ROWTYPE;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'A remittance needs the account it belongs to' USING ERRCODE = '22023';
  END IF;
  IF p_session_id IS NULL OR length(btrim(p_session_id)) = 0 THEN
    RAISE EXCEPTION 'A remittance needs its payment session id' USING ERRCODE = '22023';
  END IF;
  IF p_card_id IS NULL OR p_card_id NOT IN ('card_wps', 'card_probashi', 'card_visa') THEN
    RAISE EXCEPTION 'Unknown card' USING ERRCODE = '22023';
  END IF;

  v_amount := round(p_amount_bdt, 2);
  IF v_amount IS NULL OR v_amount <= 0 THEN
    RAISE EXCEPTION 'A remittance must be greater than zero' USING ERRCODE = '22023';
  END IF;

  -- The debit leg is written last, so its presence means the whole thing booked.
  SELECT * INTO v_existing FROM public.transactions
  WHERE user_id = p_user_id AND idempotency_key = p_session_id || ':debit';
  IF FOUND THEN
    RETURN jsonb_build_object(
      'reference', v_existing.reference,
      'amount',    v_existing.amount,
      'balance',   v_existing.balance_after,
      'repeated',  true
    );
  END IF;

  INSERT INTO public.wallets (user_id, balance, card_id)
  VALUES (p_user_id, 0, p_card_id)
  ON CONFLICT (user_id, card_id) DO NOTHING;

  PERFORM 1 FROM public.wallets
  WHERE user_id = p_user_id AND card_id = p_card_id FOR UPDATE;
  SELECT balance INTO v_before FROM public.wallets
  WHERE user_id = p_user_id AND card_id = p_card_id;

  -- Money in from the card payment...
  INSERT INTO public.transactions (
    reference, user_id, direction, purpose, amount,
    balance_before, balance_after,
    description, idempotency_key, card_id
  ) VALUES (
    v_reference, p_user_id, 'credit', 'deposit', v_amount,
    v_before, v_before + v_amount,
    'Added from your card', p_session_id || ':credit', p_card_id
  );

  -- ...and out to the recipient. The balance is unchanged overall.
  INSERT INTO public.transactions (
    reference, user_id, direction, purpose, amount,
    balance_before, balance_after,
    counterparty_name, counterparty_phone,
    description, idempotency_key, card_id
  ) VALUES (
    v_reference, p_user_id, 'debit', 'withdrawal', v_amount,
    v_before + v_amount, v_before,
    coalesce(p_recipient_name, ''), p_recipient_phone,
    'Sent to ' || coalesce(nullif(p_recipient_name, ''), 'recipient'),
    p_session_id || ':debit', p_card_id
  );

  RETURN jsonb_build_object(
    'reference', v_reference,
    'amount',    v_amount,
    'balance',   v_before,
    'repeated',  false
  );
END;
$rem$;

REVOKE ALL ON FUNCTION public.settle_remittance(uuid, text, text, numeric, text, text)
  FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.settle_remittance(uuid, text, text, numeric, text, text)
  TO service_role;

-- ===========================================================================
-- PART 5: P2P TRANSFERS USE THE PRIMARY (WPS) WALLET
-- ===========================================================================
-- Same checks and result as the verified-phone-gate version; the only change is
-- that every wallet lookup is scoped to card_wps now that a user has three.

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

  -- GATE 2: only a PROVEN number can be paid.
  SELECT user_id, full_name INTO v_recipient, v_recip_name
  FROM public.profiles
  WHERE phone = v_phone AND phone_verified_at IS NOT NULL;

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

-- ===========================================================================
-- PART 6: RATE-LIMIT RECIPIENT LOOKUPS (anti-scraping)
-- ===========================================================================
-- lookup_recipient() answers "who owns this number?" to any signed-in caller,
-- so a script could walk the number space and harvest names. A per-caller
-- fixed-window counter caps that; ordinary use (a handful of lookups while
-- choosing a recipient) never gets near it.

CREATE TABLE IF NOT EXISTS public.rpc_rate_limits (
  user_id      uuid        NOT NULL,
  bucket       text        NOT NULL,
  window_start timestamptz NOT NULL,
  hits         integer     NOT NULL DEFAULT 0,
  CONSTRAINT rpc_rate_limits_pk PRIMARY KEY (user_id, bucket, window_start)
);

ALTER TABLE public.rpc_rate_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rpc_rate_limits FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.enforce_rate_limit(
  p_user    uuid,
  p_bucket  text,
  p_max     integer,
  p_window  interval
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $rl$
DECLARE
  v_start timestamptz;
  v_hits  integer;
BEGIN
  -- Window boundaries are aligned to the interval, so every caller in the same
  -- window shares one row and old rows can be swept.
  v_start := to_timestamp(
    floor(extract(epoch FROM now()) / extract(epoch FROM p_window))
      * extract(epoch FROM p_window)
  );

  INSERT INTO public.rpc_rate_limits AS r (user_id, bucket, window_start, hits)
  VALUES (p_user, p_bucket, v_start, 1)
  ON CONFLICT (user_id, bucket, window_start)
  DO UPDATE SET hits = r.hits + 1
  RETURNING r.hits INTO v_hits;

  IF v_hits > p_max THEN
    RAISE EXCEPTION 'Too many lookups. Please wait a minute and try again.'
      USING ERRCODE = '54000';
  END IF;

  -- Housekeeping: drop this caller's windows from long ago.
  DELETE FROM public.rpc_rate_limits
  WHERE user_id = p_user AND bucket = p_bucket
    AND window_start < now() - (p_window * 10);
END;
$rl$;

REVOKE ALL ON FUNCTION public.enforce_rate_limit(uuid, text, integer, interval)
  FROM public, anon, authenticated;

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
-- 1. Every user has exactly three wallets:
--    select user_id, count(*) from public.wallets group by 1 having count(*) <> 3;   -- 0 rows
-- 2. Who can run what:
--    select p.proname, has_function_privilege('authenticated', p.oid, 'EXECUTE') as authed
--    from pg_proc p where p.pronamespace = 'public'::regnamespace
--      and p.proname in ('internal_transfer','settle_remittance','deposit_to_wallet','enforce_rate_limit');
--    -- internal_transfer = true; the other three = false.
