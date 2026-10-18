-- Migration: 20261018130000_harden_rls_security.sql
-- Description: Revoke insecure development policies on wallets and beneficiaries,
-- and enforce strict Row Level Security (RLS) scoping.

-- 1. DROP INSECURE DEV & PERMISSIVE POLICIES
DROP POLICY IF EXISTS "Allow public read and update on wallets" ON public.wallets;
DROP POLICY IF EXISTS "Public read/write wallets during dev" ON public.wallets;
DROP POLICY IF EXISTS "Users can access their own wallet" ON public.wallets;

DROP POLICY IF EXISTS "Allow public read and insert on beneficiaries" ON public.beneficiaries;
DROP POLICY IF EXISTS "Public read/write beneficiaries during dev" ON public.beneficiaries;
DROP POLICY IF EXISTS "Users can access their own beneficiaries" ON public.beneficiaries;

-- 2. HARDEN WALLETS RLS
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;

-- Authenticated users can ONLY view their own wallet
CREATE POLICY "Users view their own wallet"
  ON public.wallets
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- Restrict direct client updates to balance_bdt (must go through service_role)
REVOKE UPDATE (balance_bdt) ON public.wallets FROM anon, authenticated;

-- 3. HARDEN BENEFICIARIES RLS
ALTER TABLE public.beneficiaries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage their own beneficiaries"
  ON public.beneficiaries
  FOR ALL
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- 4. HARDEN TRANSACTIONS RLS
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read their own transactions" ON public.transactions;
DROP POLICY IF EXISTS "Users insert their own transactions" ON public.transactions;

CREATE POLICY "Users read their own transactions"
  ON public.transactions
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() = sender_id OR 
    auth.uid() = receiver_id
  );

CREATE POLICY "Users create their own transactions"
  ON public.transactions
  FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = sender_id AND
    status = 'pending'
  );

-- 5. HARDEN SAVED_DOCUMENTS RLS
ALTER TABLE public.saved_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read their own saved documents" ON public.saved_documents;
CREATE POLICY "Users read their own saved documents"
  ON public.saved_documents
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- Disallow direct client inserts/updates/deletes on saved_documents
REVOKE INSERT, UPDATE, DELETE ON public.saved_documents FROM anon, authenticated;
