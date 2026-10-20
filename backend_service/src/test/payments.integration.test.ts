import './helpers/hermeticEnv.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import app from '../server.js';
import stripeClient from '../stripeClient.js';
import { USD_TO_BDT, usdCentsForBdt } from '../pricing.js';
import { HERMETIC } from './helpers/hermeticEnv.js';
import { FakeSupabase, startApp } from './helpers/fakeServices.js';

/**
 * The money path of the API, driven through the real Express app. Supabase is a
 * fake HTTP server and Stripe's SDK methods are replaced in memory, so nothing
 * leaves this machine and nothing can be charged or credited for real.
 *
 *   POST /api/checkout/send-money            opens a Stripe Checkout session
 *   GET  /api/checkout/session-status/:id    polled by the app while the person pays
 *   POST /api/webhooks/stripe                books the paid session in the ledger
 *
 * Tests named `todo` document a defect that is still open: they assert the
 * behaviour the README promises, so they will flip to passing when it is fixed.
 */

const supabase = new FakeSupabase();
const alice = supabase.addAccount('alice', { verified: true });
const bob = supabase.addAccount('bob', { verified: false });
const guest = supabase.addAccount('guest', { anonymous: true });

let api: Awaited<ReturnType<typeof startApp>>;

// --- Stripe, in memory ------------------------------------------------------
const sessionsCreated: any[] = [];
const sessionStore = new Map<string, any>();
let v2Retrieves: string[] = [];
let stripeShouldFail = false;

const stripe = stripeClient as any;
stripe.checkout.sessions.create = async (params: any) => {
  if (stripeShouldFail) throw new Error('Invalid API Key provided: sk_test_***hermetic');
  sessionsCreated.push(params);
  const id = `cs_test_hermetic${String(sessionsCreated.length).padStart(4, '0')}`;
  return { id, url: `https://checkout.stripe.com/c/pay/${id}` };
};
stripe.checkout.sessions.retrieve = async (id: string) => {
  const found = sessionStore.get(id);
  if (!found) throw Object.assign(new Error(`No such checkout.session: '${id}'`), { statusCode: 404 });
  return found;
};
stripe.accounts.retrieve = async (id?: string) => {
  if (!id) return { id: 'acct_platform' };
  if (id === 'acct_connected_ok') return { id, capabilities: { transfers: 'active' } };
  if (id === 'acct_connected_pending') return { id, capabilities: { transfers: 'inactive' } };
  throw new Error(`No such account: '${id}'`);
};
stripe.v2.core.events.retrieve = async (id: string) => {
  v2Retrieves.push(id);
  throw new Error('stubbed: no such event');
};

test.before(async () => {
  await supabase.start();
  api = await startApp(app);
});
test.after(async () => {
  await api.close();
  await supabase.stop();
});
test.beforeEach(() => {
  supabase.reset();
  sessionsCreated.length = 0;
  v2Retrieves = [];
  stripeShouldFail = false;
  process.env.STRIPE_WEBHOOK_SECRET = HERMETIC.stripeWebhookSecret;
});

const post = (path: string, body: unknown, headers: Record<string, string> = {}) =>
  fetch(`${api.url}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });

// ===========================================================================
// POST /api/checkout/send-money
// ===========================================================================

const sendBody = (over: Record<string, unknown> = {}) => ({
  cardId: 'card_wps',
  recipientName: 'Rahim Uddin',
  recipientPhone: '+8801900000114',
  sourceAmount: 100,
  sourceCurrency: 'SAR',
  exchangeRate: 31.85,
  amountBdt: 3185,
  incentiveBdt: 79.625,
  ...over,
});

test('PAY-S01 a verified account gets a hosted Checkout session, priced in USD by the server', async () => {
  const res = await post('/api/checkout/send-money', sendBody(), alice.headers);
  assert.equal(res.status, 201);
  const body: any = await res.json();
  assert.equal(body.success, true);
  assert.match(body.checkoutUrl, /^https:\/\/checkout\.stripe\.com\//);
  assert.match(body.sessionId, /^cs_test_/);

  assert.equal(sessionsCreated.length, 1);
  const session = sessionsCreated[0];
  assert.equal(session.mode, 'payment');
  assert.equal(session.line_items[0].price_data.currency, 'usd');
  assert.equal(session.line_items[0].price_data.unit_amount, usdCentsForBdt(3185));
  assert.equal(session.line_items[0].price_data.unit_amount, 2666);
  assert.equal(session.success_url, 'http://localhost:3000/success?session_id={CHECKOUT_SESSION_ID}');
  assert.equal(session.cancel_url, 'http://localhost:3000/cancel');
  assert.equal(session.metadata.kind, 'remittance');
  assert.equal(session.metadata.cardId, 'card_wps');
  assert.equal(session.metadata.payerUserId, alice.id);
  assert.equal(session.metadata.amountBdt, '3185');
  assert.equal(session.metadata.usdToBdt, String(USD_TO_BDT));
});

test('PAY-S02 the client cannot pick the charge or the payer', async () => {
  const res = await post(
    '/api/checkout/send-money',
    sendBody({ usdAmount: 0.01, unitAmount: 1, destinationAmount: 1, payerUserId: bob.id, userId: bob.id }),
    alice.headers,
  );
  assert.equal(res.status, 201);
  const session = sessionsCreated[0];
  assert.equal(session.line_items[0].price_data.unit_amount, 2666, 'priced from amountBdt only');
  assert.equal(session.metadata.payerUserId, alice.id, 'the payer is the verified token, not the body');
});

test('PAY-S03 an account without a verified phone is refused BEFORE Stripe is called', async () => {
  const res = await post('/api/checkout/send-money', sendBody(), bob.headers);
  assert.equal(res.status, 403);
  const body: any = await res.json();
  assert.equal(body.code, 'phone_not_verified');
  assert.equal(body.checkoutUrl, undefined);
  assert.equal(sessionsCreated.length, 0);
});

test('PAY-S04 an anonymous session cannot start a payment', async () => {
  const res = await post('/api/checkout/send-money', sendBody(), guest.headers);
  assert.equal(res.status, 403);
  assert.equal(sessionsCreated.length, 0);
});

test('PAY-S05 no token at all: refused, and the database is not even asked', async () => {
  const res = await post('/api/checkout/send-money', sendBody());
  assert.equal(res.status, 403);
  assert.equal(supabase.calls('/rest/v1/profiles').length, 0);
  assert.equal(sessionsCreated.length, 0);
});

test('PAY-S06 if the database is down the charge is withheld (fail closed)', async () => {
  supabase.profilesDown = true;
  const res = await post('/api/checkout/send-money', sendBody(), alice.headers);
  assert.equal(res.status, 403);
  assert.equal(sessionsCreated.length, 0);
});

test('PAY-S07 an unknown source card is a 400 and nothing is charged', async () => {
  for (const cardId of ['card_gold', 'CARD_WPS', '', 'card_wps; drop table wallets']) {
    const res = await post('/api/checkout/send-money', sendBody({ cardId }), alice.headers);
    // An empty id falls through to the default card; the others are refused.
    if (cardId === '') {
      assert.equal(res.status, 201, 'empty cardId means the default card');
    } else {
      assert.equal(res.status, 400, cardId);
      assert.match(((await res.json()) as any).error, /Unknown source card/);
    }
  }
  assert.equal(sessionsCreated.length, 1, 'only the default-card request created a session');
  assert.equal(sessionsCreated[0].metadata.cardId, 'card_wps');
});

test('PAY-S08 sourceCardId is accepted as an alias for cardId', async () => {
  const res = await post('/api/checkout/send-money', sendBody({ cardId: undefined, sourceCardId: 'card_visa' }), alice.headers);
  assert.equal(res.status, 201);
  assert.equal(sessionsCreated[0].metadata.cardId, 'card_visa');
});

test('PAY-S09 a connected account that has not finished onboarding is not recorded', async () => {
  await post('/api/checkout/send-money', sendBody({ connectedAccountId: 'acct_connected_pending' }), alice.headers);
  await post('/api/checkout/send-money', sendBody({ connectedAccountId: 'acct_connected_ok' }), alice.headers);
  await post('/api/checkout/send-money', sendBody({ connectedAccountId: 'not-an-account' }), alice.headers);
  assert.equal(sessionsCreated[0].metadata.destinationAccount, '');
  assert.equal(sessionsCreated[1].metadata.destinationAccount, 'acct_connected_ok');
  assert.equal(sessionsCreated[2].metadata.destinationAccount, '');
});

test('PAY-S10 Stripe being down is a 500 with no session URL', async () => {
  stripeShouldFail = true;
  const res = await post('/api/checkout/send-money', sendBody(), alice.headers);
  assert.equal(res.status, 500);
  assert.equal(((await res.json()) as any).checkoutUrl, undefined);
});

test('PAY-S11 todo: the server rejects zero, negative and absurd amounts', { todo: 'SEC-13: amountBdt<=0 silently becomes a 100 BDT charge; there is no ceiling' }, async () => {
  for (const [label, over] of [
    ['zero', { amountBdt: 0, sourceAmount: 0 }],
    ['negative', { amountBdt: -500, sourceAmount: -500 }],
    ['absurd', { amountBdt: 1e12, sourceAmount: 1e12 }],
  ] as const) {
    const res = await post('/api/checkout/send-money', sendBody(over), alice.headers);
    assert.equal(res.status, 400, `${label} amount must be a 400`);
  }
  assert.equal(sessionsCreated.length, 0);
});

test('PAY-S12 todo: a send below the Stripe minimum is refused, not rounded up to 50 cents', { todo: 'SEC-13: 10 BDT is charged 0.50 USD (59.75 BDT) and 59.75 BDT is what the ledger books' }, async () => {
  const res = await post('/api/checkout/send-money', sendBody({ amountBdt: 10, sourceAmount: 10, sourceCurrency: 'BDT', exchangeRate: 1 }), alice.headers);
  assert.equal(res.status, 400);
});

test('PAY-S13 todo: a missing recipient phone is an error, not a silent +8801700000000', { todo: 'SEC-33: the same hard-coded fallback exists in checkout.ts, webhooks.ts and both Flutter repositories' }, async () => {
  const res = await post('/api/checkout/send-money', sendBody({ recipientPhone: undefined }), alice.headers);
  const used = sessionsCreated[0]?.metadata?.recipientPhone;
  assert.ok(res.status === 400 || used !== '+8801700000000', `recipientPhone defaulted to ${used}`);
});

test('PAY-S14 todo: a Stripe error message is not echoed to the client', { todo: 'SEC-18: error.message from Stripe is returned verbatim in 500 responses' }, async () => {
  stripeShouldFail = true;
  const res = await post('/api/checkout/send-money', sendBody(), alice.headers);
  const text = await res.text();
  assert.ok(!/sk_test|API Key/i.test(text), text);
});

// ===========================================================================
// GET /api/checkout/session-status/:id
// ===========================================================================

test('PAY-T01 the account that opened a session can ask whether it was paid', async () => {
  sessionStore.set('cs_test_status_paid_01', {
    id: 'cs_test_status_paid_01',
    status: 'complete',
    payment_status: 'paid',
    customer_details: { email: 'a@example.com' },
    metadata: { payerUserId: alice.id },
  });
  sessionStore.set('cs_test_status_open_01', {
    id: 'cs_test_status_open_01',
    status: 'open',
    payment_status: 'unpaid',
    metadata: { payerUserId: alice.id },
  });
  const paid: any = await (await fetch(`${api.url}/api/checkout/session-status/cs_test_status_paid_01`, { headers: alice.headers })).json();
  assert.equal(paid.is_paid, true);
  assert.equal(paid.payment_status, 'paid');
  const open: any = await (await fetch(`${api.url}/api/checkout/session-status/cs_test_status_open_01`, { headers: alice.headers })).json();
  assert.equal(open.is_paid, false);
  assert.equal(open.status, 'open');
});

test('PAY-T02 someone else\'s session answers 404, not its state', async () => {
  const res = await fetch(`${api.url}/api/checkout/session-status/cs_test_status_paid_01`, { headers: bob.headers });
  assert.equal(res.status, 404);
  assert.equal(((await res.json()) as any).payment_status, undefined);
});

test('PAY-T03 a malformed session id is a 400 and Stripe is not asked', async () => {
  for (const id of ['abc', 'cs_', 'cs_short', 'xs_test_aaaaaaaaaaaa', `cs_${'a'.repeat(300)}`]) {
    const res = await fetch(`${api.url}/api/checkout/session-status/${id}`, { headers: alice.headers });
    assert.equal(res.status, 400, id);
  }
});

test('PAY-T04 no token and anonymous tokens get 401', async () => {
  assert.equal((await fetch(`${api.url}/api/checkout/session-status/cs_test_status_paid_01`)).status, 401);
  assert.equal((await fetch(`${api.url}/api/checkout/session-status/cs_test_status_paid_01`, { headers: guest.headers })).status, 401);
});

test('PAY-T05 todo: an unknown session id looks the same as someone else\'s', { todo: 'SEC-18: unknown ids answer 500 with Stripe\'s message, foreign ids answer 404, so existence leaks' }, async () => {
  const res = await fetch(`${api.url}/api/checkout/session-status/cs_test_does_not_exist_01`, { headers: alice.headers });
  assert.equal(res.status, 404);
});

test('PAY-T06 todo: a session that is "complete" but still unpaid is not reported as paid', { todo: 'SEC-34: is_paid is true for status "complete" even when payment_status is "unpaid" (a delayed payment method); the app then shows success for money never received' }, async () => {
  sessionStore.set('cs_test_status_delayed_01', {
    id: 'cs_test_status_delayed_01',
    status: 'complete',
    payment_status: 'unpaid',
    metadata: { payerUserId: alice.id },
  });
  const body: any = await (await fetch(`${api.url}/api/checkout/session-status/cs_test_status_delayed_01`, { headers: alice.headers })).json();
  assert.equal(body.is_paid, false);
});

// ===========================================================================
// POST /api/webhooks/stripe
// ===========================================================================

const paidSession = (over: Record<string, unknown> = {}, metadata: Record<string, unknown> = {}) => ({
  id: 'cs_test_paid_0001',
  object: 'checkout.session',
  payment_status: 'paid',
  currency: 'usd',
  amount_total: usdCentsForBdt(11_950),
  metadata: {
    kind: 'remittance',
    cardId: 'card_wps',
    payerUserId: alice.id,
    amountBdt: '11950',
    sourceAmount: '100',
    sourceCurrency: 'SAR',
    recipientName: 'Rahim Uddin',
    recipientPhone: '+8801900000114',
    ...metadata,
  },
  ...over,
});
const completed = (session: unknown) => ({
  id: 'evt_hermetic_1',
  object: 'event',
  type: 'checkout.session.completed',
  data: { object: session },
});
function webhook(event: unknown, opts: { secret?: string; timestamp?: number; header?: string | null; mutate?: (s: string) => string } = {}) {
  const payload = JSON.stringify(event);
  const header =
    opts.header === undefined
      ? stripeClient.webhooks.generateTestHeaderString({
          payload,
          secret: opts.secret ?? HERMETIC.stripeWebhookSecret,
          timestamp: opts.timestamp,
        })
      : opts.header;
  return fetch(`${api.url}/api/webhooks/stripe`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(header ? { 'stripe-signature': header } : {}) },
    body: opts.mutate ? opts.mutate(payload) : payload,
  });
}

test('PAY-W01 a paid USD remittance is booked once, with the service-role key', async () => {
  const res = await webhook(completed(paidSession()));
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { received: true });

  const calls = supabase.calls('/rest/v1/rpc/settle_remittance');
  assert.equal(calls.length, 1);
  const rpc = calls[0].body;
  assert.equal(rpc.p_user_id, alice.id);
  assert.equal(rpc.p_card_id, 'card_wps');
  assert.equal(rpc.p_session_id, 'cs_test_paid_0001');
  assert.equal(rpc.p_recipient_name, 'Rahim Uddin');
  assert.equal(rpc.p_recipient_phone, '+8801900000114');
  assert.equal(calls[0].headers.apikey, HERMETIC.supabaseServiceKey);
  assert.equal(calls[0].headers.authorization, `Bearer ${HERMETIC.supabaseServiceKey}`);
});

test('PAY-W02 the credit is derived from the amount Stripe signed, at the server\'s rate', async () => {
  // metadata says 11,950 BDT; Stripe charged 10001 cents = 100.01 USD = 11,951.195 BDT.
  await webhook(completed(paidSession()));
  const credited = supabase.calls('/rest/v1/rpc/settle_remittance')[0].body.p_amount_bdt;
  assert.ok(Math.abs(credited - (10_001 / 100) * USD_TO_BDT) <= 0.011, `credited ${credited}`);
});

test('PAY-W03 a rate in the metadata cannot move the credit', async () => {
  await webhook(completed(paidSession({}, { usdToBdt: '1000', exchangeRate: '1000' })));
  const credited = supabase.calls('/rest/v1/rpc/settle_remittance')[0].body.p_amount_bdt;
  assert.ok(credited < 12_000, `credited ${credited}`);
});

test('PAY-W04 Stripe retrying the same event sends the same idempotency key every time', async () => {
  for (let i = 0; i < 3; i++) assert.equal((await webhook(completed(paidSession()))).status, 200);
  const calls = supabase.calls('/rest/v1/rpc/settle_remittance');
  assert.equal(calls.length, 3);
  assert.deepEqual(new Set(calls.map((c) => c.body.p_session_id)), new Set(['cs_test_paid_0001']));
  // The database turns repeats into a no-op: see DB-R02.
});

const NOT_CREDITED: Array<[string, Record<string, unknown>, Record<string, unknown>]> = [
  ['not yet paid', { payment_status: 'unpaid' }, {}],
  ['paid in a non-USD currency', { currency: 'bdt' }, {}],
  ['currency missing', { currency: undefined }, {}],
  ['not a remittance session', {}, { kind: 'subscription' }],
  ['no kind in the metadata', {}, { kind: undefined }],
  ['unknown card', {}, { cardId: 'card_unknown' }],
  ['no payer on the session', {}, { payerUserId: undefined }],
  ['zero total', { amount_total: 0 }, {}],
  ['negative total', { amount_total: -1000 }, {}],
  ['no total', { amount_total: undefined }, {}],
  ['total far below what the metadata claims', { amount_total: 100 }, {}],
  ['total far above what the metadata claims', { amount_total: 5_000_000 }, {}],
  ['metadata amount is not a number', {}, { amountBdt: 'lots' }],
  ['metadata amount missing', {}, { amountBdt: undefined }],
];
for (const [label, over, meta] of NOT_CREDITED) {
  test(`PAY-W05 nothing is credited when the session is ${label}`, async () => {
    const res = await webhook(completed(paidSession(over, meta)));
    assert.equal(res.status, 200, 'Stripe is still told the event was received');
    assert.equal(supabase.calls('/rest/v1/rpc/settle_remittance').length, 0);
  });
}

test('PAY-W06 a total within one cent of the metadata price is still accepted', async () => {
  await webhook(completed(paidSession({ amount_total: usdCentsForBdt(11_950) + 1 })));
  assert.equal(supabase.calls('/rest/v1/rpc/settle_remittance').length, 1);
  await webhook(completed(paidSession({ id: 'cs_test_paid_0002', amount_total: usdCentsForBdt(11_950) + 2 })));
  assert.equal(supabase.calls('/rest/v1/rpc/settle_remittance').length, 1, 'two cents off is refused');
});

test('PAY-W07 other event types are acknowledged and ignored', async () => {
  for (const type of ['payment_intent.succeeded', 'charge.refunded', 'customer.created', 'v2.core.account[requirements].updated']) {
    const res = await webhook({ id: 'evt_x', object: 'event', type, data: { object: {} } });
    assert.equal(res.status, 200, type);
  }
  assert.equal(supabase.calls('/rest/v1/rpc/settle_remittance').length, 0);
});

test('PAY-W08 a bad signature is a 400 and credits nothing', async () => {
  const event = completed(paidSession());
  assert.equal((await webhook(event, { header: null })).status, 400, 'no header');
  assert.equal((await webhook(event, { header: 't=1,v1=deadbeef' })).status, 400, 'garbage header');
  assert.equal((await webhook(event, { secret: 'whsec_somebody_elses' })).status, 400, 'wrong secret');
  assert.equal((await webhook(event, { mutate: (s) => s.replace('11950', '99999') })).status, 400, 'body edited after signing');
  assert.equal(
    (await webhook(event, { timestamp: Math.floor(Date.now() / 1000) - 3600 })).status,
    400,
    'a correctly signed event an hour old (replay)',
  );
  assert.equal(supabase.calls('/rest/v1/rpc/settle_remittance').length, 0);
});

test('PAY-W09 with no webhook secret configured the endpoint refuses everything', async () => {
  process.env.STRIPE_WEBHOOK_SECRET = '';
  const res = await webhook(completed(paidSession()));
  assert.equal(res.status, 500);
  assert.equal(supabase.calls('/rest/v1/rpc/settle_remittance').length, 0);
});

test('PAY-W10 todo: a failed booking is reported to Stripe so it retries', { todo: 'SEC-06: settle_remittance failures (and P0003) are logged but the webhook still answers 200' }, async () => {
  supabase.settleMode = 'fail';
  const res = await webhook(completed(paidSession()));
  assert.ok(res.status >= 500, `webhook answered ${res.status}; Stripe will never retry a 2xx`);
});

test('PAY-W11 todo: a forged signature never makes the server fetch an attacker-named event', { todo: 'SEC-07: stripeClient.ts polyfills parseThinEvent; it JSON.parses an unsigned body and the webhook retrieves that id from Stripe' }, async () => {
  const res = await webhook({ id: 'evt_attacker_chosen', type: 'checkout.session.completed' }, { header: 't=1,v1=deadbeef' });
  assert.equal(res.status, 400);
  assert.deepEqual(v2Retrieves, [], 'v2.core.events.retrieve was called with an id from an unsigned body');
});

test('PAY-W12 todo: a delayed payment that later succeeds is booked', { todo: 'SEC-34: checkout.session.async_payment_succeeded is not handled, so a session that completes unpaid and is paid later is never credited' }, async () => {
  const event = { id: 'evt_async_1', object: 'event', type: 'checkout.session.async_payment_succeeded', data: { object: paidSession({ id: 'cs_test_async_0001' }) } };
  assert.equal((await webhook(event)).status, 200);
  assert.equal(supabase.calls('/rest/v1/rpc/settle_remittance').length, 1);
});

// ===========================================================================
// Rate limit (last: it uses up this process's whole send-money allowance)
// ===========================================================================

test('PAY-S15 send-money answers 429 with Retry-After after 20 requests a minute', async () => {
  let blocked: Response | undefined;
  let accepted = 0;
  for (let i = 0; i < 40 && !blocked; i++) {
    const res = await post('/api/checkout/send-money', sendBody(), alice.headers);
    if (res.status === 429) blocked = res;
    else accepted++;
  }
  assert.ok(blocked, 'a 429 appeared within 40 requests');
  assert.ok(accepted <= 20, `${accepted} requests were accepted before the limit`);
  assert.ok(Number(blocked!.headers.get('retry-after')) >= 1);
  assert.equal((await fetch(`${api.url}/api/health`)).status, 200, 'other routes are unaffected');
});
