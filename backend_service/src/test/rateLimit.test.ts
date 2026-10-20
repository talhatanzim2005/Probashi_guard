import test from 'node:test';
import assert from 'node:assert/strict';
import type { NextFunction, Request, Response } from 'express';
import { rateLimit } from '../rateLimit.js';

// A stand-in request/response pair: only the members rateLimit touches.
function call(limiter: ReturnType<typeof rateLimit>, who: { userId?: string; ip?: string }) {
  const headers: Record<string, unknown> = {};
  let status = 200;
  let body: unknown;
  let passed = false;
  const res = {
    locals: who.userId ? { userId: who.userId } : {},
    setHeader: (k: string, v: unknown) => {
      headers[k] = v;
    },
    status(code: number) {
      status = code;
      return this;
    },
    json(payload: unknown) {
      body = payload;
      return this;
    },
  } as unknown as Response;
  const next: NextFunction = () => {
    passed = true;
  };
  limiter({ ip: who.ip } as Request, res, next);
  return { passed, status, body, headers };
}

test('RATE-01 a caller gets exactly `max` requests per window, then 429', () => {
  const limiter = rateLimit({ name: 't', max: 3, windowMs: 60_000 });
  for (let i = 0; i < 3; i++) assert.ok(call(limiter, { userId: 'u1' }).passed, `request ${i + 1}`);
  const blocked = call(limiter, { userId: 'u1' });
  assert.equal(blocked.passed, false);
  assert.equal(blocked.status, 429);
  assert.match(String((blocked.body as any).error), /Too many requests/);
});

test('RATE-02 the 429 carries a Retry-After of at least one second', () => {
  const limiter = rateLimit({ name: 't', max: 1, windowMs: 30_000 });
  call(limiter, { userId: 'u1' });
  const blocked = call(limiter, { userId: 'u1' });
  const retry = Number(blocked.headers['Retry-After']);
  assert.ok(retry >= 1 && retry <= 30, `Retry-After ${retry}`);
});

test('RATE-03 one account being limited does not limit another', () => {
  const limiter = rateLimit({ name: 't', max: 1, windowMs: 60_000 });
  call(limiter, { userId: 'alice' });
  assert.equal(call(limiter, { userId: 'alice' }).status, 429);
  assert.ok(call(limiter, { userId: 'bob' }).passed);
});

test('RATE-04 with no verified user the key is the IP address', () => {
  const limiter = rateLimit({ name: 't', max: 1, windowMs: 60_000 });
  assert.ok(call(limiter, { ip: '10.0.0.1' }).passed);
  assert.equal(call(limiter, { ip: '10.0.0.1' }).status, 429);
  assert.ok(call(limiter, { ip: '10.0.0.2' }).passed);
});

test('RATE-05 callers with neither a user nor an IP share one "unknown" bucket', () => {
  const limiter = rateLimit({ name: 't', max: 1, windowMs: 60_000 });
  assert.ok(call(limiter, {}).passed);
  assert.equal(call(limiter, {}).status, 429);
});

test('RATE-06 the window resets once windowMs has passed', (t) => {
  t.mock.timers.enable({ apis: ['Date'], now: 1_000_000 });
  const limiter = rateLimit({ name: 't', max: 2, windowMs: 10_000 });
  call(limiter, { userId: 'u' });
  call(limiter, { userId: 'u' });
  assert.equal(call(limiter, { userId: 'u' }).status, 429);

  t.mock.timers.tick(9_999);
  assert.equal(call(limiter, { userId: 'u' }).status, 429, 'still inside the window');

  t.mock.timers.tick(2);
  assert.ok(call(limiter, { userId: 'u' }).passed, 'a new window opens');
});

test('RATE-07 two limiters keep separate counts', () => {
  const a = rateLimit({ name: 'a', max: 1, windowMs: 60_000 });
  const b = rateLimit({ name: 'b', max: 1, windowMs: 60_000 });
  call(a, { userId: 'u' });
  assert.equal(call(a, { userId: 'u' }).status, 429);
  assert.ok(call(b, { userId: 'u' }).passed);
});

test('RATE-08 expired entries are swept so the table cannot grow without bound', (t) => {
  t.mock.timers.enable({ apis: ['Date'], now: 5_000_000 });
  const limiter = rateLimit({ name: 't', max: 5, windowMs: 1_000 });
  for (let i = 0; i < 5_001; i++) call(limiter, { userId: `user-${i}` });
  t.mock.timers.tick(2_000);
  // This request pushes the table past 5,000 and triggers the sweep; the point
  // is that it still answers normally rather than throwing.
  assert.ok(call(limiter, { userId: 'fresh' }).passed);
  assert.ok(call(limiter, { userId: 'user-0' }).passed, 'an expired caller starts a new window');
});
