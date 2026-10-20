import './helpers/hermeticEnv.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import { SignJWT, exportJWK, generateKeyPair, type CryptoKey, type JWK } from 'jose';
import app from '../server.js';
import { HERMETIC } from './helpers/hermeticEnv.js';
import { FakeSupabase, startApp } from './helpers/fakeServices.js';

/**
 * POST /api/auth/bind-phone, end to end.
 *
 * Firebase signs the phone-proof ID token with Google's private key and
 * publishes the public half at a fixed JWKS URL. Here the test generates its own
 * key pair and answers that URL itself (by wrapping global fetch), so tokens of
 * every shape can be minted: valid, stale, wrongly signed, wrong audience...
 * Everything else the route calls is the in-process fake Supabase.
 *
 * Firebase's own behaviour for the console test numbers (+8801700000000 ..
 * +8801700000009, code 123456, no SMS) cannot be exercised without Firebase;
 * what is tested here is what the backend does with the token that results.
 */

const JWKS_URL_PREFIX = 'https://www.googleapis.com/service_accounts/v1/jwk/';
const KID = 'hermetic-key-1';
const PROJECT = HERMETIC.firebaseProjectId;

const supabase = new FakeSupabase();
const alice = supabase.addAccount('alice');
const guest = supabase.addAccount('guest', { anonymous: true });

let api: Awaited<ReturnType<typeof startApp>>;
let signingKey: CryptoKey;
let otherKey: CryptoKey;
let jwksFetches = 0;
const realFetch = globalThis.fetch;

test.before(async () => {
  const pair = await generateKeyPair('RS256');
  signingKey = pair.privateKey;
  otherKey = (await generateKeyPair('RS256')).privateKey;
  const publicJwk: JWK = { ...(await exportJWK(pair.publicKey)), kid: KID, alg: 'RS256', use: 'sig' };

  globalThis.fetch = (async (input: any, init?: any) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    if (url.startsWith(JWKS_URL_PREFIX)) {
      jwksFetches++;
      return new Response(JSON.stringify({ keys: [publicJwk] }), {
        status: 200,
        headers: { 'content-type': 'application/json', 'cache-control': 'max-age=3600' },
      });
    }
    return realFetch(input, init);
  }) as typeof fetch;

  await supabase.start();
  api = await startApp(app);
});
test.after(async () => {
  globalThis.fetch = realFetch;
  await api.close();
  await supabase.stop();
});
test.beforeEach(() => {
  supabase.reset();
  process.env.NODE_ENV = 'test';
  process.env.FIREBASE_PROJECT_ID = PROJECT;
  process.env.SUPABASE_SERVICE_ROLE_KEY = HERMETIC.supabaseServiceKey;
});

const nowSec = () => Math.floor(Date.now() / 1000);

type TokenOpts = {
  phone?: string | null;
  authAgoSeconds?: number | null;
  aud?: string;
  iss?: string;
  expiresInSeconds?: number;
  key?: CryptoKey;
};
async function firebaseToken(o: TokenOpts = {}) {
  const claims: Record<string, unknown> = {};
  if (o.phone !== null) claims.phone_number = o.phone ?? '+8801700000003';
  if (o.authAgoSeconds !== null) claims.auth_time = nowSec() - (o.authAgoSeconds ?? 5);
  return new SignJWT(claims)
    .setProtectedHeader({ alg: 'RS256', kid: KID })
    .setIssuer(o.iss ?? `https://securetoken.google.com/${PROJECT}`)
    .setAudience(o.aud ?? PROJECT)
    .setSubject('firebase-uid-123')
    .setIssuedAt(nowSec() - 60)
    .setExpirationTime(nowSec() + (o.expiresInSeconds ?? 3600))
    .sign(o.key ?? signingKey);
}

function bind(body: unknown, headers: Record<string, string> = alice.headers) {
  return fetch(`${api.url}/api/auth/bind-phone`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
}
const rpcCalls = () => supabase.calls('/rest/v1/rpc/bind_verified_phone');

test('PHONE-01 a valid proof for a Firebase test number binds it as SHARED to the caller', async () => {
  const res = await bind({ firebaseIdToken: await firebaseToken({ phone: '+8801700000003' }) });
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { verified: true });

  assert.equal(rpcCalls().length, 1);
  const call = rpcCalls()[0];
  assert.deepEqual(call.body, {
    p_user_id: alice.id,
    p_phone: '+8801700000003',
    p_shared: true,
    p_shared_cap: 50,
  });
  assert.equal(call.headers.apikey, HERMETIC.supabaseServiceKey, 'only the service role may bind');
});

test('PHONE-02 a real number is bound as exclusive to one account', async () => {
  await bind({ firebaseIdToken: await firebaseToken({ phone: '+8801900000114' }) });
  assert.equal(rpcCalls()[0].body.p_shared, false);
  assert.equal(rpcCalls()[0].body.p_phone, '+8801900000114');
});

test('PHONE-03 the number comes from the signed token, never from the request body', async () => {
  const res = await bind({
    firebaseIdToken: await firebaseToken({ phone: '+8801900000114' }),
    phone: '+8801999999999',
    phone_number: '+8801888888888',
    p_phone: '+8801777777777',
    userId: guest.id,
  });
  assert.equal(res.status, 200);
  assert.equal(rpcCalls()[0].body.p_phone, '+8801900000114');
  assert.equal(rpcCalls()[0].body.p_user_id, alice.id, 'and the account is the Supabase session, not the body');
});

test('PHONE-04 all ten documented test numbers are shared; the next number up is not', async () => {
  for (const phone of HERMETIC.testPhones) {
    supabase.reset();
    assert.equal((await bind({ firebaseIdToken: await firebaseToken({ phone }) })).status, 200, phone);
    assert.equal(rpcCalls()[0].body.p_shared, true, `${phone} should be shared`);
  }
  supabase.reset();
  await bind({ firebaseIdToken: await firebaseToken({ phone: '+8801700000010' }) });
  assert.equal(rpcCalls()[0].body.p_shared, false);
});

test('PHONE-05 in production the test numbers are ordinary numbers', async () => {
  process.env.NODE_ENV = 'production';
  await bind({ firebaseIdToken: await firebaseToken({ phone: '+8801700000003' }) });
  assert.equal(rpcCalls()[0].body.p_shared, false);
});

test('PHONE-06 the SMS must have been confirmed within the last 15 minutes', async () => {
  const fresh = await bind({ firebaseIdToken: await firebaseToken({ authAgoSeconds: 14 * 60 }) });
  assert.equal(fresh.status, 200, '14 minutes is fine');

  supabase.reset();
  const stale = await bind({ firebaseIdToken: await firebaseToken({ authAgoSeconds: 16 * 60 }) });
  assert.equal(stale.status, 401);
  assert.match(((await stale.json()) as any).error, /too old/);
  assert.equal(rpcCalls().length, 0);

  const noAuthTime = await bind({ firebaseIdToken: await firebaseToken({ authAgoSeconds: null }) });
  assert.equal(noAuthTime.status, 401, 'a token with no auth_time cannot prove recency');
  assert.equal(rpcCalls().length, 0);
});

test('PHONE-07 a sign-in that never confirmed an SMS (no phone_number claim) proves nothing', async () => {
  const res = await bind({ firebaseIdToken: await firebaseToken({ phone: null }) });
  assert.equal(res.status, 400);
  assert.equal(rpcCalls().length, 0);
});

test('PHONE-08 tokens that are not Firebase\'s are refused with 401', async () => {
  const header = (h: object) => Buffer.from(JSON.stringify(h)).toString('base64url');
  const payload = Buffer.from(
    JSON.stringify({ phone_number: '+8801900000114', auth_time: nowSec(), iss: `https://securetoken.google.com/${PROJECT}`, aud: PROJECT }),
  ).toString('base64url');
  const hs256 = await new SignJWT({ phone_number: '+8801900000114', auth_time: nowSec() })
    .setProtectedHeader({ alg: 'HS256', kid: KID })
    .setIssuer(`https://securetoken.google.com/${PROJECT}`)
    .setAudience(PROJECT)
    .setExpirationTime('1h')
    .sign(new TextEncoder().encode('a-shared-secret-of-thirty-two-chars!!'));

  const bad: Array<[string, string]> = [
    ['wrong audience', await firebaseToken({ aud: 'some-other-project' })],
    ['wrong issuer', await firebaseToken({ iss: 'https://securetoken.google.com/some-other-project' })],
    ['expired', await firebaseToken({ expiresInSeconds: -120 })],
    ['signed with a different private key', await firebaseToken({ key: otherKey })],
    ['alg none (unsigned)', `${header({ alg: 'none', typ: 'JWT' })}.${payload}.`],
    ['HS256 instead of RS256', hs256],
    ['not a JWT', 'definitely.not.a-jwt'],
  ];
  for (const [label, token] of bad) {
    const res = await bind({ firebaseIdToken: token });
    assert.equal(res.status, 401, label);
    assert.equal(rpcCalls().length, 0, `${label}: nothing may be bound`);
  }
});

test('PHONE-09 the body must carry a firebaseIdToken at all', async () => {
  for (const body of [{}, { firebaseIdToken: '' }, { firebaseIdToken: 123 }, { firebaseIdToken: null }]) {
    assert.equal((await bind(body)).status, 400, JSON.stringify(body));
  }
});

test('PHONE-10 the caller must be a signed-in, non-anonymous Supabase account', async () => {
  const token = await firebaseToken();
  assert.equal((await bind({ firebaseIdToken: token }, {})).status, 401, 'no session');
  assert.equal((await bind({ firebaseIdToken: token }, { Authorization: 'Bearer nope' })).status, 401, 'unknown session');
  assert.equal((await bind({ firebaseIdToken: token }, guest.headers)).status, 401, 'anonymous session');
  assert.equal(rpcCalls().length, 0);
});

test('PHONE-11 a number another account already verified is a 409, not a takeover', async () => {
  supabase.bindMode = 'taken';
  const res = await bind({ firebaseIdToken: await firebaseToken({ phone: '+8801900000114' }) });
  assert.equal(res.status, 409);
  assert.match(((await res.json()) as any).error, /already verified/);
});

test('PHONE-12 any other database failure is a generic 500 without internals', async () => {
  supabase.bindMode = 'error';
  const res = await bind({ firebaseIdToken: await firebaseToken() });
  assert.equal(res.status, 500);
  const text = await res.text();
  assert.ok(!/boom|service-key|hermetic-key/i.test(text), text);
});

test('PHONE-13 a server missing its Firebase project or service key answers 503, binding nothing', async () => {
  process.env.FIREBASE_PROJECT_ID = '';
  assert.equal((await bind({ firebaseIdToken: await firebaseToken() })).status, 503);
  process.env.FIREBASE_PROJECT_ID = PROJECT;
  process.env.SUPABASE_SERVICE_ROLE_KEY = '';
  assert.equal((await bind({ firebaseIdToken: await firebaseToken() })).status, 503);
  assert.equal(rpcCalls().length, 0);
});

test('PHONE-14 Google\'s signing keys are fetched once and cached, not per request', async () => {
  const before = jwksFetches;
  for (let i = 0; i < 5; i++) await bind({ firebaseIdToken: await firebaseToken() });
  assert.ok(jwksFetches - before <= 1, `${jwksFetches - before} JWKS fetches for 5 requests`);
});
