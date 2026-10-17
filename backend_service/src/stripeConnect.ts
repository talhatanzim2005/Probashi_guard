import stripeClient from './stripeClient.js';

/**
 * Helpers for safely routing Connect destination charges.
 *
 * Stripe rejects `payment_intent_data.transfer_data` / `application_fee_amount`
 * at payment-confirmation time (on the hosted Checkout page, *after* the session
 * was created successfully) in two cases:
 *
 *   1. The destination is the platform's own account
 *      -> "The 'transfer_data[destination]' param cannot be set to your own account."
 *   2. The destination is a connected account that has not finished onboarding
 *      -> code `insufficient_capabilities_for_transfer`
 *
 * So a destination account must be verified before it is attached to a session.
 * When it cannot be used we fall back to a plain platform charge instead of
 * handing the customer a checkout page that fails on submit.
 */

const CAPABILITY_CACHE_TTL_MS = 5 * 60 * 1000;

let platformAccountIdPromise: Promise<string | null> | null = null;
const destinationCache = new Map<string, { usable: boolean; reason: string; checkedAt: number }>();

/** The account the API key belongs to. Cached for the process lifetime. */
export async function getPlatformAccountId(): Promise<string | null> {
  if (!platformAccountIdPromise) {
    // A no-argument retrieve maps to GET /v1/account (the key's own account);
    // the cast is needed because the typings only describe the by-id form.
    platformAccountIdPromise = (stripeClient.accounts as any)
      .retrieve()
      .then((account: any) => account.id || null)
      .catch((err: any) => {
        console.warn('[Connect] Could not resolve platform account id:', err.message);
        platformAccountIdPromise = null; // allow a later retry
        return null;
      });
  }
  return platformAccountIdPromise;
}

/** True when the account holds a capability that can receive a destination transfer. */
function hasTransferCapability(account: any): boolean {
  const capabilities = account?.capabilities || {};
  if (
    capabilities.transfers === 'active' ||
    capabilities.crypto_transfers === 'active' ||
    capabilities.legacy_payments === 'active'
  ) {
    return true;
  }

  // Accounts created through the /v2/core/accounts API expose the equivalent
  // capability under configuration.recipient.
  const v2Status =
    account?.configuration?.recipient?.capabilities?.stripe_balance?.stripe_transfers?.status;
  return v2Status === 'active';
}

/**
 * Resolve the destination account for a destination charge.
 *
 * Preference order: the account supplied by the caller, then STRIPE_TEST_ACCOUNT_ID.
 * Returns `accountId: null` when no candidate can legally receive a transfer, in
 * which case the caller must omit `payment_intent_data` entirely.
 */
export async function resolveDestinationAccount(
  requestedAccountId?: string | null
): Promise<{ accountId: string | null; reason: string }> {
  const candidates = [requestedAccountId, process.env.STRIPE_TEST_ACCOUNT_ID]
    .map((value) => (typeof value === 'string' ? value.trim() : ''))
    .filter((value) => value.length > 0);

  if (candidates.length === 0) {
    return { accountId: null, reason: 'no connected account supplied' };
  }

  const platformAccountId = await getPlatformAccountId();
  const rejections: string[] = [];

  for (const candidate of candidates) {
    if (!candidate.startsWith('acct_')) {
      rejections.push(`"${candidate}" is not a Stripe account id`);
      continue;
    }

    // Stripe refuses a transfer to the account that is making the charge.
    if (platformAccountId && candidate === platformAccountId) {
      rejections.push(`${candidate} is the platform's own account`);
      continue;
    }

    const cached = destinationCache.get(candidate);
    if (cached && Date.now() - cached.checkedAt < CAPABILITY_CACHE_TTL_MS) {
      if (cached.usable) {
        return { accountId: candidate, reason: cached.reason };
      }
      rejections.push(cached.reason);
      continue;
    }

    try {
      const account: any = await stripeClient.accounts.retrieve(candidate);
      const usable = hasTransferCapability(account);
      const reason = usable
        ? 'verified transfer capability'
        : `${candidate} has not completed onboarding (no active transfers capability)`;
      destinationCache.set(candidate, { usable, reason, checkedAt: Date.now() });

      if (usable) {
        return { accountId: candidate, reason };
      }
      rejections.push(reason);
    } catch (err: any) {
      // An unretrievable account (wrong mode, deleted, typo) must not be attached.
      const reason = `${candidate} could not be retrieved: ${err.message}`;
      rejections.push(reason);
      destinationCache.set(candidate, { usable: false, reason, checkedAt: Date.now() });
    }
  }

  return { accountId: null, reason: rejections.join('; ') || 'no connected account supplied' };
}

/**
 * Build `payment_intent_data` for a Checkout Session, or `undefined` when the
 * charge has to stay on the platform account.
 */
export async function buildDestinationChargeData(
  requestedAccountId: string | null | undefined,
  applicationFeeAmount: number
): Promise<{
  paymentIntentData:
    | { application_fee_amount?: number; transfer_data: { destination: string } }
    | undefined;
  destinationAccountId: string | null;
  reason: string;
}> {
  const { accountId, reason } = await resolveDestinationAccount(requestedAccountId);

  if (!accountId) {
    console.warn(`[Connect] Charging the platform account directly — ${reason}`);
    return { paymentIntentData: undefined, destinationAccountId: null, reason };
  }

  const fee = Number.isFinite(applicationFeeAmount) ? Math.max(0, Math.round(applicationFeeAmount)) : 0;
  return {
    paymentIntentData: {
      // An application fee of 0 is rejected, so only send a positive fee.
      ...(fee > 0 ? { application_fee_amount: fee } : {}),
      transfer_data: { destination: accountId },
    },
    destinationAccountId: accountId,
    reason,
  };
}
