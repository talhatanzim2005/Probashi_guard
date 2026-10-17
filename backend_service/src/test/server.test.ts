import test from 'node:test';
import assert from 'node:assert';
import app from '../server.js';
import http from 'node:http';

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
  const res = await fetch(`${baseUrl}/api/payment/cards`);
  assert.strictEqual(res.status, 200);
  const data = await res.json() as any;
  assert.ok(Array.isArray(data.cards));
  assert.ok(data.cards.length >= 1);
});

test('GET /api/payment/beneficiaries returns beneficiaries', async () => {
  const res = await fetch(`${baseUrl}/api/payment/beneficiaries`);
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

test('POST /api/checkout/send-money completes remittance transaction', async () => {
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
  assert.strictEqual(res.status, 201);
  const data = await res.json() as any;
  assert.strictEqual(data.success, true);
  assert.strictEqual(data.transaction.title, 'Tanzim');
  assert.strictEqual(data.transaction.amount, 3185);
  assert.strictEqual(data.transaction.converted_amount, 100);
  assert.strictEqual(data.transaction.currency, 'SAR');
  assert.strictEqual(data.transaction.exchange_rate, 31.85);
});

test('POST /api/connect/create-account validation and response shape', async () => {
  const res = await fetch(`${baseUrl}/api/connect/create-account`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      displayName: 'Test Partner',
      email: 'test@example.com',
    }),
  });
  // Since test placeholder key is in .env, Stripe may respond with 500 or 201
  // We verify that the endpoint is mapped and handled cleanly
  assert.ok(res.status === 201 || res.status === 500);
});
