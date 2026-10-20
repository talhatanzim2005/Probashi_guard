import './helpers/hermeticEnv.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import type { Request, Response } from 'express';
import {
  assertDevBypassSafe,
  devAuthBypassEnabled,
  hasVerifiedPhone,
  requireAuth,
  resolveCaller,
  resolveUserId,
} from '../supabaseUser.js';
import { FakeSupabase } from './helpers/fakeServices.js';

const fake = new FakeSupabase();
const alice = fake.addAccount('alice', { verified: true });
const guest = fake.addAccount('guest', { anonymous: true });

test.before(async () => {
  await fake.start();
});
test.after(async () => {
  await fake.stop();
});
test.beforeEach(() => {
  fake.requests.length = 0;
  fake.profilesDown = false;
  process.env.NODE_ENV = 'test';
  process.env.DEV_AUTH_BYPASS = '';
  process.env.DEV_AUTH_BYPASS_TOKEN = '';
  process.env.DEV_AUTH_BYPASS_USER_ID = '';
  process.env.SUPABASE_URL = fake.url;
});

const req = (authorization?: string) => ({ headers: authorization ? { authorization } : {} }) as unknown as Request;

test('AUTHZ-01 no Authorization header, or one that is not a Bearer token, is "none"', async () => {
  assert.deepEqual(await resolveCaller(req()), { ok: false, reason: 'none' });
  assert.deepEqual(await resolveCaller(req('Basic abc')), { ok: false, reason: 'none' });
  assert.deepEqual(await resolveCaller(req('Bearer ')), { ok: false, reason: 'none' });
  assert.equal(fake.requests.length, 0, 'nothing is sent to Supabase for these');
});

test('AUTHZ-02 a token Supabase does not know is "invalid"', async () => {
  assert.deepEqual(await resolveCaller(req('Bearer not-a-real-token')), { ok: false, reason: 'invalid' });
});

test('AUTHZ-03 the user id comes from Supabase for the presented token', async () => {
  assert.deepEqual(await resolveCaller(req(alice.headers.Authorization)), { ok: true, userId: alice.id, anonymous: false });
  const sent = fake.calls('/auth/v1/user')[0];
  assert.equal(sent.headers.authorization, alice.headers.Authorization);
  assert.equal(sent.headers.apikey, 'anon-key-hermetic', 'the anon key identifies the project, not the service-role key');
});

test('AUTHZ-04 an anonymous session is reported as anonymous', async () => {
  assert.deepEqual(await resolveCaller(req(guest.headers.Authorization)), { ok: true, userId: guest.id, anonymous: true });
});

test('AUTHZ-05 resolveUserId (used for money) rejects anonymous and unknown callers', async () => {
  assert.equal(await resolveUserId(req(alice.headers.Authorization)), alice.id);
  assert.equal(await resolveUserId(req(guest.headers.Authorization)), null);
  assert.equal(await resolveUserId(req('Bearer nope')), null);
  assert.equal(await resolveUserId(req()), null);
});

test('AUTHZ-06 if Supabase cannot be reached the caller is "none", never let in', async () => {
  process.env.SUPABASE_URL = 'http://127.0.0.1:9'; // nothing listens on the discard port
  assert.deepEqual(await resolveCaller(req(alice.headers.Authorization)), { ok: false, reason: 'none' });
});

test('AUTHZ-07 requireAuth lets a real account through and records its id', async () => {
  const res = { locals: {} as Record<string, unknown> } as unknown as Response;
  let nextCalled = false;
  await requireAuth(req(alice.headers.Authorization), res, () => {
    nextCalled = true;
  });
  assert.ok(nextCalled);
  assert.equal((res.locals as any).userId, alice.id);
});

test('AUTHZ-08 requireAuth answers 401 for anonymous, unknown and missing tokens', async () => {
  for (const header of [guest.headers.Authorization, 'Bearer nope', undefined]) {
    let status = 0;
    let nextCalled = false;
    const res = {
      locals: {},
      status(code: number) {
        status = code;
        return this;
      },
      json() {
        return this;
      },
    } as unknown as Response;
    await requireAuth(req(header), res, () => {
      nextCalled = true;
    });
    assert.equal(status, 401, String(header));
    assert.equal(nextCalled, false, String(header));
  }
});

// --- developer bypass ------------------------------------------------------

test('AUTHZ-09 the developer bypass is OFF unless DEV_AUTH_BYPASS=1', () => {
  assert.equal(devAuthBypassEnabled(), false);
  process.env.DEV_AUTH_BYPASS = 'true';
  assert.equal(devAuthBypassEnabled(), false, 'only the exact value 1 switches it on');
  process.env.DEV_AUTH_BYPASS = '1';
  assert.equal(devAuthBypassEnabled(), true);
});

test('AUTHZ-10 the bypass token authenticates as the configured user, and only that token', async () => {
  process.env.DEV_AUTH_BYPASS = '1';
  process.env.DEV_AUTH_BYPASS_TOKEN = 'dev-token-123';
  process.env.DEV_AUTH_BYPASS_USER_ID = '11111111-1111-4111-8111-111111111111';
  assert.deepEqual(await resolveCaller(req('Bearer dev-token-123')), {
    ok: true,
    userId: '11111111-1111-4111-8111-111111111111',
    anonymous: false,
  });
  assert.deepEqual(await resolveCaller(req('Bearer dev-token-124')), { ok: false, reason: 'invalid' });
});

test('AUTHZ-11 with the bypass off, its token is just an unknown token', async () => {
  process.env.DEV_AUTH_BYPASS_TOKEN = 'dev-token-123';
  process.env.DEV_AUTH_BYPASS_USER_ID = '11111111-1111-4111-8111-111111111111';
  assert.deepEqual(await resolveCaller(req('Bearer dev-token-123')), { ok: false, reason: 'invalid' });
});

test('AUTHZ-12 the bypass needs both a token and a user id, or it grants nothing', async () => {
  process.env.DEV_AUTH_BYPASS = '1';
  process.env.DEV_AUTH_BYPASS_TOKEN = 'dev-token-123';
  assert.deepEqual(await resolveCaller(req('Bearer dev-token-123')), { ok: false, reason: 'invalid' });
});

test('AUTHZ-13 production ignores the bypass and refuses to boot with it set', async () => {
  process.env.NODE_ENV = 'production';
  process.env.DEV_AUTH_BYPASS = '1';
  process.env.DEV_AUTH_BYPASS_TOKEN = 'dev-token-123';
  process.env.DEV_AUTH_BYPASS_USER_ID = '11111111-1111-4111-8111-111111111111';
  assert.equal(devAuthBypassEnabled(), false);
  assert.throws(() => assertDevBypassSafe(), /Refusing to start/);
  assert.deepEqual(await resolveCaller(req('Bearer dev-token-123')), { ok: false, reason: 'invalid' });

  process.env.DEV_AUTH_BYPASS = '';
  assert.doesNotThrow(() => assertDevBypassSafe());
});

// --- phone verification gate ----------------------------------------------

test('AUTHZ-14 hasVerifiedPhone is true only for a profile with phone_verified_at set', async () => {
  assert.equal(await hasVerifiedPhone(alice.id), true);
  assert.equal(await hasVerifiedPhone(guest.id), false);
});

test('AUTHZ-15 hasVerifiedPhone fails CLOSED when the database is down', async () => {
  fake.profilesDown = true;
  assert.equal(await hasVerifiedPhone(alice.id), false);
  process.env.SUPABASE_URL = 'http://127.0.0.1:9';
  assert.equal(await hasVerifiedPhone(alice.id), false);
  process.env.SUPABASE_SERVICE_ROLE_KEY = '';
  assert.equal(await hasVerifiedPhone(alice.id), false);
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'service-key-hermetic';
});

test('AUTHZ-16 the user id is URL-encoded, so it cannot inject PostgREST filters', async () => {
  const hostile = 'abc&select=*&user_id=neq.0';
  await hasVerifiedPhone(hostile);
  const sent = fake.calls('/rest/v1/profiles')[0];
  assert.equal(sent.query.get('user_id'), `eq.${hostile}`);
  assert.equal(sent.query.get('select'), 'phone_verified_at', 'the select list was not overridden');
});
