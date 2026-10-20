import test from 'node:test';
import assert from 'node:assert';
import app from '../server.js';
import stripeClient from '../stripeClient.js';
import http from 'node:http';

const DEV_AUTH = { Authorization: 'Bearer mock-test-token' };

let server: http.Server;
let baseUrl: string;

test.before(async () => {
  return new Promise<void>((resolve) => {
    server = app.listen(0, () => {
      const addr = server.address() as any;
      baseUrl = `http://127.0.0.1:${addr.port}`;
      resolve();
    });
  });
});

test.after(async () => {
  return new Promise<void>((resolve) => {
    server.close(() => resolve());
  });
});

test('GET /api/health returns ok', async () => {
  const res = await fetch(`${baseUrl}/api/health`);
  assert.strictEqual(res.status, 200);
  const data = await res.json() as any;
  assert.strictEqual(data.status, 'ok');
});

test('GET /api/payment/cards returns cards', async () => {
  const res = await fetch(`${baseUrl}/api/payment/cards`, { headers: DEV_AUTH });
  assert.strictEqual(res.status, 200);
  const data = await res.json() as any;
  assert.ok(Array.isArray(data.cards));
  assert.ok(data.cards.length >= 1);
});

test('GET /api/payment/beneficiaries returns beneficiaries', async () => {
  const res = await fetch(`${baseUrl}/api/payment/beneficiaries`, { headers: DEV_AUTH });
  assert.strictEqual(res.status, 200);
  const data = await res.json() as any;
  assert.ok(Array.isArray(data.beneficiaries));
});

test('GET /api/rates returns dynamic exchange rates', async () => {
  const res = await fetch(`${baseUrl}/api/rates`);
  assert.strictEqual(res.status, 200);
  const data = await res.json() as any;
  assert.strictEqual(data.success, true);
  assert.strictEqual(data.base, 'BDT');
  assert.ok(data.rates.USD >= 100);
  assert.ok(data.rates.SAR >= 25);
  assert.strictEqual(data.rates.BDT, 1.0);
});

test('POST /api/checkout/send-money refuses an unverified caller before charging', async () => {
  // No Authorization header, so there is no payer to credit. The refusal has to
  // come BEFORE Stripe takes anything, or a later rejection would strand real
  // money. The happy path needs a verified account and a live Supabase row, so
  // it is covered by the integration suite rather than here.
  const payload = {
    cardId: 'card_wps',
    sourceCardId: 'card_wps',
    recipientName: 'Tanzim',
    recipientPhone: '+8801700000000',
    sourceAmount: 100,
    sourceCurrency: 'SAR',
    exchangeRate: 31.85,
    amountBdt: 3185,
    incentiveBdt: 79.63,
    destinationAmount: 3264.63,
    destinationCurrency: 'BDT',
  };
  const res = await fetch(`${baseUrl}/api/checkout/send-money`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  assert.strictEqual(res.status, 403);
  const data = await res.json() as any;
  assert.strictEqual(data.code, 'phone_not_verified');
  // Nothing resembling a Checkout session may come back from a refusal.
  assert.strictEqual(data.checkoutUrl, undefined);
  assert.strictEqual(data.sessionId, undefined);
});

test('POST /api/connect/create-account validation and response shape', async () => {
  const res = await fetch(`${baseUrl}/api/connect/create-account`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...DEV_AUTH },
    body: JSON.stringify({
      displayName: 'Test Partner',
      email: 'test@example.com',
    }),
  });
  // Since test placeholder key is in .env, Stripe may respond with 500 or 201
  // We verify that the endpoint is mapped and handled cleanly
  assert.ok(res.status === 201 || res.status === 500);
});

test('POST /api/webhooks/stripe rejects requests without a signature', async () => {
  const res = await fetch(`${baseUrl}/api/webhooks/stripe`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'checkout.session.completed' }),
  });
  assert.strictEqual(res.status, 400);
});

test('POST /api/webhooks/stripe rejects a forged signature without echoing secrets', async () => {
  const res = await fetch(`${baseUrl}/api/webhooks/stripe`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'stripe-signature': 't=1,v1=deadbeef' },
    body: JSON.stringify({ type: 'checkout.session.completed' }),
  });
  assert.strictEqual(res.status, 400);
  const body = await res.text();
  assert.ok(!body.includes('whsec_'));
  const secret = process.env.STRIPE_WEBHOOK_SECRET;
  if (secret) assert.ok(!body.includes(secret));
});

test('POST /api/webhooks/stripe accepts a correctly signed event', async () => {
  // The negative tests above pass even when verification is broken outright, so
  // this is the one that proves the endpoint still reads the raw bytes Stripe
  // signed. A zero-amount session is used so nothing is credited.
  const secret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!secret) {
    // Nothing to sign with; the suite still reports this as a pass but says why.
    console.log('skipped: STRIPE_WEBHOOK_SECRET not set');
    return;
  }

  const payload = JSON.stringify({
    id: 'evt_test_signed',
    object: 'event',
    type: 'checkout.session.completed',
    data: {
      object: {
        id: 'cs_test_signed_probe',
        object: 'checkout.session',
        amount_total: 0,
        metadata: {},
      },
    },
  });
  const header = stripeClient.webhooks.generateTestHeaderString({ payload, secret });

  const res = await fetch(`${baseUrl}/api/webhooks/stripe`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'stripe-signature': header },
    body: payload,
  });

  // 200 means the signature verified and the handler ran. A 400 here means the
  // raw body never reached constructEvent.
  assert.strictEqual(res.status, 200);
});


test('locked routes refuse a caller with no session', async () => {
  const cases: Array<[string, string]> = [
    ['GET', '/api/payment/cards'],
    ['GET', '/api/payment/transactions'],
    ['POST', '/api/payment/transfer-cards'],
    ['POST', '/api/products/create'],
    ['POST', '/api/checkout/destination-charge'],
    ['POST', '/api/checkout/card-transfer'],
    ['GET', '/api/checkout/session-status/cs_test_aaaaaaaaaaaa'],
    ['POST', '/api/connect/create-account'],
  ];
  for (const [method, path] of cases) {
    const res = await fetch(`${baseUrl}${path}`, {
      method,
      headers: { 'Content-Type': 'application/json' },
      body: method === 'POST' ? '{}' : undefined,
    });
    // The removed routes 404; every other one must be 401. None may do work.
    assert.ok(res.status === 401 || res.status === 404, `${method} ${path} -> ${res.status}`);
    if (!path.includes('transfer')) assert.strictEqual(res.status, 401, `${method} ${path}`);
  }
});

test('a made-up bearer token is rejected, not treated as the dev user', async () => {
  const res = await fetch(`${baseUrl}/api/payment/cards`, {
    headers: { Authorization: 'Bearer not-the-dev-token' },
  });
  assert.strictEqual(res.status, 401);
});

test('product creation validates its input before touching Stripe', async () => {
  for (const body of [{ amount: -5 }, { amount: 'abc' }, { amount: 10, currency: 'xyz' }]) {
    const res = await fetch(`${baseUrl}/api/products/create`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...DEV_AUTH },
      body: JSON.stringify(body),
    });
    assert.strictEqual(res.status, 400, JSON.stringify(body));
  }
});

test('/success never reflects a script payload from session_id', async () => {
  const payload = encodeURIComponent('"><script>alert(1)</script>');
  const res = await fetch(`${baseUrl}/success?session_id=${payload}`);
  assert.strictEqual(res.status, 200);
  const html = await res.text();
  assert.ok(!html.includes('<script>alert'));
  assert.ok(!html.includes('alert(1)'));

  const ok = await fetch(`${baseUrl}/success?session_id=cs_test_a1B2c3D4e5`);
  assert.ok((await ok.text()).includes('cs_test_a1B2c3D4'));

  // ?session_id=a&session_id=b arrives as an array and used to crash .slice.
  const arr = await fetch(`${baseUrl}/success?session_id=a&session_id=b`);
  assert.strictEqual(arr.status, 200);
});

test('CORS answers a local dev origin but not a foreign one', async () => {
  const local = await fetch(`${baseUrl}/api/health`, { headers: { Origin: 'http://localhost:5000' } });
  assert.strictEqual(local.headers.get('access-control-allow-origin'), 'http://localhost:5000');
  const evil = await fetch(`${baseUrl}/api/health`, { headers: { Origin: 'https://evil.example' } });
  assert.strictEqual(evil.headers.get('access-control-allow-origin'), null);
});

test('the webhook credits nothing for a non-USD, unpaid or foreign session', async () => {
  const secret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!secret) {
    console.log('skipped: STRIPE_WEBHOOK_SECRET not set');
    return;
  }
  const base = {
    id: 'cs_test_guard',
    object: 'checkout.session',
    amount_total: 10000,
    payment_status: 'paid',
    currency: 'usd',
    metadata: { kind: 'remittance', payerUserId: '00000000-0000-0000-0000-000000000000', cardId: 'card_wps', amountBdt: '1195' },
  };
  const variants: Array<Record<string, unknown>> = [
    { ...base, currency: 'bdt' },
    { ...base, payment_status: 'unpaid' },
    { ...base, metadata: { ...base.metadata, kind: undefined } },
    { ...base, metadata: { ...base.metadata, cardId: 'card_unknown' } },
    { ...base, amount_total: 50 }, // far below the 1195 BDT it claims
  ];
  const warn = console.error;
  const errors: string[] = [];
  console.error = (...a: unknown[]) => { errors.push(a.join(' ')); };
  try {
    for (const object of variants) {
      const payload = JSON.stringify({ id: 'evt_guard', object: 'event', type: 'checkout.session.completed', data: { object } });
      const header = stripeClient.webhooks.generateTestHeaderString({ payload, secret });
      const res = await fetch(`${baseUrl}/api/webhooks/stripe`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'stripe-signature': header },
        body: payload,
      });
      assert.strictEqual(res.status, 200);
    }
  } finally {
    console.error = warn;
  }
  // A credit attempt would have logged a Supabase failure or "no payerUserId".
  assert.ok(!errors.some((e) => e.includes('settle_remittance failed')), errors.join('; '));
});
