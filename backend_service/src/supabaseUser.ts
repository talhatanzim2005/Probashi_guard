import { NextFunction, Request, Response } from 'express';

/**
 * Resolves the Supabase account behind a request's `Authorization: Bearer`
 * header, by asking Supabase to validate the token.
 *
 * The id is NOT taken from the request body. A client-supplied user id would
 * let anyone attribute their Stripe payment to somebody else's wallet, so the
 * only id trusted here is the one Supabase returns for the presented token.
 *
 * Returns null when there is no token, the token is rejected, or it belongs to
 * an anonymous session — none of which may fund a wallet.
 */
export async function resolveUserId(req: Request): Promise<string | null> {
  const caller = await resolveCaller(req);
  return caller.ok && !caller.anonymous ? caller.userId : null;
}

/**
 * Whether this account has proven a phone number.
 *
 * Used to refuse a Checkout session BEFORE the person is charged. The gate
 * deliberately sits here rather than only in `deposit_to_wallet`: refusing at
 * the webhook would mean Stripe had already taken the money and nothing was
 * credited. Refusing here costs nobody anything.
 *
 * Returns false when it cannot tell, so an outage withholds the charge rather
 * than letting an unverified account through.
 */
export async function hasVerifiedPhone(userId: string): Promise<boolean> {
  const supabaseUrl = process.env.SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) return false;

  try {
    const response = await fetch(
      `${supabaseUrl}/rest/v1/profiles?user_id=eq.${encodeURIComponent(userId)}&select=phone_verified_at`,
      {
        headers: {
          apikey: serviceRoleKey,
          Authorization: `Bearer ${serviceRoleKey}`,
        },
      }
    );
    if (!response.ok) return false;

    const rows = (await response.json()) as Array<{ phone_verified_at?: string | null }>;
    return Array.isArray(rows) && rows.length > 0 && !!rows[0].phone_verified_at;
  } catch (err: any) {
    console.warn('[Auth] could not read phone verification state:', err?.message);
    return false;
  }
}

// ---------------------------------------------------------------------------
// Developer bypass
// ---------------------------------------------------------------------------

/**
 * A prototype needs a way to call the API without a real Supabase session
 * (curl, the automated tests). That is allowed, but only on purpose: it is OFF
 * unless DEV_AUTH_BYPASS=1, it is refused outright in production, the token
 * comes from the environment instead of the source, and it maps to a user id
 * chosen in the environment too.
 *
 * It used to switch on whenever the words "test" appeared in the process's
 * command line, so a deploy folder called `latest` enabled a public login.
 */
export function devAuthBypassEnabled(): boolean {
  return process.env.DEV_AUTH_BYPASS === '1' && process.env.NODE_ENV !== 'production';
}

/** Called once at boot: a production server must never carry the bypass. */
export function assertDevBypassSafe(): void {
  if (process.env.DEV_AUTH_BYPASS === '1' && process.env.NODE_ENV === 'production') {
    throw new Error(
      'DEV_AUTH_BYPASS=1 is set while NODE_ENV=production. Refusing to start: unset it.'
    );
  }
  if (devAuthBypassEnabled()) {
    console.warn(
      '[Auth] DEV_AUTH_BYPASS is ON: the configured dev token authenticates as a fixed user. Development only.'
    );
  }
}

function devBypassUser(header: string): string | null {
  if (!devAuthBypassEnabled()) return null;
  const token = process.env.DEV_AUTH_BYPASS_TOKEN;
  const userId = process.env.DEV_AUTH_BYPASS_USER_ID;
  if (!token || !userId) return null;
  return header === `Bearer ${token}` ? userId : null;
}

// ---------------------------------------------------------------------------
// One resolver for every route
// ---------------------------------------------------------------------------

export type Caller =
  | { ok: true; userId: string; anonymous: boolean }
  | { ok: false; reason: 'none' | 'invalid' };

/**
 * Who is calling. Anonymous Supabase sessions are reported (`anonymous: true`)
 * so each route decides whether they are enough: scanning a document is, moving
 * money is not.
 */
export async function resolveCaller(req: Request): Promise<Caller> {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) return { ok: false, reason: 'none' };

  const bypass = devBypassUser(header);
  if (bypass) return { ok: true, userId: bypass, anonymous: false };

  const token = header.slice('Bearer '.length).trim();
  if (!token) return { ok: false, reason: 'none' };

  const supabaseUrl = process.env.SUPABASE_URL;
  const apiKey = process.env.SUPABASE_ANON_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !apiKey) {
    console.warn('[Auth] SUPABASE_URL / key not configured; cannot identify the caller');
    return { ok: false, reason: 'none' };
  }

  try {
    const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: { apikey: apiKey, Authorization: `Bearer ${token}` },
    });
    if (!response.ok) return { ok: false, reason: 'invalid' };
    const user = (await response.json()) as { id?: string; is_anonymous?: boolean };
    if (!user?.id) return { ok: false, reason: 'invalid' };
    return { ok: true, userId: user.id, anonymous: !!user.is_anonymous };
  } catch (err: any) {
    console.warn('[Auth] could not verify the caller token:', err?.message);
    return { ok: false, reason: 'none' };
  }
}

/**
 * Express guard for routes that need a real (non-anonymous) account. Puts the
 * verified id on `res.locals.userId`.
 */
export async function requireAuth(req: Request, res: Response, next: NextFunction) {
  const caller = await resolveCaller(req);
  if (!caller.ok || caller.anonymous) {
    return res.status(401).json({ error: 'Sign in to continue.' });
  }
  res.locals.userId = caller.userId;
  next();
}
