/**
 * Live end-to-end smoke test: signs in as the seeded test account and drives the
 * running backend and the real Supabase project, the way the app does.
 *
 *   npm run dev                        (in another terminal: the backend on :3000)
 *   npm run e2e:live                   read-only checks, safe to run any time
 *
 * Anything that WRITES is opt-in, because this talks to the real project:
 *
 *   --swap                             move 1.00 BDT card_visa -> card_wps and back (4 ledger rows, net zero)
 *   --bind-phone +8801700000003        prove a Firebase TEST number with code 123456, bind it (needs FIREBASE_WEB_API_KEY)
 *   --checkout                         open a Stripe TEST Checkout session (nothing is charged unless you pay it)
 *   --p2p +8801900000114 1.00          send 1.00 BDT to another account's verified number (not reversible from here)
 *
 * Environment (backend_service/.env is read; these override it):
 *   BACKEND_URL           default http://localhost:3000
 *   SUPABASE_URL, SUPABASE_ANON_KEY       the project and its public (anon / publishable) key
 *   E2E_EMAIL / E2E_PASSWORD              default sender@example.com / Test1234! (the account in docs/SETUP.md §6)
 *   FIREBASE_WEB_API_KEY                  the web API key of the Firebase project (only for --bind-phone)
 *
 * The test phones are +8801700000000 .. +8801700000009 and the code is 123456
 * for all of them; they are Firebase console test numbers, so no SMS is sent.
 * Test numbers can SEND but never RECEIVE a transfer (see docs/TESTCASES.md).
 *
 * Nothing here ever prints a token or a key. Exit code 1 if any check fails.
 */
import dotenv from 'dotenv';

dotenv.config();

const args = process.argv.slice(2);
const flag = (name: string) => args.includes(name);
const valueOf = (name: string, offset = 1) => args[args.indexOf(name) + offset];

const BACKEND = (process.env.BACKEND_URL || 'http://localhost:3000').replace(/\/$/, '');
const SUPABASE_URL = process.env.SUPABASE_URL || '';
const ANON_KEY = process.env.SUPABASE_ANON_KEY || '';
const EMAIL = process.env.E2E_EMAIL || 'sender@example.com';
const PASSWORD = process.env.E2E_PASSWORD || 'Test1234!';
const FIREBASE_KEY = process.env.FIREBASE_WEB_API_KEY || '';
const TEST_CODE = '123456';

let failures = 0;
let passes = 0;
let skips = 0;

type Result = { ok: boolean; detail?: string } | void;
async function step(id: string, title: string, run: () => Promise<Result>) {
  try {
    const result = await run();
    if (result && !result.ok) {
      failures++;
      console.log(`FAIL  ${id} ${title}${result.detail ? `\n        ${result.detail}` : ''}`);
    } else {
      passes++;
      console.log(`PASS  ${id} ${title}${result && result.detail ? `  (${result.detail})` : ''}`);
    }
  } catch (err: any) {
    failures++;
    console.log(`FAIL  ${id} ${title}\n        ${err?.message ?? err}`);
  }
}
function skip(id: string, title: string, why: string) {
  skips++;
  console.log(`SKIP  ${id} ${title}  [${why}]`);
}

async function json(res: Response): Promise<any> {
  const text = await res.text();
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

async function rest(path: string, token: string, init: RequestInit = {}) {
  const res = await fetch(`${SUPABASE_URL}${path}`, {
    ...init,
    headers: { apikey: ANON_KEY, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', ...(init.headers ?? {}) },
  });
  return { status: res.status, body: await json(res) };
}
const rpc = (name: string, token: string, body: unknown) =>
  rest(`/rest/v1/rpc/${name}`, token, { method: 'POST', body: JSON.stringify(body) });

async function main() {
  console.log(`Backend  ${BACKEND}`);
  console.log(`Supabase ${SUPABASE_URL || '(not set)'}`);
  console.log(`Account  ${EMAIL}\n`);

  if (!SUPABASE_URL || !ANON_KEY) {
    console.log('Set SUPABASE_URL and SUPABASE_ANON_KEY (backend_service/.env has them).');
    process.exit(2);
  }

  // --- E2E-01..02 backend is up ----------------------------------------------
  await step('E2E-01', 'GET /api/health answers ok', async () => {
    const res = await fetch(`${BACKEND}/api/health`);
    const body = await json(res);
    return { ok: res.status === 200 && body.status === 'ok' };
  });
  await step('E2E-02', 'GET /api/rates returns BDT-based rates including USD', async () => {
    const body = await json(await fetch(`${BACKEND}/api/rates`));
    return { ok: body.base === 'BDT' && body.rates?.USD > 100, detail: `USD=${body.rates?.USD}` };
  });

  // --- E2E-03 sign in --------------------------------------------------------
  let token = '';
  let userId = '';
  await step('E2E-03', 'sign in with email + password (Supabase Auth)', async () => {
    const res = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
      method: 'POST',
      headers: { apikey: ANON_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: EMAIL, password: PASSWORD }),
    });
    const body = await json(res);
    if (res.status !== 200) {
      return {
        ok: false,
        detail: `${res.status} ${body?.error_code ?? body?.msg ?? ''}. The account in the repo's docs is sender@example.com; set E2E_EMAIL / E2E_PASSWORD if yours differs.`,
      };
    }
    token = body.access_token;
    userId = body.user?.id;
    return { ok: !!token && body.user?.is_anonymous === false };
  });
  if (!token) {
    console.log('\nCannot continue without a session.');
    return summary();
  }

  // --- E2E-04..06 the account's own data (row-level security) ----------------
  let wpsBalance = 0;
  await step('E2E-04', 'the account has exactly three card wallets', async () => {
    const { status, body } = await rest('/rest/v1/wallets?select=card_id,balance&order=card_id', token);
    if (status !== 200 || !Array.isArray(body)) return { ok: false, detail: `${status} ${JSON.stringify(body)}` };
    wpsBalance = Number(body.find((w: any) => w.card_id === 'card_wps')?.balance ?? 0);
    const ids = body.map((w: any) => w.card_id).join(',');
    return { ok: ids === 'card_probashi,card_visa,card_wps', detail: body.map((w: any) => `${w.card_id}=${w.balance}`).join('  ') };
  });
  await step('E2E-05', 'the account sees only its own profile, with a verified phone', async () => {
    const { status, body } = await rest('/rest/v1/profiles?select=user_id,phone,phone_verified_at,phone_is_shared', token);
    if (status !== 200 || body.length !== 1) return { ok: false, detail: `${status} rows=${body?.length}` };
    const row = body[0];
    return { ok: row.user_id === userId && !!row.phone && !!row.phone_verified_at, detail: `${row.phone} shared=${row.phone_is_shared}` };
  });
  await step('E2E-06', 'the account sees only its own ledger rows', async () => {
    const { status, body } = await rest('/rest/v1/transactions?select=user_id&limit=200', token);
    return { ok: status === 200 && body.every((r: any) => r.user_id === userId), detail: `${body.length} rows` };
  });

  // --- E2E-07..09 the backend-only functions are closed to a signed-in client -
  // Each probe uses an invalid argument, so even if a grant were wrong nothing
  // could be credited: the point is WHICH error comes back. 42501 / 403 means
  // "no permission" (good); a validation error would mean the function ran.
  for (const [id, name, body] of [
    ['E2E-07', 'deposit_to_wallet', { p_user_id: userId, p_amount: 1, p_idempotency_key: 'e2e-probe', p_description: '', p_card_id: 'card_probe' }],
    ['E2E-08', 'settle_remittance', { p_user_id: userId, p_card_id: 'card_probe', p_session_id: 'cs_e2e_probe', p_amount_bdt: 1, p_recipient_name: '', p_recipient_phone: null }],
    ['E2E-09', 'bind_verified_phone', { p_user_id: userId, p_phone: 'not-a-phone', p_shared: false, p_shared_cap: 50 }],
  ] as const) {
    await step(id, `a signed-in client cannot call ${name}`, async () => {
      const { status, body: out } = await rpc(name, token, body);
      const denied = status === 401 || status === 403 || out?.code === '42501';
      return { ok: denied, detail: `${status} ${out?.code ?? ''} ${out?.message ?? ''}`.trim() };
    });
  }

  // --- E2E-10..11 backend auth gates ----------------------------------------
  await step('E2E-10', 'send-money without a session is refused before Stripe (403 phone_not_verified)', async () => {
    const res = await fetch(`${BACKEND}/api/checkout/send-money`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ cardId: 'card_wps', amountBdt: 1195, sourceAmount: 1195, sourceCurrency: 'BDT' }),
    });
    const body = await json(res);
    return { ok: res.status === 403 && body.code === 'phone_not_verified' && !body.checkoutUrl };
  });
  await step('E2E-11', 'protected routes reject a missing or made-up token', async () => {
    const a = await fetch(`${BACKEND}/api/checkout/session-status/cs_test_aaaaaaaaaaaa`);
    const b = await fetch(`${BACKEND}/api/chat`, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer nope' }, body: '{"message":"hi"}' });
    return { ok: a.status === 401 && b.status === 401, detail: `${a.status}, ${b.status}` };
  });

  // --- E2E-12 recipient lookup ----------------------------------------------
  await step('E2E-12', 'lookup_recipient: an unknown number is {found:false}, never an error or a name', async () => {
    const { status, body } = await rpc('lookup_recipient', token, { p_phone: '+8801000000001' });
    return { ok: status === 200 && body?.found === false, detail: JSON.stringify(body) };
  });
  await step('E2E-13', 'lookup_recipient: a shared Firebase test number is never a recipient', async () => {
    const { status, body } = await rpc('lookup_recipient', token, { p_phone: '+8801700000003' });
    return { ok: status === 200 && body?.found === false, detail: JSON.stringify(body) };
  });

  // --- optional writes -------------------------------------------------------
  if (flag('--swap')) {
    const key = `e2e-swap-${Date.now()}`;
    await step('E2E-20', 'card swap visa -> wps moves exactly 1.00 and a retry with the same key moves nothing', async () => {
      const first = await rpc('internal_transfer', token, { p_from_card: 'card_visa', p_to_card: 'card_wps', p_amount: 1, p_idempotency_key: key });
      if (first.status !== 200) return { ok: false, detail: `${first.status} ${JSON.stringify(first.body)}` };
      const retry = await rpc('internal_transfer', token, { p_from_card: 'card_visa', p_to_card: 'card_wps', p_amount: 1, p_idempotency_key: key });
      const now = Number((await rest('/rest/v1/wallets?select=balance&card_id=eq.card_wps', token)).body[0].balance);
      return { ok: first.body.repeated === false && retry.body.repeated === true && Math.abs(now - (wpsBalance + 1)) < 0.005, detail: `wps ${wpsBalance} -> ${now}` };
    });
    await step('E2E-21', 'card swap back wps -> visa restores the balances', async () => {
      const back = await rpc('internal_transfer', token, { p_from_card: 'card_wps', p_to_card: 'card_visa', p_amount: 1, p_idempotency_key: `${key}-back` });
      const now = Number((await rest('/rest/v1/wallets?select=balance&card_id=eq.card_wps', token)).body[0].balance);
      return { ok: back.status === 200 && Math.abs(now - wpsBalance) < 0.005, detail: `wps back to ${now}` };
    });
    await step('E2E-22', 'a swap that would overdraw is refused and changes nothing', async () => {
      const r = await rpc('internal_transfer', token, { p_from_card: 'card_visa', p_to_card: 'card_wps', p_amount: 999999999, p_idempotency_key: null });
      return { ok: r.status >= 400 && /enough balance/i.test(String(r.body?.message)), detail: `${r.status} ${r.body?.message ?? ''}` };
    });
  } else {
    skip('E2E-20..22', 'card swap, idempotency and overdraw', 'writes 4 ledger rows; pass --swap');
  }

  if (flag('--bind-phone')) {
    const phone = valueOf('--bind-phone') || '+8801700000003';
    if (!FIREBASE_KEY) {
      skip('E2E-30', `prove ${phone} with code ${TEST_CODE} and bind it`, 'set FIREBASE_WEB_API_KEY');
    } else {
      await step('E2E-30', `Firebase test number ${phone} + code ${TEST_CODE} -> backend binds it as shared`, async () => {
        const toolkit = 'https://identitytoolkit.googleapis.com/v1/accounts';
        const sent = await json(
          await fetch(`${toolkit}:sendVerificationCode?key=${FIREBASE_KEY}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ phoneNumber: phone, recaptchaToken: 'probashi-guard-test-number' }),
          }),
        );
        if (!sent.sessionInfo) return { ok: false, detail: `sendVerificationCode: ${JSON.stringify(sent.error?.message ?? sent)}. Is ${phone} in the Firebase console's test numbers?` };
        const signedIn = await json(
          await fetch(`${toolkit}:signInWithPhoneNumber?key=${FIREBASE_KEY}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ sessionInfo: sent.sessionInfo, code: TEST_CODE }),
          }),
        );
        if (!signedIn.idToken) return { ok: false, detail: `signInWithPhoneNumber: ${JSON.stringify(signedIn.error?.message ?? signedIn)}` };
        const bind = await fetch(`${BACKEND}/api/auth/bind-phone`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify({ firebaseIdToken: signedIn.idToken }),
        });
        const out = await json(bind);
        return { ok: bind.status === 200 && out.verified === true, detail: `${bind.status} ${JSON.stringify(out)}` };
      });
      await step('E2E-31', 'a wrong code is refused by Firebase', async () => {
        const toolkit = 'https://identitytoolkit.googleapis.com/v1/accounts';
        const sent = await json(
          await fetch(`${toolkit}:sendVerificationCode?key=${FIREBASE_KEY}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ phoneNumber: phone, recaptchaToken: 'probashi-guard-test-number' }),
          }),
        );
        const res = await fetch(`${toolkit}:signInWithPhoneNumber?key=${FIREBASE_KEY}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ sessionInfo: sent.sessionInfo, code: '000000' }),
        });
        const out = await json(res);
        return { ok: res.status === 400 && /INVALID_CODE/.test(JSON.stringify(out)), detail: String(out?.error?.message ?? '') };
      });
    }
  } else {
    skip('E2E-30..31', 'Firebase test-number proof and bind', 'changes the account\'s bound phone; pass --bind-phone <number>');
  }

  if (flag('--checkout')) {
    await step('E2E-40', 'send-money opens a hosted Stripe TEST Checkout session priced in USD', async () => {
      const res = await fetch(`${BACKEND}/api/checkout/send-money`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({
          cardId: 'card_wps',
          recipientName: 'E2E Recipient',
          recipientPhone: '+8801900000114',
          sourceAmount: 1195,
          sourceCurrency: 'BDT',
          exchangeRate: 1,
          amountBdt: 1195,
          incentiveBdt: 29.875,
        }),
      });
      const body = await json(res);
      if (res.status !== 201) return { ok: false, detail: `${res.status} ${JSON.stringify(body)}` };
      const status = await json(await fetch(`${BACKEND}/api/checkout/session-status/${body.sessionId}`, { headers: { Authorization: `Bearer ${token}` } }));
      console.log(`        Open to pay with Stripe test card 4242 4242 4242 4242:\n        ${body.checkoutUrl}`);
      return { ok: /^https:\/\/checkout\.stripe\.com\//.test(body.checkoutUrl) && status.is_paid === false, detail: `session ${body.sessionId}, unpaid` };
    });
  } else {
    skip('E2E-40', 'open a Stripe test Checkout session', 'creates a session on the Stripe test account; pass --checkout');
  }

  if (flag('--p2p')) {
    const to = valueOf('--p2p', 1);
    const amount = Number(valueOf('--p2p', 2) || '1');
    await step('E2E-50', `p2p_transfer of ${amount} to ${to}`, async () => {
      const { status, body } = await rpc('p2p_transfer', token, { p_recipient_phone: to, p_amount: amount, p_description: 'e2e', p_idempotency_key: `e2e-p2p-${Date.now()}` });
      return { ok: status === 200 && body?.repeated === false, detail: `${status} ${JSON.stringify(body)}` };
    });
  } else {
    skip('E2E-50', 'person-to-person transfer', 'moves real (test) money to another account; pass --p2p <number> <amount>');
  }

  summary();
}

function summary() {
  console.log(`\n${passes} passed, ${failures} failed, ${skips} skipped`);
  process.exit(failures ? 1 : 0);
}

main().catch((err) => {
  console.error('Unexpected error:', err?.message ?? err);
  process.exit(1);
});
