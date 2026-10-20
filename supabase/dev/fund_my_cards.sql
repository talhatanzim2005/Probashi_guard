-- Dev only: NOT a migration. Do not move into supabase/migrations/.
-- Name in the Supabase SQL editor: "Dev - Fund my cards"
--
-- Gives ONE real account a starting balance on each of its three cards, so the
-- app's wallet cards read like a funded wallet:
--
--     card_wps       WPS Payroll Card              50,000.00
--     card_probashi  Probashi Expatriate Account   25,000.00
--     card_visa      Probashi Global Visa          10,000.00
--
-- The app shows what the ledger holds (the `wallets` table); it cannot, and
-- should not, invent a balance on screen. So the numbers appear in the app only
-- once they are really in the ledger, which is what this does. It uses
-- deposit_to_wallet(), the same function production uses, so every credit gets
-- a transactions row with balance_before / balance_after.
--
-- BEFORE YOU RUN IT
--   1. Run 20261020100000_sub_wallets.sql first (it creates the three wallets
--      per account and the card-aware deposit_to_wallet).
--   2. Put the email you sign in to the app with in v_email below.
--   3. Run the whole file once. Running it again is safe: each deposit has a
--      fixed idempotency key, so the money is credited a single time.
--      (To top up later, change the 'v1' in the keys to 'v2'.)
--
-- Never run this against a project holding real customers.

DO $fund$
DECLARE
  -- ===== EDIT THIS ==========================================================
  v_email   text := 'you@example.com';
  -- ==========================================================================
  v_user_id uuid;
BEGIN
  SELECT id INTO v_user_id FROM auth.users WHERE lower(email) = lower(v_email);
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No auth user with email %. Use the email you sign in with.', v_email;
  END IF;

  PERFORM public.deposit_to_wallet(
    v_user_id, 50000, 'dev-fund-my-cards-v1-card_wps-' || v_user_id::text,
    'Dev seed: WPS Payroll Card', 'card_wps');
  PERFORM public.deposit_to_wallet(
    v_user_id, 25000, 'dev-fund-my-cards-v1-card_probashi-' || v_user_id::text,
    'Dev seed: Probashi Expatriate Account', 'card_probashi');
  PERFORM public.deposit_to_wallet(
    v_user_id, 10000, 'dev-fund-my-cards-v1-card_visa-' || v_user_id::text,
    'Dev seed: Probashi Global Visa', 'card_visa');

  RAISE NOTICE 'Funded the three cards of % (50000 / 25000 / 10000).', v_email;
END
$fund$;

-- Check the result: three rows, 50000.00 / 25000.00 / 10000.00 (edit the email).
SELECT u.email, w.card_id, w.balance
FROM auth.users u
JOIN public.wallets w ON w.user_id = u.id
WHERE lower(u.email) = lower('you@example.com')
ORDER BY w.card_id;
