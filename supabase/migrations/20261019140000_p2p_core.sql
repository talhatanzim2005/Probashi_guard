-- Migration: 20261019140000_p2p_core.sql
-- Description: The P2P money-transfer core — profiles, wallets, payment
-- methods and a double-entry transaction ledger — plus the transfer function.
--
-- Shape adapted from the Pay-Mobile-Server reference backend
-- (github.com/adedayoniyi/Pay-Mobile-Server): a transfer writes TWO ledger
-- rows, a debit on the sender and a credit on the recipient, sharing one
-- `reference`, and every row snapshots `balance_before` / `balance_after`.
--
-- What is deliberately NOT carried over from that reference:
--   * It runs debit and credit through Promise.all, each re-reading the
--     balance without a lock. Two concurrent transfers can both pass the
--     balance check and overdraw. Here both wallet rows are locked FOR UPDATE,
--     in user_id order so two opposite transfers cannot deadlock.
--   * It never validates the amount. A negative amount reaches `$inc: -amount`
--     and CREDITS the sender. Here amount_bdt must be > 0, by CHECK and by
--     an explicit test in the function.
--   * Its /api/fundWallet credits a balance on request with no proof of
--     payment. Nothing here can raise a balance except a transfer from another
--     account; funding stays behind the Stripe webhook.
--   * It has no idempotency key, so a retried request transfers twice.
--
-- NO SEED DATA. Every account starts with a zero balance, no cards and no
-- history. Nothing in this file inserts a demo card, contact or transaction.
--
-- Safe to run more than once.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- 0. RETIRE THE OLD SHAPE
-- The previous wallets/transactions tables hold only test rows and do not fit
-- the ledger below. They are RENAMED, not dropped, so the rows survive and can
-- be inspected or restored; client roles lose access to them.
-- New tables name their constraints explicitly (…_pk, not the automatic
-- …_pkey) so they cannot collide with the legacy table's constraint names.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema = 'public' AND table_name = 'wallets')
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema = 'public' AND table_name = 'wallets'
                       AND column_name = 'balance')
  THEN
    ALTER TABLE public.wallets RENAME TO wallets_legacy_20261019;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema = 'public' AND table_name = 'transactions')
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema = 'public' AND table_name = 'transactions'
                       AND column_name = 'balance_before')
  THEN
    ALTER TABLE public.transactions RENAME TO transactions_legacy_20261019;
  END IF;
END $$;

DO $$
BEGIN
  EXECUTE 'REVOKE ALL ON public.wallets_legacy_20261019 FROM anon, authenticated';
EXCEPTION WHEN undefined_table THEN NULL;
END $$;
DO $$
BEGIN
  EXECUTE 'REVOKE ALL ON public.transactions_legacy_20261019 FROM anon, authenticated';
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

-- ---------------------------------------------------------------------------
-- 1. PROFILES — the public identity a transfer is addressed to.
-- auth.users.phone stays empty because the app signs in by email, so the
-- phone a sender types has to resolve here.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
  user_id    uuid NOT NULL,
  full_name  text NOT NULL DEFAULT '',
  phone      text,
  avatar_url text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT profiles_pk PRIMARY KEY (user_id),
  CONSTRAINT profiles_user_fk FOREIGN KEY (user_id)
    REFERENCES auth.users (id) ON DELETE CASCADE,
  CONSTRAINT profiles_phone_format CHECK (phone IS NULL OR phone ~ '^\+?[0-9]{6,15}$')
);

-- One account per phone number, so a transfer can never be ambiguous.
CREATE UNIQUE INDEX IF NOT EXISTS profiles_phone_uk
  ON public.profiles (phone) WHERE phone IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 2. WALLETS — one per user, opened at zero.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.wallets (
  id          uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL,
  balance     numeric(14, 2) NOT NULL DEFAULT 0,
  currency    text NOT NULL DEFAULT 'BDT',
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT wallets_pk PRIMARY KEY (id),
  CONSTRAINT wallets_user_uk UNIQUE (user_id),
  CONSTRAINT wallets_user_fk FOREIGN KEY (user_id)
    REFERENCES auth.users (id) ON DELETE CASCADE,
  -- A wallet can never go negative, whatever the application does.
  CONSTRAINT wallets_balance_non_negative CHECK (balance >= 0)
);

-- ---------------------------------------------------------------------------
-- 3. PAYMENT_METHODS — cards and bank accounts the person adds themselves.
--
-- SECURITY: there is deliberately NO column for a full card number, CVV, PIN
-- or bank account number, and none may ever be added. The app derives the
-- brand and the last four digits on the device and sends only those; the PAN
-- never leaves the phone and never reaches this database. `last4` is CHECKed
-- to be exactly four digits so a full number cannot be smuggled into it.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payment_methods (
  id           uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL,
  kind         text NOT NULL,
  label        text NOT NULL DEFAULT '',
  brand        text,
  last4        text NOT NULL,
  exp_month    smallint,
  exp_year     smallint,
  holder_name  text,
  bank_name    text,
  is_default   boolean NOT NULL DEFAULT false,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT payment_methods_pk PRIMARY KEY (id),
  CONSTRAINT payment_methods_user_fk FOREIGN KEY (user_id)
    REFERENCES auth.users (id) ON DELETE CASCADE,
  CONSTRAINT payment_methods_kind_check CHECK (kind IN ('card', 'bank', 'mfs')),
  CONSTRAINT payment_methods_last4_check CHECK (last4 ~ '^[0-9]{4}$'),
  CONSTRAINT payment_methods_exp_month_check
    CHECK (exp_month IS NULL OR exp_month BETWEEN 1 AND 12),
  CONSTRAINT payment_methods_exp_year_check
    CHECK (exp_year IS NULL OR exp_year BETWEEN 2000 AND 2100),
  -- The same card cannot be added twice.
  CONSTRAINT payment_methods_unique_per_user
    UNIQUE (user_id, kind, brand, last4, exp_month, exp_year)
);

-- At most one default per person.
CREATE UNIQUE INDEX IF NOT EXISTS payment_methods_one_default
  ON public.payment_methods (user_id) WHERE is_default;

CREATE INDEX IF NOT EXISTS payment_methods_user_idx
  ON public.payment_methods (user_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 4. TRANSACTIONS — the double-entry ledger.
-- One transfer = two rows sharing `reference`: a debit on the sender's ledger
-- and a credit on the recipient's. Each row keeps the balance either side of
-- itself, so a statement can be rebuilt and checked without replaying sums.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.transactions (
  id                 uuid NOT NULL DEFAULT gen_random_uuid(),
  reference          uuid NOT NULL,
  user_id            uuid NOT NULL,
  direction          text NOT NULL,
  purpose            text NOT NULL DEFAULT 'transfer',
  amount             numeric(14, 2) NOT NULL,
  balance_before     numeric(14, 2) NOT NULL,
  balance_after      numeric(14, 2) NOT NULL,
  currency           text NOT NULL DEFAULT 'BDT',
  counterparty_id    uuid,
  counterparty_name  text NOT NULL DEFAULT '',
  counterparty_phone text,
  description        text NOT NULL DEFAULT '',
  status             text NOT NULL DEFAULT 'completed',
  payment_method_id  uuid,
  idempotency_key    text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT transactions_pk PRIMARY KEY (id),
  CONSTRAINT transactions_user_fk FOREIGN KEY (user_id)
    REFERENCES auth.users (id) ON DELETE CASCADE,
  CONSTRAINT transactions_counterparty_fk FOREIGN KEY (counterparty_id)
    REFERENCES auth.users (id) ON DELETE SET NULL,
  CONSTRAINT transactions_payment_method_fk FOREIGN KEY (payment_method_id)
    REFERENCES public.payment_methods (id) ON DELETE SET NULL,
  CONSTRAINT transactions_direction_check CHECK (direction IN ('debit', 'credit')),
  CONSTRAINT transactions_purpose_check
    CHECK (purpose IN ('transfer', 'deposit', 'withdrawal')),
  CONSTRAINT transactions_status_check
    CHECK (status IN ('pending', 'completed', 'failed')),
  CONSTRAINT transactions_amount_positive CHECK (amount > 0),
  -- A leg is unique per (transfer, person, side), so a replay cannot double it.
  CONSTRAINT transactions_leg_uk UNIQUE (reference, user_id, direction)
);

CREATE INDEX IF NOT EXISTS transactions_user_created_idx
  ON public.transactions (user_id, created_at DESC);

-- A retried transfer with the same key is rejected rather than repeated.
CREATE UNIQUE INDEX IF NOT EXISTS transactions_idempotency_uk
  ON public.transactions (user_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 5. A NEW ACCOUNT GETS A PROFILE AND AN EMPTY WALLET
-- Not seed data: an identity row and a zero balance, nothing to spend.
-- ---------------------------------------------------------------------------
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

  INSERT INTO public.wallets (user_id, balance)
  VALUES (NEW.id, 0)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Opens the caller's wallet if they signed up before this migration. Returns
-- the balance. Creating an empty wallet is not a balance change.
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

  INSERT INTO public.wallets (user_id, balance) VALUES (caller, 0)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT balance INTO current FROM public.wallets WHERE user_id = caller;
  RETURN current;
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. THE TRANSFER
-- Everything that moves money happens here, under SECURITY DEFINER, so no
-- client role needs UPDATE on a balance or INSERT on the ledger.
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
AS $$
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

  -- Rounded to paisa first, so 10.999 cannot debit 10.99 and credit 11.00.
  v_amount := round(p_amount, 2);
  IF v_amount IS NULL OR v_amount <= 0 THEN
    RAISE EXCEPTION 'Enter an amount greater than zero'
      USING ERRCODE = '22023';
  END IF;

  -- A repeat of a request already carried out returns the first result
  -- instead of sending the money a second time.
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
  SELECT user_id, full_name INTO v_recipient, v_recip_name
  FROM public.profiles WHERE phone = v_phone;

  IF v_recipient IS NULL THEN
    RAISE EXCEPTION 'No Probashi Guard account uses that number'
      USING ERRCODE = 'P0002';
  END IF;
  IF v_recipient = caller THEN
    RAISE EXCEPTION 'You cannot send money to yourself'
      USING ERRCODE = '22023';
  END IF;

  -- Both wallets exist before they are locked.
  INSERT INTO public.wallets (user_id, balance) VALUES (caller, 0)
  ON CONFLICT (user_id) DO NOTHING;
  INSERT INTO public.wallets (user_id, balance) VALUES (v_recipient, 0)
  ON CONFLICT (user_id) DO NOTHING;

  -- Locked in a fixed order, so A->B and B->A at the same instant queue
  -- rather than deadlock. This is the lock the reference backend lacks.
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
$$;

-- Claims a phone number for the caller's profile. Unique, so the number can
-- address exactly one account.
CREATE OR REPLACE FUNCTION public.set_my_phone(p_phone text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller uuid := auth.uid();
  v_phone text;
BEGIN
  IF caller IS NULL THEN
    RAISE EXCEPTION 'Sign in first' USING ERRCODE = '42501';
  END IF;

  v_phone := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g');
  IF v_phone !~ '^\+?[0-9]{6,15}$' THEN
    RAISE EXCEPTION 'That phone number does not look right'
      USING ERRCODE = '22023';
  END IF;

  IF EXISTS (SELECT 1 FROM public.profiles
             WHERE phone = v_phone AND user_id <> caller) THEN
    RAISE EXCEPTION 'Another account already uses that number'
      USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.profiles (user_id, phone)
  VALUES (caller, v_phone)
  ON CONFLICT (user_id) DO UPDATE SET phone = EXCLUDED.phone, updated_at = now();

  RETURN v_phone;
END;
$$;

-- Looks up who a phone number belongs to, for the confirmation step before a
-- transfer. Returns the name only — never an id, an email or a balance — so
-- it cannot be used to harvest accounts.
CREATE OR REPLACE FUNCTION public.lookup_recipient(p_phone text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
  WHERE phone = v_phone AND user_id <> caller;

  IF v_name IS NULL THEN
    RETURN jsonb_build_object('found', false);
  END IF;
  RETURN jsonb_build_object('found', true, 'full_name', v_name);
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. ROW LEVEL SECURITY
-- Read your own rows. Manage your own cards. Never write a balance or a
-- ledger row directly — only the functions above do that.
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallets         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_methods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions    ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read their own profile" ON public.profiles;
CREATE POLICY "Users read their own profile"
  ON public.profiles FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

-- Name and avatar only. `phone` is not in this grant, so it can be changed
-- only through set_my_phone(), which enforces uniqueness.
DROP POLICY IF EXISTS "Users update their own profile" ON public.profiles;
CREATE POLICY "Users update their own profile"
  ON public.profiles FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users read their own wallet" ON public.wallets;
CREATE POLICY "Users read their own wallet"
  ON public.wallets FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users manage their own payment methods" ON public.payment_methods;
CREATE POLICY "Users manage their own payment methods"
  ON public.payment_methods FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users read their own transactions" ON public.transactions;
CREATE POLICY "Users read their own transactions"
  ON public.transactions FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

-- No INSERT / UPDATE / DELETE policy on wallets or transactions, and the
-- table grants are withdrawn as well: with RLS on, a missing policy already
-- blocks the write, and removing the grant means a future policy cannot
-- silently re-open it.
REVOKE ALL ON public.wallets FROM anon, authenticated;
REVOKE ALL ON public.transactions FROM anon, authenticated;
GRANT SELECT ON public.wallets TO authenticated;
GRANT SELECT ON public.transactions TO authenticated;

-- REVOKE ALL first, not REVOKE INSERT/DELETE: a column-level GRANT UPDATE is
-- ADDED to any table-level UPDATE the role already holds, it does not replace
-- it. Narrowing the grant therefore has to start from nothing, or
-- `profiles.phone` stays writable and set_my_phone()'s uniqueness and format
-- checks can be stepped around with a direct UPDATE.
REVOKE ALL ON public.profiles FROM anon, authenticated;
GRANT SELECT ON public.profiles TO authenticated;
GRANT UPDATE (full_name, avatar_url) ON public.profiles TO authenticated;

-- Cards belong to the signed-in person; the anonymous role has no business
-- with them at all.
REVOKE ALL ON public.payment_methods FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payment_methods TO authenticated;

-- ---------------------------------------------------------------------------
-- 8. FUNCTION GRANTS
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.p2p_transfer(text, numeric, text, text) FROM public, anon;
REVOKE ALL ON FUNCTION public.ensure_my_wallet() FROM public, anon;
REVOKE ALL ON FUNCTION public.set_my_phone(text) FROM public, anon;
REVOKE ALL ON FUNCTION public.lookup_recipient(text) FROM public, anon;

GRANT EXECUTE ON FUNCTION public.p2p_transfer(text, numeric, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_my_wallet() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_my_phone(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.lookup_recipient(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 9. BACKFILL profiles / wallets for accounts that already exist.
-- A row per existing user with a zero balance; no money, no cards, no history.
-- ---------------------------------------------------------------------------
INSERT INTO public.profiles (user_id, full_name, phone)
SELECT u.id,
       COALESCE(u.raw_user_meta_data ->> 'full_name',
                u.raw_user_meta_data ->> 'name', ''),
       NULLIF(u.phone, '')
FROM auth.users u
WHERE NOT u.is_anonymous
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO public.wallets (user_id, balance)
SELECT u.id, 0 FROM auth.users u
WHERE NOT u.is_anonymous
ON CONFLICT (user_id) DO NOTHING;
