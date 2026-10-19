import { Request } from 'express';

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
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) return null;

  const token = header.slice('Bearer '.length).trim();
  if (!token) return null;

  const supabaseUrl = process.env.SUPABASE_URL;
  // The anon key is enough to identify the bearer of a token, and keeps the
  // service-role key out of this path.
  const apiKey =
    process.env.SUPABASE_ANON_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !apiKey) {
    console.warn('[Auth] SUPABASE_URL / key not configured; cannot identify the caller');
    return null;
  }

  try {
    const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: { apikey: apiKey, Authorization: `Bearer ${token}` },
    });
    if (!response.ok) return null;

    const user = (await response.json()) as { id?: string; is_anonymous?: boolean };
    if (!user?.id || user.is_anonymous) return null;
    return user.id;
  } catch (err: any) {
    console.warn('[Auth] could not verify the caller token:', err?.message);
    return null;
  }
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
