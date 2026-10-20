import test from 'node:test';
import assert from 'node:assert';
import { isTestPhone, testPhoneNumbers, TEST_PHONE_POOL_SIZE } from '../testPhones.js';

const env = (o: Record<string, string>) => o as unknown as NodeJS.ProcessEnv;

test('only numbers listed in FIREBASE_TEST_PHONES are test numbers', () => {
  const e = env({ FIREBASE_TEST_PHONES: '+8801700000000, +8801711111111' });
  assert.deepStrictEqual(testPhoneNumbers(e), ['+8801700000000', '+8801711111111']);
  assert.ok(isTestPhone('+8801700000000', e));
  assert.ok(isTestPhone('+880 1700-000000', e));
  assert.ok(!isTestPhone('+8801911223344', e));
});

test('nothing is a test number when the list is empty or malformed', () => {
  assert.deepStrictEqual(testPhoneNumbers(env({})), []);
  assert.deepStrictEqual(testPhoneNumbers(env({ FIREBASE_TEST_PHONES: '01700000000, abc, ,+1' })), []);
});

test('production never treats a number as a test number', () => {
  const e = env({ NODE_ENV: 'production', FIREBASE_TEST_PHONES: '+8801700000000' });
  assert.deepStrictEqual(testPhoneNumbers(e), []);
  assert.ok(!isTestPhone('+8801700000000', e));
});

test('the shared pool holds 50 accounts', () => {
  assert.strictEqual(TEST_PHONE_POOL_SIZE, 50);
});
