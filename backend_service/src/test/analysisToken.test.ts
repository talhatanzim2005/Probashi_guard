import test from 'node:test';
import assert from 'node:assert';
import { canonicalJson, signAnalysis, verifyAnalysis } from '../analysisToken.js';

const analysis = { verdict: 'DO_NOT_SIGN', salary: { amount: 800, currency: 'SAR' }, tags: ['a', 'b'] };

test.beforeEach(() => {
  process.env.ANALYSIS_SIGNING_SECRET = 'unit-test-secret';
});

test('canonicalJson ignores key order', () => {
  assert.strictEqual(
    canonicalJson({ b: 1, a: { d: 2, c: 3 } }),
    canonicalJson({ a: { c: 3, d: 2 }, b: 1 })
  );
});

test('a token verifies for the same user, language and analysis', () => {
  const token = signAnalysis('user-1', 'en', analysis);
  assert.ok(token);
  assert.strictEqual(verifyAnalysis(token, 'user-1', 'en', { ...analysis }), 'ok');
});

test('a token fails if the analysis, user or language changed', () => {
  const token = signAnalysis('user-1', 'en', analysis)!;
  assert.strictEqual(verifyAnalysis(token, 'user-1', 'en', { ...analysis, verdict: 'SAFE_TO_SIGN' }), 'bad');
  assert.strictEqual(verifyAnalysis(token, 'user-2', 'en', analysis), 'bad');
  assert.strictEqual(verifyAnalysis(token, 'user-1', 'bn', analysis), 'bad');
  assert.strictEqual(verifyAnalysis(undefined, 'user-1', 'en', analysis), 'bad');
  assert.strictEqual(verifyAnalysis(`${Date.now() + 60000}.zz`, 'user-1', 'en', analysis), 'bad');
});

test('an expired token is reported as expired', () => {
  const realNow = Date.now;
  const token = signAnalysis('user-1', 'en', analysis)!;
  Date.now = () => realNow() + 31 * 60 * 1000;
  try {
    assert.strictEqual(verifyAnalysis(token, 'user-1', 'en', analysis), 'expired');
  } finally {
    Date.now = realNow;
  }
});

test('without a secret: development trusts the client, production refuses', () => {
  delete process.env.ANALYSIS_SIGNING_SECRET;
  assert.strictEqual(signAnalysis('user-1', 'en', analysis), null);
  assert.strictEqual(verifyAnalysis(null, 'user-1', 'en', analysis), 'unsigned-dev');
  const env = process.env.NODE_ENV;
  process.env.NODE_ENV = 'production';
  try {
    assert.strictEqual(verifyAnalysis(null, 'user-1', 'en', analysis), 'unavailable');
  } finally {
    process.env.NODE_ENV = env;
  }
});
