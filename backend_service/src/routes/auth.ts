import { Router, Request, Response } from 'express';
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { resolveUserId } from '../supabaseUser.js';

const router = Router();

/**
 * Google publishes the public half of the keys that sign Firebase ID tokens
 * here, in JWK form, and rotates them regularly. createRemoteJWKSet caches the
 * set and re-fetches when it sees an unknown `kid`, so a rotation needs no
 * deploy and no stored secret.
 *
 * This is the standard JWK endpoint, not the x509 one firebase-admin uses.
 */
const FIREBASE_JWKS = createRemoteJWKSet(
  new URL(
    'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'
  )
);

/**
 * How recently the SMS code must have been confirmed for the token to be
 * accepted here. A Firebase ID token lives an hour and can be refreshed for
 * much longer, so without this an old token keeps re-binding a number.
 */
const MAX_AUTH_AGE_SECONDS = 15 * 60;

/**
 * POST /api/auth/bind-phone
 *
 * Binds a phone number to the signed-in Supabase account, but only on proof
 * that the person actually holds it.
 *
 * Two tokens, deliberately:
 *   Authorization: Bearer <supabase access token>   — WHO is asking
 *   body.firebaseIdToken                            — WHAT they proved
 *
 * The phone number is read from the verified Firebase token's `phone_number`
 * claim and never from the request body. Trusting a body field would recreate
 * exactly the hole this replaces: anyone could bind any number, and because
 * p2p_transfer resolves recipients by number, claiming someone else's would
 * redirect their incoming money.
 */
router.post('/bind-phone', async (req: Request, res: Response) => {
  const projectId = process.env.FIREBASE_PROJECT_ID;
  const supabaseUrl = process.env.SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!projectId || !supabaseUrl || !serviceRoleKey) {
    console.error('[Auth] bind-phone is not configured (FIREBASE_PROJECT_ID / SUPABASE_*)');
    return res.status(503).json({ error: 'Phone verification is not configured' });
  }

  // 1. Who is asking. Verified against Supabase, never taken from the body.
  const userId = await resolveUserId(req);
  if (!userId) {
    return res.status(401).json({ error: 'Sign in before verifying a number' });
  }

  // 2. What they proved.
  const firebaseIdToken = req.body?.firebaseIdToken;
  if (typeof firebaseIdToken !== 'string' || !firebaseIdToken) {
    return res.status(400).json({ error: 'Missing firebaseIdToken' });
  }

  let phone: string;
  try {
    const { payload } = await jwtVerify(firebaseIdToken, FIREBASE_JWKS, {
      issuer: `https://securetoken.google.com/${projectId}`,
      audience: projectId,
      // Pinned, so a token claiming `alg: none` or a symmetric algorithm
      // cannot be used to forge one against a key we would otherwise accept.
      algorithms: ['RS256'],
    });

    // Firebase sets phone_number only once an SMS code has been confirmed, so
    // its presence IS the proof. An email or Google sign-in token has none.
    const claimed = payload.phone_number;
    if (typeof claimed !== 'string' || !claimed) {
      return res
        .status(400)
        .json({ error: 'That sign-in does not prove a phone number' });
    }

    // Replay guard: the SMS must have been confirmed just now, not weeks ago.
    const authTime = typeof payload.auth_time === 'number' ? payload.auth_time : 0;
    const ageSeconds = Math.floor(Date.now() / 1000) - authTime;
    if (!authTime || ageSeconds > MAX_AUTH_AGE_SECONDS) {
      return res
        .status(401)
        .json({ error: 'Verify the number again — that confirmation is too old' });
    }

    phone = claimed;
  } catch (err: any) {
    console.warn('[Auth] Firebase ID token rejected:', err?.message);
    return res.status(401).json({ error: 'Phone verification failed' });
  }

  // 3. Bind it. bind_verified_phone is granted to service_role alone, so this
  // is the only path that can set phone_verified_at.
  try {
    const rpcRes = await fetch(`${supabaseUrl}/rest/v1/rpc/bind_verified_phone`, {
      method: 'POST',
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ p_user_id: userId, p_phone: phone }),
    });

    const body = await rpcRes.text();
    if (!rpcRes.ok) {
      // 23505 is bind_verified_phone's "another account proved this number".
      const taken = body.includes('23505') || body.includes('already verified');
      console.error('[Auth] bind_verified_phone failed:', rpcRes.status, body);
      return res.status(taken ? 409 : 500).json({
        error: taken
          ? 'Another account has already verified that number'
          : 'Could not save the verified number',
      });
    }

    console.log(`[Auth] Phone verified and bound for user ${userId}`);
    return res.json({ verified: true });
  } catch (err: any) {
    console.error('[Auth] bind-phone sync error:', err?.message);
    return res.status(500).json({ error: 'Could not save the verified number' });
  }
});

export default router;
