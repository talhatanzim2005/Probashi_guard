/// Every transfer settles in USD; these convert the sender's BDT figures into
/// it. Shared by Checkout (which prices the session) and the webhook (which
/// re-derives the price to confirm the session was not altered).
export const SETTLEMENT_CURRENCY = 'usd';
export const USD_TO_BDT = 119.5;
export const VAT_ON_COMMISSION_RATE = 0.0001; // 0.01%

/// The card ids a wallet can belong to. One ledger wallet exists per card.
export const CARD_IDS = ['card_wps', 'card_probashi', 'card_visa'] as const;
export type CardId = (typeof CARD_IDS)[number];

export function isCardId(value: unknown): value is CardId {
  return typeof value === 'string' && (CARD_IDS as readonly string[]).includes(value);
}

/// Stripe rejects a USD charge under 50 cents, so that is the floor.
export function toUsdCents(amountUsd: number): number {
  return Math.max(50, Math.round(amountUsd * 100));
}

/// What a transfer of [amountBdt] costs in USD cents, VAT on commission included.
export function usdCentsForBdt(amountBdt: number): number {
  const vat = amountBdt * VAT_ON_COMMISSION_RATE;
  return toUsdCents((amountBdt + vat) / USD_TO_BDT);
}
