/**
 * Firebase "phone numbers for testing" send no SMS (so cost nothing) and accept
 * one fixed code. They are the only way to verify a phone on the free plan.
 *
 * The catch: a verified number normally belongs to exactly one account (a
 * transfer is addressed to a number), and a test number is the same string for
 * every tester. So a number is treated as a SHARED pool when it appears in
 * FIREBASE_TEST_PHONES (E.164, comma separated: the same ones entered in the
 * Firebase console):
 *
 *   - up to TEST_PHONE_POOL_SIZE accounts may hold it at the same time;
 *   - the next one releases the oldest holder (first in, first out), so the
 *     total never exceeds the pool size;
 *   - a shared number can never receive a transfer (it names no one);
 *   - a real number, one not on the list, stays strictly one account.
 *
 * Off in production no matter what the variable says: there a number is a real
 * person's and may only ever move by a real verification.
 */
export const TEST_PHONE_POOL_SIZE = 50;

export function testPhoneNumbers(env: NodeJS.ProcessEnv = process.env): string[] {
  if (env.NODE_ENV === 'production') return [];
  return (env.FIREBASE_TEST_PHONES || '')
    .split(',')
    .map((n) => n.replace(/[^0-9+]/g, ''))
    .filter((n) => /^\+[0-9]{6,15}$/.test(n));
}

export function isTestPhone(phone: string, env: NodeJS.ProcessEnv = process.env): boolean {
  return testPhoneNumbers(env).includes(phone.replace(/[^0-9+]/g, ''));
}
