import { createHmac, timingSafeEqual } from 'crypto';

/**
 * A scan result is returned to the app so the worker can read it before
 * deciding to keep it; "keep" posts it back to /api/documents/save. Without
 * more, that endpoint would store whatever JSON a client cared to send as an
 * audit result. This token ties the saved analysis to what this server
 * actually produced, for that user and language, for a limited time.
 *
 * Stateless on purpose (an HMAC, no table): nothing to clean up, nothing to
 * look up, and a prototype needs nothing heavier.
 *
 *   token = <expiry-ms>.<hex hmac-sha256(secret, userId|language|expiry|sha256 of canonical analysis)>
 *
 * The secret is ANALYSIS_SIGNING_SECRET. Unset in development, tokens are
 * simply not issued or checked (with one warning); unset in production, saving
 * is refused rather than silently unprotected.
 */

const TTL_MS = 30 * 60 * 1000;

let warned = false;

function secret(): string | null {
  const value = process.env.ANALYSIS_SIGNING_SECRET;
  if (value) return value;
  if (!warned) {
    warned = true;
    console.warn(
      '[Documents] ANALYSIS_SIGNING_SECRET is not set: scan results are NOT signed and /save trusts the client. Fine for development only.'
    );
  }
  return null;
}

/** JSON with object keys sorted, so the same data always hashes the same. */
export function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value && typeof value === 'object') {
    const entries = Object.entries(value as Record<string, unknown>)
      .filter(([, v]) => v !== undefined)
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
    return `{${entries.map(([k, v]) => `${JSON.stringify(k)}:${canonicalJson(v)}`).join(',')}}`;
  }
  return JSON.stringify(value) ?? 'null';
}

function mac(key: string, userId: string, language: string, expiry: number, analysis: unknown) {
  return createHmac('sha256', key)
    .update(`${userId}|${language}|${expiry}|${canonicalJson(analysis)}`)
    .digest('hex');
}

/** Null when signing is not configured. */
export function signAnalysis(userId: string, language: string, analysis: unknown): string | null {
  const key = secret();
  if (!key) return null;
  const expiry = Date.now() + TTL_MS;
  return `${expiry}.${mac(key, userId, language, expiry, analysis)}`;
}

export type TokenCheck = 'ok' | 'unsigned-dev' | 'unavailable' | 'bad' | 'expired';

export function verifyAnalysis(
  token: unknown,
  userId: string,
  language: string,
  analysis: unknown
): TokenCheck {
  const key = secret();
  if (!key) {
    return process.env.NODE_ENV === 'production' ? 'unavailable' : 'unsigned-dev';
  }
  if (typeof token !== 'string') return 'bad';
  const [expiryText, given] = token.split('.');
  const expiry = Number(expiryText);
  if (!Number.isFinite(expiry) || !given) return 'bad';
  if (expiry < Date.now()) return 'expired';

  const expected = Buffer.from(mac(key, userId, language, expiry, analysis), 'hex');
  const actual = Buffer.from(given, 'hex');
  if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) return 'bad';
  return 'ok';
}
