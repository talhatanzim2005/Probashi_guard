-- Dev only: NOT a migration. Do not move into supabase/migrations/.
-- Name in the Supabase SQL editor: "Dev - Fund test users"
--
-- Gives two REAL accounts a verified phone and a starting balance, using the
-- same functions production uses (bind_verified_phone, deposit_to_wallet), so
-- the ledger, balance_before/after and idempotency all behave like the app.
--
-- BEFORE YOU RUN IT
--   1. Create both users: Supabase Dashboard > Authentication > Users >
--      Add user > "Create new user" (tick Auto Confirm User). Or sign up in the
--      app. The emails must exist or this script stops with a clear error.
--   2. Edit the four values in the DECLARE block below.
--   3. Run the whole file once. Running it again is safe: the deposit uses a
--      fixed idempotency key, so the money is credited a single time.
--
-- WHAT IT SKIPS: the real SMS check. bind_verified_phone() marks the number as
-- verified without sending a code, which is exactly why it is service-role
-- only. Never run this against a project holding real customers.

DO $seed$
DECLARE
  -- ===== EDIT THESE =========================================================
  v_sender_email    text    := 'sender@example.com';
  v_sender_phone    text    := '+966500000001';   -- the worker abroad
  v_receiver_email  text    := 'receiver@example.com';
  v_receiver_phone  text    := '+8801700000001';  -- the family member in BD
  v_amount_bdt      numeric := 50000;             -- credited to the SENDER only
  -- ==========================================================================
  v_sender_id   uuid;
  v_receiver_id uuid;
BEGIN
  SELECT id INTO v_sender_id   FROM auth.users WHERE lower(email) = lower(v_sender_email);
  SELECT id INTO v_receiver_id FROM auth.users WHERE lower(email) = lower(v_receiver_email);

  IF v_sender_id IS NULL THEN
    RAISE EXCEPTION 'No auth user with email %. Create it under Authentication > Users first.', v_sender_email;
  END IF;
  IF v_receiver_id IS NULL THEN
    RAISE EXCEPTION 'No auth user with email %. Create it under Authentication > Users first.', v_receiver_email;
  END IF;
  IF v_sender_id = v_receiver_id THEN
    RAISE EXCEPTION 'Sender and receiver must be two different accounts.';
  END IF;

  -- Verified phone + a zero-balance wallet for each (a deposit and a transfer
  -- both refuse an account without one).
  PERFORM public.bind_verified_phone(v_sender_id,   v_sender_phone);
  PERFORM public.bind_verified_phone(v_receiver_id, v_receiver_phone);

  -- The only legal way for a balance to go up. Fixed key => credited once.
  PERFORM public.deposit_to_wallet(
    v_sender_id,
    v_amount_bdt,
    'dev-seed-test-funds-v1-' || v_sender_id::text,
    'Dev seed: test funds'
  );

  RAISE NOTICE 'Funded % (%), receiver % (%) is verified at zero.',
    v_sender_email, v_sender_phone, v_receiver_email, v_receiver_phone;
END
$seed$;

-- Check the result: the sender's card_wps shows the amount (the other two cards
-- 0.00), the receiver is all zeros, both with a verified_at timestamp.
SELECT u.email, p.phone, p.phone_verified_at AS verified_at, w.card_id, w.balance
FROM auth.users u
JOIN public.profiles p ON p.user_id = u.id
JOIN public.wallets  w ON w.user_id = u.id
WHERE u.email IN ('sender@example.com', 'receiver@example.com')
ORDER BY u.email, w.card_id;
