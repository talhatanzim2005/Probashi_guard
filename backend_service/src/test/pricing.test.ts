import test from 'node:test';
import assert from 'node:assert/strict';
import {
  CARD_IDS,
  SETTLEMENT_CURRENCY,
  USD_TO_BDT,
  VAT_ON_COMMISSION_RATE,
  isCardId,
  toUsdCents,
  usdCentsForBdt,
} from '../pricing.js';

// The server prices a Checkout session from these functions and the webhook
// re-derives the same price to prove the session was not altered, so they are
// the one place where "what was charged" and "what is credited" must agree.

test('PRICE-01 the settlement rail is USD at the documented fixed rate and VAT', () => {
  assert.equal(SETTLEMENT_CURRENCY, 'usd');
  assert.equal(USD_TO_BDT, 119.5);
  assert.equal(VAT_ON_COMMISSION_RATE, 0.0001);
});

test('PRICE-02 toUsdCents rounds to whole cents', () => {
  assert.equal(toUsdCents(10), 1000);
  assert.equal(toUsdCents(10.004), 1000);
  assert.equal(toUsdCents(10.005), 1001);
  assert.equal(toUsdCents(26.659), 2666);
});

test('PRICE-03 toUsdCents never goes below Stripe\'s 50 cent minimum', () => {
  assert.equal(toUsdCents(0.5), 50);
  assert.equal(toUsdCents(0.1), 50);
  assert.equal(toUsdCents(0), 50);
  // A negative amount is also lifted to the floor, which is why the route must
  // validate the amount before it prices anything (see PAY-S11).
  assert.equal(toUsdCents(-25), 50);
});

test('PRICE-04 usdCentsForBdt adds VAT on commission, then converts at 119.5', () => {
  // 11,950 BDT + 0.01% VAT = 11,951.195 BDT = 100.01 USD.
  assert.equal(usdCentsForBdt(11_950), 10_001);
  assert.equal(usdCentsForBdt(3_185), 2_666);
  assert.equal(usdCentsForBdt(119.5), 100);
});

test('PRICE-05 anything under about 59.75 BDT is charged the 50 cent floor', () => {
  assert.equal(usdCentsForBdt(59.75), 50);
  assert.equal(usdCentsForBdt(10), 50);
  assert.equal(usdCentsForBdt(1), 50);
  // 59.75 BDT is the 50 cents expressed in taka: a 10 BDT send therefore costs
  // 59.75 BDT (finding SEC-13).
  assert.equal(usdCentsForBdt(60), 50);
  assert.equal(usdCentsForBdt(120), 100);
});

test('PRICE-06 a non-finite amount prices to NaN, which the webhook treats as "do not credit"', () => {
  // webhooks.ts refuses a session when !Number.isFinite(expectedCents).
  assert.ok(Number.isNaN(usdCentsForBdt(Number.NaN)));
  assert.ok(Number.isNaN(usdCentsForBdt(Number('abc'))));
  assert.ok(Number.isNaN(usdCentsForBdt(Number(undefined))));
});

test('PRICE-07 the charge and the credit agree to within a cent for every amount', () => {
  // The webhook credits cents / 100 * 119.5. Compare that with what the sender
  // asked for plus VAT: the gap is rounding to a whole cent, so at most half a
  // cent, which is 0.5975 BDT.
  const halfCentInBdt = (0.5 * USD_TO_BDT) / 100;
  let seed = 12345;
  const next = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
  for (let i = 0; i < 2_000; i++) {
    const bdt = Math.round((60 + next() * 2_000_000) * 100) / 100;
    const credited = (usdCentsForBdt(bdt) / 100) * USD_TO_BDT;
    const asked = bdt * (1 + VAT_ON_COMMISSION_RATE);
    assert.ok(
      Math.abs(credited - asked) <= halfCentInBdt + 1e-6,
      `${bdt} BDT: asked ${asked.toFixed(4)}, credited ${credited.toFixed(4)}`,
    );
  }
});

test('PRICE-08 a larger send never costs less than a smaller one', () => {
  let previous = 0;
  for (let bdt = 1; bdt <= 5_000; bdt += 7) {
    const cents = usdCentsForBdt(bdt);
    assert.ok(cents >= previous, `${bdt} BDT priced below the previous step`);
    previous = cents;
  }
});

test('PRICE-09 only the three known card ids are accepted', () => {
  assert.deepEqual([...CARD_IDS], ['card_wps', 'card_probashi', 'card_visa']);
  for (const id of CARD_IDS) assert.ok(isCardId(id));
  for (const bad of ['', 'card_wps ', 'CARD_WPS', 'card_unknown', 'wps', null, undefined, 42, {}, ['card_wps']]) {
    assert.ok(!isCardId(bad), `${JSON.stringify(bad)} must not be a card id`);
  }
});
