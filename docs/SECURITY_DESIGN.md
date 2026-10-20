# Probashi Guard — Security Design and Audit

| | |
|---|---|
| **Audit snapshot** | 2026-10-20 · branch `talha` · commit `f125438` · app `1.0.0+1` |
| **Companion documents** | [SYSTEM_ARCHITECTURE.md](SYSTEM_ARCHITECTURE.md) · [CORE_ALGORITHM.md](CORE_ALGORITHM.md) |
| **Stage assumed** | Prototype; Stripe in **sandbox (test mode)**, per the project owner. Severities are rated for the point where the prototype goes live. The **Gate** column in §1 says when each finding actually starts to matter. |
| **Type of review** | White-box code and configuration review, plus a read-only look at live Supabase metadata. **No active attack was run against any live system.** Findings marked *confirmed live* were observed in the production Supabase project (`xfwxiawapksepskcevwe`) on 2026-10-20. |
| **Not covered** | Stripe dashboard settings, Firebase console (test numbers, App Check, SMS region policy), Supabase Auth dashboard (anonymous sign-in, redirect URLs, email templates, captcha), OpenRouter account privacy settings, any hosting environment (none exists in the repo). Items that depend on those are marked *verify*. |

---

## 1. Executive summary

**Posture in one sentence.** The *database and webhook* layers are designed carefully and are the strongest part of the system; the *money flow as a whole* is not yet a remittance system, the *client* trusts and invents too much, and *operational security* (CI, monitoring, environments, secrets hygiene) is mostly absent. It is a well-built prototype and **must not take live money or real documents yet**.

### What is done well

| Area | Evidence |
|---|---|
| **Clients cannot write money.** `authenticated` holds only `SELECT` on `wallets` and `transactions`; every balance change is a `SECURITY DEFINER` function with row locks, rounding, `CHECK` constraints and idempotency keys. `deposit_to_wallet`, `settle_remittance`, `bind_verified_phone`, `match_faqs` are `service_role` only (confirmed live: none appear in the advisor's "callable by anon/authenticated" list). | [p2p_core.sql](../supabase/migrations/20261019140000_p2p_core.sql), [sub_wallets.sql](../supabase/migrations/20261020100000_sub_wallets.sql) |
| **Phone numbers are proven, not claimed.** RS256 Firebase token verified against Google's rotating JWKS with algorithm pinned, issuer and audience checked, number read from the *token claim*, 15-minute freshness, `set_my_phone` revoked from clients. | [auth.ts](../backend_service/src/routes/auth.ts) |
| **Stripe amounts are not trusted.** Price derived server-side from one input; webhook needs signature, `kind`, `paid`, USD, whitelisted card, and re-derives the expected price; payer comes from a verified token; booking is idempotent on the session id. | [webhooks.ts](../backend_service/src/routes/webhooks.ts) |
| **Developer bypass is fenced.** Off by default, refused at boot when `NODE_ENV=production`, token and user id from the environment. | [supabaseUser.ts](../backend_service/src/supabaseUser.ts) |
| **The AI cannot clear a trap.** Deterministic rules force `DO_NOT_SIGN`; output is coerced to a fixed schema; saved audits are HMAC-bound to user, language and content; images are never stored. | [documents.ts](../backend_service/src/routes/documents.ts), [analysisToken.ts](../backend_service/src/analysisToken.ts) |
| **RLS everywhere, and grants narrowed.** All 12 public tables have RLS (confirmed live); `TRUNCATE/REFERENCES/TRIGGER` revoked; `payment_methods` has no column that could hold a PAN. | [enforce_rls_all_tables.sql](../supabase/migrations/20261019180000_enforce_rls_all_tables.sql) |
| **Hygiene.** `.env`, `key.properties`, `google-services.json`, keystores are git-ignored (checked); release keystore is outside the repo; Android `allowBackup=false`; cleartext only in debug; `/success` page reflects only a regex-validated id; logout wipes local caches. | `.gitignore`, `AndroidManifest.xml` |

### Findings at a glance (26, plus 11 more in the [§10 addendum](#10-addendum-second-pass-2026-10-20))

**Gate** = when the finding starts to matter: **Now** (a bug or handover hazard at any stage) · **Live money** (before Stripe leaves test mode) · **Real documents** (before anyone scans a real passport or contract) · **Public** (before the backend is internet-facing or a public beta opens).

| Sev | ID | Title | Gate | Status |
|---|---|---|---|---|
| **High** | SEC-01 | Collected funds are never delivered; no production path can fund a wallet | Live money | confirmed in code |
| **High** | SEC-02 | Saving a contract/visa audit is rejected by the live database | **Now** | **confirmed live** |
| **High** | SEC-03 | Wallet UI fails open to invented balances, history and contacts | **Now** | confirmed in code |
| **High** | SEC-04 | Stripe Connect endpoints have no ownership checks | Live money | confirmed in code |
| **High** | SEC-05 | Passport/contract photos and questions go to free third-party models; PII stored unencrypted | Real documents | confirmed in code · *verify provider terms* |
| Medium | SEC-06 | Webhook acknowledges a failed booking, so Stripe never retries | Live money | confirmed in code |
| Medium | SEC-07 | Webhook signature helper has an unsigned fallback | Live money | confirmed in code |
| Medium | SEC-08 | Costly endpoints lack rate limits; anonymous identities are free | Public | confirmed in code |
| Medium | SEC-09 | `lookup_recipient` enables name enumeration and accepts anonymous callers | Public | confirmed in code |
| Medium | SEC-10 | Tokens and cached identity data sit in plain `SharedPreferences`; no app lock | Real documents | confirmed in code |
| Medium | SEC-11 | Migration ledger, repo and live schema disagree | **Now** | **confirmed live** |
| Medium | SEC-12 | Weak account policy (6-char passwords, leaked-password check off) | Public | **confirmed live** |
| Medium | SEC-13 | Pricing/accounting inconsistencies and no transaction limits | Live money | confirmed in code |
| Medium | SEC-14 | `handle_new_user()` and an unknown `rls_auto_enable()` are callable via the API | **Now** (two `REVOKE`s) | **confirmed live** |
| Medium | SEC-15 | Release and build hygiene (debug-key fallback, no CI, placeholder iOS id…) | Public | confirmed |
| Medium | SEC-16 | Firebase test-number mode is the default in every build | Public | confirmed in code · *verify console* |
| Medium | SEC-17 | Security test assets are stale or touch live systems | **Now** | confirmed |
| Low | SEC-18 – SEC-26 | Error/log leakage · route sprawl · Trigger stub · Origin-derived URLs · limiter keying · token scope · token replay window · dead deep link and stale docs · content governance | Public | confirmed |

**Readiness verdict.** For a sandbox prototype the design is sound and nothing here puts real money at risk. Fix the **Now** rows (SEC-02, 03, 11, 14, 17) at any stage: they are bugs, misleading output or handover hazards, not future risks. The **Live money** rows (SEC-01, 04, 06, 07, 13) are the checklist for flipping Stripe out of test mode. The **Real documents** rows (SEC-05, 10) apply from the first moment a tester scans a real passport or contract — until then, test with specimen or redacted documents. Everything else before a public beta.

---

## 2. Assets, actors and trust boundaries

**Assets (most to least sensitive)**

1. Identity documents and contracts of migrant workers (passport numbers, DOB, visa/sponsor data, full contract text and translation) — `saved_documents`, the on-device cache, and the photos in transit.
2. Money: wallet balances, the ledger, the Stripe account and its keys.
3. Account control: Supabase sessions, the service-role key, the Stripe secret key, the Firebase project.
4. Phone ↔ account binding (it decides where money lands).
5. Recipient directory (names behind phone numbers).
6. Availability of free AI quota; integrity of the FAQ knowledge base.

**Actors**: honest worker; abusive/curious registered user; unauthenticated internet client; person with a stolen/shared/rooted phone; hostile document author (prompt injection); malicious or compromised third party (LLM provider); insider with repo access; Stripe/Supabase/Firebase as trusted-but-failing dependencies.

```
 ┌─ UNTRUSTED ─────────────┐     ┌─ SEMI-TRUSTED ───────────────┐     ┌─ TRUSTED ────────────────────┐
 │ Phone: app code, local  │     │ backend_service              │     │ Postgres: grants + functions │
 │ storage, camera input   │     │ holds service-role + Stripe  │     │ are the real access control  │
 │ Document text (hostile) │ ──► │ + OpenRouter keys; validates │ ──► │ RLS on every table           │
 │ Any request body field  │ TLS │ every claim itself           │     │ service_role-only functions  │
 └─────────────────────────┘     └──────────────┬───────────────┘     └──────────────────────────────┘
        │ also direct (anon key + user JWT)     │ third parties receiving data: OpenRouter (documents,
        └───────────────────────────────────────┴──► questions), Stripe, Firebase, Trigger.dev
```
Rule the code follows well: **no identity, amount, phone or price is taken from a request body when it can be derived from a verified token or recomputed.** Rule it breaks: *"the client display is only a display"* — see SEC-03.

### Threat summary by component

| Component | Main threats | Controls present | Gaps |
|---|---|---|---|
| Login / sessions | credential stuffing, weak passwords, anonymous abuse, token theft | Supabase Auth, email OTP, PKCE | SEC-12, SEC-10, SEC-08 |
| Phone binding | claiming someone else's number, replay, test-number abuse | JWKS-verified token, freshness, unique verified index, revoked client RPC | SEC-16, SEC-24 |
| Ledger | forged balances, double spend, overdraw, race | grants, definer functions, locks, CHECK, idempotency | SEC-01 (nothing funds it) |
| Stripe / webhook | forged events, price tampering, replay, mis-credit | signature on raw body, gates, re-derived price, idempotency | SEC-06, SEC-07, SEC-13 |
| Document scanner | prompt injection, oversized input, tampered save, data exfiltration | untrusted-text prompt, schema coercion, hard rules, size/format checks, HMAC token | SEC-02, SEC-05, SEC-08 |
| Prohori | prompt injection, quota burn, hallucinated advice | separate system/user messages, 12/min limit, no tools | SEC-26 |
| Mobile app | local data theft, screen capture, tamper | `allowBackup=false`, cache wipe on logout, balance auto-hide | SEC-10, SEC-15 |
| Database | privilege creep, drift, enumeration | RLS, narrowed grants, advisors | SEC-09, SEC-11, SEC-14 |

---

## 3. Security design by layer

### 3.1 Identity and sessions
- **Supabase Auth** is the only identity system. Firebase is a *proof provider*; its session is signed out right after the ID token is handed over.
- The backend never trusts a user id from a body. `resolveCaller()` asks Supabase to validate the bearer token and returns `{userId, anonymous}`; money, chat, Stripe and phone binding require a **non-anonymous** user.
- OAuth uses the `io.supabase.probashiguard://login-callback/` deep link (and the page origin on web); `supabase_flutter` v2 defaults to PKCE, which makes an intercepted code useless without the verifier.
- Logout clears profile, checklist, wallet mirror, vault cache and the anonymous-claim token.
- Pre-login anonymous data is migrated with a one-time, 24-hour token that only an anonymous session can mint and only a real account can spend.

### 3.2 Authorisation: the database is the policy
| Object | Client access | Mechanism |
|---|---|---|
| `wallets`, `transactions` | read own rows | RLS `auth.uid() = user_id` + `GRANT SELECT` only |
| `profiles` | read own; update `full_name`, `avatar_url` | column-level grant; `phone`, `phone_verified_at`, `phone_is_shared` not writable |
| `payment_methods`, `beneficiaries` | CRUD own rows | RLS `FOR ALL` |
| `saved_documents` | read own rows | writes only by `backend_service` (service role) |
| `notices` | public read | `SELECT` only |
| `faq_embeddings`, `anonymous_claims`, `rpc_rate_limits` | none | RLS on, no policy, no grant |
| Money / phone / search functions | see matrix in §9 | `REVOKE … FROM public, anon, authenticated; GRANT … TO service_role` |

A column-level `GRANT UPDATE (…)` *adds* to an existing table-level grant; the migrations therefore start from `REVOKE ALL`. That lesson is encoded in the files — keep it.

### 3.3 Money integrity
1. The only inputs the client controls are `amountBdt`, `cardId` and the recipient label. Price = `f(amountBdt)`, computed server-side; webhook re-derives it.
2. Payer = verified token → `metadata.payerUserId` → booking target. No payer → nothing is booked.
3. **Verified phone required before a Checkout session is created** (refusing after payment would strand money); the same gate exists in `p2p_transfer`. (The `P0003` exception that used to back it up inside the deposit function was dropped by `sub_wallets.sql`; see SEC-28.)
4. Ledger legs are immutable by clients; a statement can be rebuilt from `balance_before/after`.

### 3.4 Document pipeline
Size/page/format limits with magic-byte checks → untrusted-text prompt → schema coercion → deterministic rules → signed result → explicit user "save". No auto-save is a deliberate privacy decision. Images are never persisted; only a SHA-256.

### 3.5 Prohori
User text never enters the system message; the model has **no tools and no secrets in its prompt**, so injection can only produce a bad *answer*, not an action. Output is stripped of markdown. Per-user 12/min limit.

### 3.6 Transport, secrets and build
- HTTPS to Supabase/Stripe/OpenRouter; the app→backend link is HTTPS only in release (Android cleartext is a debug-only manifest override). TLS termination for `backend_service` is **not** configured anywhere in the repo.
- Secrets live in `backend_service/.env` (ignored). The Supabase management token was moved to a user-level environment variable (project notes). The client contains only the *publishable* Supabase key and web Firebase options (public by design — restrict them by domain/app in the consoles).
- Release signing key is outside the repo; `key.properties` is ignored.

---

## 4. Findings register

Each finding gives evidence, impact and a concrete fix. File links point into the repo.

### High

#### SEC-01 — Collected funds are never delivered; no production path can fund a wallet
- **Evidence.** [checkout.ts:261–284](../backend_service/src/routes/checkout.ts#L261) calls `buildDestinationChargeData(...)` but keeps only `destinationAccountId`; the `paymentIntentData` (the `transfer_data`) is discarded, so the session is a plain platform charge. Repo-wide search finds no `transfers.create` or `payouts.create`. [settle_remittance](../supabase/migrations/20261020100000_sub_wallets.sql#L358) inserts a credit and a debit of the same amount and **never updates `wallets`**. `deposit_to_wallet` is referenced only by `supabase/dev/*.sql`.
- **Stage note.** In sandbox this is expected prototype behaviour and harms nobody; it is recorded as High because it is the largest gap between what the app *says* and what it *does*, and it must be closed before a live key is used.
- **Impact (once live).** A customer pays USD, the app and ledger say the money was "Sent to X", and nobody receives anything through the system; the platform simply holds the funds. That is a consumer-harm and regulatory exposure (money-transmission rules — get proper advice), a chargeback magnet, and it makes the in-app "balance" meaningless: every real account is ৳0, so `p2p_transfer` and card swaps are unreachable in practice.
- **Fix.** Decide the settlement model and build it before any live key: (a) Stripe Connect transfers to onboarded recipients, (b) a licensed payout partner API for bKash/Nagad/bank, or (c) a funded-wallet model where the webhook calls `deposit_to_wallet` and delivery is `p2p_transfer`. Until then label the flow "demo", and make the server **refuse to start with an `sk_live_` key**.

#### SEC-02 — Saving a contract/visa audit is rejected by the live database  *(confirmed live)*
- **Evidence.** Live `saved_documents.source_engine` has `CHECK (source_engine = ANY (ARRAY['Gemini','On-device MRZ']))`. The backend writes `'OpenRouter AI'` ([documents.ts:85, 692, 747](../backend_service/src/routes/documents.ts#L85)). The base table was created in the dashboard and has no migration in the repo.
- **Impact.** The insert fails; `saveDocument` returns `null`; `/save` answers 502 "Could not save this document to your vault". The product's central loop — scan, read, keep — is broken for contracts and visas. Passports (`On-device MRZ`) and old `Gemini` rows are unaffected, which is why it can go unnoticed.
- **Fix.** Look up the constraint name, then in the dashboard SQL editor (not `db push`): drop it and re-add with `('OpenRouter AI','Gemini','On-device MRZ')`; commit the SQL as a migration. Add an integration test that saves a vision-model result against a disposable database. *(I have not changed the live database; this needs your review and approval.)*

#### SEC-03 — Wallet UI fails open to invented balances, history and contacts
- **Evidence.** [payment_controller.dart:73–112](../lib/frontend/payment/controllers/payment_controller.dart#L73) starts with three cards at ৳50,000 / 25,000 / 10,000. [supabase_payment_repository.dart](../lib/frontend/payment/repository/supabase_payment_repository.dart): `getCards` falls back to the mock on any error/timeout/no session; `getTransactions` and `getBeneficiaries` fall back to the mock when the result is **empty**, i.e. for every new account. The mock holds five fake transactions and four fake contacts ([mock_payment_repository.dart](../lib/frontend/payment/repository/mock_payment_repository.dart)). `PaymentLocalStore` persists mock-modified balances across launches.
- **Impact.** A signed-in user can see money that does not exist (first frame, slow network, outage) and a brand-new account shows other people's names and a "Google subscription" history. In a finance app that is a trust and potentially a legal problem, and it contradicts the project's own "no seed data" rule.
- **Fix.** Remove the seeded initial state; for signed-in users never fall back to the mock — show `Loading / Unavailable / ৳0.00` and an "offline, last updated hh:mm" badge if a *server* snapshot is cached; keep `MockPaymentRepository` for widget tests only; delete the hard-coded `'Talha Tanzim'` name filter in `getWalletHolderName`.

#### SEC-04 — Stripe Connect endpoints have no ownership checks
- **Evidence.** [connect.ts:11, 62, 95](../backend_service/src/routes/connect.ts#L11): `create-account`, `account-link`, `account-status/:accountId` require only a signed-in non-anonymous user (anyone can register). Nothing maps a user to a Stripe account. `account-status` returns `details: account` — the entire Stripe object. [checkout.ts:116](../backend_service/src/routes/checkout.ts#L116) `destination-charge` accepts any `priceId`, `connectedAccountId` and an `applicationFeeAmount` of 0–10,000 from the caller. An account id is already embedded in the app (`acct_1URCKREQ1XrhmDDe`).
- **Impact.** Any registered user can read details of any connected account whose id they know, mint onboarding links for accounts they don't own, create unlimited connected accounts and products on the platform account, and zero the platform fee on a charge.
- **Fix.** Store `stripe_account_id` per user server-side and require `accountId === caller's`; return a minimal projection; remove or admin-gate routes the app does not use (it uses none of `connect/*` or `destination-charge`); never accept `applicationFeeAmount` or arbitrary `priceId` from clients.

#### SEC-05 — Identity documents and questions go to free third-party models; PII stored unencrypted
- **Evidence.** [documents.ts:597–621](../backend_service/src/routes/documents.ts#L597) sends the full photo (passports, visas, contracts) as a base64 data URL to OpenRouter's **free** models (NVIDIA, Google). Prohori sends questions plus FAQ text. Saved rows keep passport numbers, DOB, sponsor, and the whole translated contract as plain `jsonb`/`text` (`identity`, `full_translation`, `translation_segments`). The app has no consent screen for third-party processing and no account/data-deletion flow.
- **Impact.** Free endpoints are commonly offered on terms that allow provider-side logging or use of prompts (*verify per model and per OpenRouter account setting*). For vulnerable workers, a passport scan or a contract leaving the trust boundary is the highest-impact privacy risk in the product. Breach of the database exposes everything at once.
- **Fix.** (1) Verify and set OpenRouter's data policy — request-level `provider.data_collection: "deny"` and the account privacy toggles — and accept that this may exclude most free models; (2) show an explicit consent screen before the first upload; (3) prefer on-device text recognition and send text, not the image, where accuracy allows; (4) for anything real, use a paid zero-retention endpoint or a self-hosted model; (5) encrypt `identity` / `full_translation` / `translation_segments` (Supabase Vault/pgsodium or application-level envelope encryption); (6) add retention limits and a delete-my-data/account flow.

### Medium

#### SEC-06 — Webhook acknowledges a failed booking, so Stripe never retries
- **Evidence.** [webhooks.ts:198–225](../backend_service/src/routes/webhooks.ts#L198): a non-OK response from `settle_remittance` is only logged; a thrown error is logged as "non-fatal"; both paths reach `res.json({ received: true })`. The `P0003` branch prints "MANUAL RECONCILIATION NEEDED" to the console only.
- **Impact.** A transient Supabase outage at delivery time permanently loses the booking (Stripe stops retrying on 200). Harmless today (the ledger is cosmetic, SEC-01) — serious once money is real.
- **Fix.** Return **5xx** for transient failures so Stripe retries for up to three days (the function is idempotent); 2xx only for "booked" or a permanent business refusal. Persist every webhook outcome in a `payment_events` table and alert on any unbooked paid session.

#### SEC-07 — Webhook signature helper has an unsigned fallback
- **Evidence.** [stripeClient.ts:24–41](../backend_service/src/stripeClient.ts#L24): Stripe SDK 23 exposes `parseEventNotification`, not `parseThinEvent`, so this polyfill **is** active, and when `constructEvent` throws its `catch` returns `JSON.parse(raw)` **without verifying anything**. [webhooks.ts:42–54](../backend_service/src/routes/webhooks.ts#L42) then retrieves `thinEvent.id` from Stripe.
- **Impact.** A forged body cannot be credited: snapshot events are accepted only if their signature verifies, and the fallback uses only the `id` for an authenticated Stripe lookup, which fails for invented ids. But any unauthenticated caller can make the server call Stripe with attacker-chosen ids, a replayed real v2 event id is processed, and the helper is one refactor from trusting unverified data. It also contradicts `STRIPE_INTEGRATION_TODO.md` ("verifies the signature").
- **Fix.** Delete the polyfill; verify thin events with `stripe.parseEventNotification(rawBody, signature, secret)` and reject on failure; ideally use separate endpoints (and secrets) for snapshot and thin destinations.

#### SEC-08 — Costly endpoints lack rate limits; anonymous identities are free
- **Evidence.** No `rateLimit` on [documents.ts](../backend_service/src/routes/documents.ts) (`/scan`, `/mrz`, `/save`), `/api/auth/bind-phone`, `session-status`, `/api/rates` (calls Stripe). `/scan` accepts **anonymous** sessions, and anonymous sign-in appears to remain enabled (earlier builds used it and the RLS pentest script depends on it — *verify in the Supabase Auth settings*). One scan can fan out to three LLM calls over 120 s.
- **Impact.** Free-model quota exhaustion → "busy" for every user; Stripe API quota burn; cost explosion if a paid model is configured. Per-user limits are meaningless when identities are free.
- **Fix.** Per-IP and per-user limits on all `/api/documents/*`, `bind-phone`, `rates` (cache 60 s); require a non-anonymous user for `/scan` (the login screen already guarantees one); cap concurrent LLM calls; add CAPTCHA to sign-up; move the limiter to Redis and set `trust proxy` before running more than one instance.

#### SEC-09 — `lookup_recipient` enables name enumeration and accepts anonymous callers
- **Evidence.** [sub_wallets.sql:653](../supabase/migrations/20261020100000_sub_wallets.sql#L653) / [shared_test_phones.sql:303](../supabase/migrations/20261020110000_shared_test_phones.sql#L303): the only identity check is `caller IS NULL`; anonymous users pass; the caller need not have a verified phone; the answer is the account's `full_name`. Limit: 20/min/user.
- **Impact.** An attacker with many free accounts can map phone numbers (Bangladesh and Gulf ranges) to real names — a doxxing and spear-phishing tool against the exact population the app protects.
- **Fix.** Require non-anonymous **and** verified-phone callers; return a masked name (first name + initial); add a per-IP cap and a daily cap; keep responses uniform for "not found".

#### SEC-10 — Tokens and cached identity data sit in plain `SharedPreferences`; no app lock
- **Evidence.** `Supabase.initialize(url, anonKey)` with no custom `LocalStorage` ([main.dart:65](../lib/main.dart#L65)), so the library default is used (verify against the installed version); vault cache with passport fields, wallet mirror and profile phone are `SharedPreferences` JSON. No `flutter_secure_storage`, no `local_auth`, no `FLAG_SECURE` (searched `android/` and `lib/`). The profile screen advertises "Lock the app with your biometrics" but the action is "coming soon".
- **Impact.** On a rooted, debug-built, shared or malware-infected phone, a refresh token and the vault are readable; recents/screenshots can capture documents.
- **Mitigations present.** `allowBackup=false`; logout wipes caches; the balance hides itself after 30 s and when the app leaves the foreground.
- **Fix.** Store the session via Keystore/Keychain (`flutter_secure_storage` + custom `LocalStorage`); encrypt the vault cache with a Keystore-held key; implement the app lock; set `FLAG_SECURE` on scanner/vault/payment screens; consider Play Integrity / App Check for the backend.

#### SEC-11 — Migration ledger, repo and live schema disagree  *(confirmed live)*
- **Evidence.** Live `schema_migrations` lists 9 versions, three of which have no file in the repo. The live schema contains objects from migrations the ledger does not record (`my_phone_status`, `phone_is_shared`, `wallets.card_id`, `rpc_rate_limits`, `faq_embeddings`). `saved_documents` and `beneficiaries` base tables and the function `rls_auto_enable()` exist in no repo migration. [harden_rls_security.sql](../supabase/migrations/20261018130000_harden_rls_security.sql) references the retired columns `balance_bdt`, `sender_id`, `receiver_id` and cannot be replayed. Legacy tables still hold 31 rows of old test data with RLS policies attached.
- **Impact.** Disaster recovery, staging environments and security review all depend on knowing what is deployed; today nobody can prove it.
- **Fix.** Snapshot the live schema (`pg_dump --schema-only`) as a baseline migration; reconcile `schema_migrations` by hand for each applied file; add the missing base-table DDL; delete or archive `harden_rls_security.sql`; export then drop the `*_legacy_20261019` tables; keep the "never `db push`" rule only until the ledger is repaired.

#### SEC-12 — Weak account policy  *(confirmed live)*
- **Evidence.** Supabase advisor `auth_leaked_password_protection` is **disabled**; the app enforces only 6 characters ([auth_widgets.dart:17](../lib/frontend/auth/auth_widgets.dart#L17)); anonymous sign-ins are available; no CAPTCHA or MFA step-up for payments beyond the phone proof.
- **Fix.** Enable the HaveIBeenPwned check; set the minimum to 8–12 *in Supabase* (client checks are advisory); disable anonymous sign-ins once the claim migration is retired; add CAPTCHA to sign-up/reset; require a fresh phone/OTP step-up before `send-money`.

#### SEC-13 — Pricing/accounting inconsistencies and no transaction limits
- **Evidence.** See [CORE_ALGORITHM.md §3.3](CORE_ALGORITHM.md): the VAT is charged but then included in the booked recipient amount (P1); the 2.5 % incentive is displayed but never booked (P2); `USD_TO_BDT = 119.5` is a constant while users see live/baseline rates (P3); there is no minimum, maximum, daily or velocity limit (P4); a missing amount silently prices as ৳100 (P5).
- **Impact.** Disputes, reconciliation errors, and no brake on abuse or on a compromised account. No AML/CTF-style monitoring exists.
- **Fix.** Single canonical rate source shared by display and charge; decide VAT treatment and book it as its own leg; add per-transaction and rolling-24h limits enforced in the database; reject (not default) invalid amounts.

#### SEC-14 — `handle_new_user()` and an unknown `rls_auto_enable()` are callable via the API  *(confirmed live)*
- **Evidence.** Supabase advisors 0028/0029: both `SECURITY DEFINER` functions are executable by `anon` and `authenticated` through `/rest/v1/rpc/…`. `handle_new_user` is a trigger function (a direct RPC call errors), but the repo never revokes it. `rls_auto_enable()` is **not defined in any repo migration**; its body has not been inspected.
- **Fix.** `REVOKE EXECUTE … FROM public, anon, authenticated` on both (triggers do not need caller EXECUTE); read `rls_auto_enable`'s source and confirm it is a harmless event-trigger helper; move helper functions out of the exposed `public` schema.

#### SEC-15 — Release and build hygiene
- Release builds **fall back to the debug signing key** when the keystore is missing ([build.gradle.kts](../android/app/build.gradle.kts)); an unattended build could ship a debug-signed APK.
- With no `BACKEND_URL` define, a release build targets `http://10.0.2.2:3000` (emulator host).
- No obfuscation/symbol-split flags are configured anywhere (no CI to carry them).
- iOS bundle id is still `com.example.probashiGuard`; Android is `com.probashiguard.app`.
- **No CI/CD, no dependency or secret scanning, no deployment definition, no staging.**
- The release keystore and its password sit side by side in `F:\Probashi_Guard_keystore\` (`probashi-guard-release.jks`, `keystore-password.txt` in clear text), on one drive. Losing them means the app can never be updated on Google Play.
- **Fix.** Fail the release build when the keystore is absent; require `BACKEND_URL` in release; add `--obfuscate --split-debug-info`; add CI (analyze, tests, `npm audit`, `flutter pub outdated`, secret scan); move the password to a password manager or CI secret store and back the keystore up in two places; fix the iOS id before first TestFlight upload.

#### SEC-16 — Firebase test-number mode is the default in every build
- **Evidence.** [firebase_phone_verifier.dart:62, 116](../lib/frontend/auth/firebase_phone_verifier.dart#L62): unless built with `--dart-define=ALLOW_REAL_SMS=true`, all builds (debug **and release**) verify through the Identity Toolkit REST route with a dummy `recaptchaToken`, which Firebase honours only for console test numbers (fixed code, no SMS). In production `testPhoneNumbers()` returns `[]`, so a leftover console test number would be treated as an *ordinary unique number* — first account to verify it owns it and receives transfers addressed to it.
- **Impact.** Safe now (it's a test phase); dangerous if launch happens with test numbers still configured, or with the flag forgotten (real users could not verify at all).
- **Fix.** Delete every test number from the Firebase console before launch; make CI build release with `ALLOW_REAL_SMS=true`; enforce Firebase App Check (Play Integrity / DeviceCheck), an SMS region allow-list and budget alerts; fail backend start in production if `FIREBASE_TEST_PHONES` is non-empty.

#### SEC-17 — Security test assets are stale or touch live systems
- `pentest_stripe_arbitrage.ts` posts a **BDT** session and looks for `stripe_payment_id` / `amount_bdt` in the old `transactions` shape; the webhook now refuses non-USD and the table was renamed, so the script falls into its "record not found → PASS" branch and proves nothing.
- `pentest_supabase_rls.ts` signs in anonymously and checks `wallets`; it does not test cross-user access with two real accounts, nor the function grants.
- `server.test.ts` creates real Stripe test-mode connected accounts; `documents.test.ts` imports the live server (may reach OpenRouter/Supabase with a real `.env`); `verify_payment_run_test.dart` writes to the live Supabase project; none of this runs in CI.
- **Fix.** Hermetic tests with mocked Stripe/OpenRouter and a disposable Supabase branch; a webhook test suite for every gate in [CORE_ALGORITHM.md §3.2](CORE_ALGORITHM.md); a two-user RLS/grants test that asserts the matrix in §9; scanner golden set (L9). Run all in CI.

### Low

| ID | Finding | Evidence | Fix |
|---|---|---|---|
| SEC-18 | **Error/log leakage.** Global handler returns `err.message`; routes return Stripe's `error.message`; logs include phone numbers and session ids. | [server.ts:153](../backend_service/src/server.ts#L153), `checkout.ts` catch blocks, `auth.ts` log of user ids | Generic client messages with a request id; redact PII in logs; structured logging. |
| SEC-19 | **Route sprawl and demo endpoints.** The checkout router is mounted at `/api/checkout`, `/api/products` **and** `/api`; `/api/payment/*` returns hard-coded demo cards/balances; `products/create` lets any user create catalogue items. | [server.ts:143–150](../backend_service/src/server.ts#L143), [payment.ts](../backend_service/src/routes/payment.ts) | One prefix per router; delete unused demo and product routes. |
| SEC-20 | **Trigger.dev stub.** Tasks only log; they fire at Checkout **creation** (before payment) and again at the webhook, with no idempotency key; the payload (recipient name/phone) goes to a third-party cloud. | [checkout.ts:334](../backend_service/src/routes/checkout.ts#L334), [paymentTasks.ts](../backend_service/src/trigger/paymentTasks.ts) | Trigger only from the verified webhook; add an idempotency key; minimise payload. |
| SEC-21 | **Origin-derived redirect URLs.** `destination-charge` and `account-link` build success/return URLs from the request `Origin` header. | [checkout.ts:144](../backend_service/src/routes/checkout.ts#L144), [connect.ts:69](../backend_service/src/routes/connect.ts#L69) | Use `DOMAIN` / an allow-list. |
| SEC-22 | **Limiter keying.** `send-money`'s limiter runs *before* auth, so it keys on IP; `trust proxy` is unset (behind a proxy all users share one bucket); in-memory and per process. | [checkout.ts:208](../backend_service/src/routes/checkout.ts#L208), [rateLimit.ts](../backend_service/src/rateLimit.ts) | Run auth first, key on user id; set `trust proxy` correctly; Redis for >1 instance. |
| SEC-23 | **Token scope.** The analysis HMAC covers the analysis but not the client-echoed `image_sha256` and `model`; with no secret in non-production the token is skipped. | [analysisToken.ts](../backend_service/src/analysisToken.ts), [documents.ts:749](../backend_service/src/routes/documents.ts#L749) | Include both in the MAC; set the secret in every environment. |
| SEC-24 | **Phone-token replay window.** A fresh Firebase ID token is not bound to the Supabase account that presents it; valid for 15 minutes. Requires theft of a token in transit. | [auth.ts:27, 87](../backend_service/src/routes/auth.ts#L27) | Shorten to 2–3 minutes; remember used `(sub, auth_time)` pairs. |
| SEC-25 | **Dead deep link and stale docs.** `/success` links `probashiguard://checkout/success`, but only `io.supabase.probashiguard` is registered. `STRIPE_INTEGRATION_TODO.md` lists `automatic_tax`, promo codes, saved cards etc. that `send-money` does not set, and says the webhook verifies signatures (SEC-07). A Dart comment says PDFs are accepted (they are not). | [server.ts:108](../backend_service/src/server.ts#L108), `AndroidManifest.xml`, `Info.plist` | Register the scheme or remove the button; update the docs. |
| SEC-26 | **Prohori content governance.** The FAQ contains domestic-banking and student-finance advice outside the worker persona; there is no grounding check; with no match the model is still called with "(No entry matched)". No tools or secrets are reachable, so impact is a wrong answer, not an action. | [instruction/…english.txt](../instruction/probashi_guard_ai_flow_english.txt), [prohori.ts](../backend_service/src/ai/prohori.ts) | Review and tag FAQ content; short-circuit with a canned answer when retrieval is empty; add disclaimers. |

---

## 5. Live database verification (2026-10-20, metadata only)

| Check | Result |
|---|---|
| Tables in `public` / RLS enabled | 12 / **12** |
| Row counts | profiles 10 · wallets 30 · transactions 8 · saved_documents 10 · beneficiaries 7 · notices 7 · faq_embeddings 78 · payment_methods 0 · anonymous_claims 0 · rpc_rate_limits 0 · legacy 1 + 30 |
| Money/phone/search functions callable by `anon`/`authenticated` | **None** of `deposit_to_wallet`, `settle_remittance`, `bind_verified_phone`, `match_faqs`, `set_my_phone` appear in the advisor findings (✔ consistent with the migrations) |
| Unexpected exposure | `handle_new_user()`, `rls_auto_enable()` (SEC-14) |
| `saved_documents.source_engine` CHECK | allows `Gemini`, `On-device MRZ` only (**SEC-02**) |
| `profiles` has `phone_verified_at`, `phone_is_shared`; `wallets` has `card_id` | ✔ later migrations are live |
| Migration ledger | 9 versions; not in sync (SEC-11) |
| Advisors | 3 × INFO (RLS on, no policy: `anonymous_claims`, `faq_embeddings`, `rpc_rate_limits` — **intended**), WARN: function exposure (SEC-14), policies reachable by the anonymous role on 9 tables (expected: anonymous users carry the `authenticated` role; harmless while all policies are `auth.uid() = user_id`), leaked-password protection off (SEC-12) |

---

## 6. Secrets and configuration checklist (before any production use)

| Item | Where | State |
|---|---|---|
| `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` | `backend_service/.env` | test-mode per project notes; keep out of git ✔; **add boot check against `sk_live_` until SEC-01 is solved** |
| `SUPABASE_SERVICE_ROLE_KEY` | `.env` | server-only ✔; never ship in the app; rotate if `.env` was ever shared |
| `SUPABASE_ACCESS_TOKEN` | listed in `.env.example` | project notes say it now lives only in a user environment variable; remove it from `.env.example` |
| `ANALYSIS_SIGNING_SECRET` | `.env` | **must be set in production** (saving is refused without it); use ≥ 32 random bytes |
| `OPENROUTER_API_KEY` | `.env` | server-only ✔; set provider data policy (SEC-05) |
| `DEV_AUTH_BYPASS*` | `.env` | must be unset in production (boot refuses otherwise ✔) |
| `FIREBASE_TEST_PHONES` | `.env` | must be empty in production (SEC-16); remove test numbers from the console |
| `CORS_ORIGINS`, `DOMAIN`, `NODE_ENV=production` | `.env` | set explicitly; terminate TLS in front of Node |
| Supabase Auth dashboard | console | confirm-email on · OTP templates with `{{ .Token }}` · redirect URLs exact · leaked-password protection on · disable anonymous sign-ins when possible · CAPTCHA |
| Firebase | console | App Check enforced · SMS region allow-list · budget alert · test numbers removed · Android SHA-1/256 (debug, release, **Play App Signing**) |
| Stripe | console | webhook endpoint restricted to the events used · restricted API key instead of the full secret key · radar rules |
| Android keystore | `F:\Probashi_Guard_keystore\` | back up (two locations); move the password out of a plain-text file |

---

## 7. Compliance and privacy notes (not legal advice)

- The app processes **passport and contract data of migrant workers** and plans to move money across borders. Expect obligations around personal-data protection (consent, purpose limitation, retention, deletion), payment-service licensing / agent arrangements, and KYC/AML — in Bangladesh and in each destination country. Resolve SEC-01 and SEC-05 with counsel before launch.
- Card data: the app and database never see a PAN/CVV (Stripe-hosted Checkout; `last4` only), which keeps PCI scope minimal — preserve that.
- No privacy policy, terms, consent record or data-retention schedule exist in the repo.

---

## 8. Hardening roadmap

**Now (any stage — small, high value)**
1. SEC-02 fix the `source_engine` CHECK constraint; add a save-path integration test. Without it the core scan → keep loop is broken for contracts and visas.
2. SEC-03 make the wallet UI fail closed (no seeded balances, history or contacts for a signed-in user).
3. SEC-14 `REVOKE EXECUTE` on `handle_new_user()` and `rls_auto_enable()`; read the latter's source.
4. SEC-11 snapshot the live schema as a baseline migration; reconcile `schema_migrations`; archive `harden_rls_security.sql`.
5. SEC-17 stop running `verify_payment_run_test.dart` / `server.test.ts` against live projects; fix the stale pentest scripts.

**Before any live Stripe key (money path)**
6. SEC-01 decide and build settlement; add an `sk_live_` boot guard meanwhile.
7. SEC-06 return 5xx on transient booking failure; add `payment_events` + alerting.
8. SEC-07 remove the signature fallback; use `parseEventNotification`.
9. SEC-04 lock down or delete the Connect routes; stop trusting client `priceId` / fee.
10. SEC-13 single rate source, VAT leg, per-transaction and daily limits.

**Before real documents**
11. SEC-05 provider data policy + consent + encryption + deletion. Until then, test with specimen or redacted documents.
12. SEC-10 secure session storage, encrypted cache, app lock, `FLAG_SECURE`.

**Before the backend is internet-facing / a public beta**
13. SEC-08 / SEC-09 rate limits, non-anonymous scan, hardened `lookup_recipient`.
14. SEC-12 account policy (and step-up before `send-money`); SEC-16 Firebase production settings.
15. SEC-15 CI/CD, release signing guard, obfuscation, environments (dev / staging / prod), structured logging and alerts; build the scanner golden set (CORE_ALGORITHM L9).
16. Low items SEC-18 – SEC-26.

**Longer term**
- Verify Supabase JWTs locally (asymmetric signing keys) instead of one `/auth/v1/user` round-trip per request.
- Certificate pinning for the payment screens; root/jailbreak signals feeding risk scoring.
- Independent penetration test and a data-protection impact assessment.

---

## 9. Appendix — function privilege matrix (from the migrations, cross-checked with live advisors)

| Function | `anon` | `authenticated` | `service_role` | Purpose |
|---|---|---|---|---|
| `ensure_my_wallet` | – | ✔ | ✔ | open own wallets |
| `internal_transfer` | – | ✔ | ✔ | own-card swap |
| `p2p_transfer` | – | ✔ | ✔ | send to a verified phone (checks not-anonymous, sender verified) |
| `lookup_recipient` | – | ✔ | ✔ | name for a verified phone (**SEC-09**) |
| `my_phone_status` | – | ✔ | ✔ | own verification state |
| `issue_anonymous_claim`, `claim_anonymous_data` | – | ✔ | ✔ | migrate pre-login data |
| `deposit_to_wallet` | – | – | ✔ | the only balance-raising function |
| `settle_remittance` | – | – | ✔ | book a paid Stripe session |
| `bind_verified_phone` | – | – | ✔ | the only way to set `phone_verified_at` |
| `set_my_phone` | – | – | ✔ | legacy; revoked from clients |
| `match_faqs` | – | – | ✔ | RAG search |
| `enforce_rate_limit` | – | – | internal | counter |
| `handle_new_user` | **✔ (unintended)** | **✔ (unintended)** | ✔ | trigger (**SEC-14**) |
| `rls_auto_enable` | **✔ (unintended)** | **✔ (unintended)** | ? | not in repo (**SEC-14**) |

Re-verify any time with:

```sql
select p.proname,
       has_function_privilege('anon',          p.oid, 'EXECUTE') as anon,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authed
from pg_proc p where p.pronamespace = 'public'::regnamespace order by 1;
```

---

## 10. Addendum: second pass, 2026-10-20

A second pass with **executed tests** ([TESTCASES.md](TESTCASES.md): 181 backend tests including a real Postgres running the repo's migrations, 150 new Flutter tests, and a live smoke script). It re-read the backend, the migrations and the app's payment, auth, scanner and profile code, checked the live project with **read-only** queries, and scanned the tracked tree and the full git history for credentials (output masked). No code outside `test/`, `backend_service/src/test/`, `backend_service/scripts/e2e_live_smoke.ts` and `backend_service/package.json` was changed, and nothing was written to a live service.

### 10.1 What the second pass confirmed

| Claim | Evidence |
|---|---|
| Clients cannot write balances or ledger rows; the funding, booking, binding and search functions are backend-only | `DB-G01`–`DB-G06` on the real migrations; re-queried live: `deposit_to_wallet`, `settle_remittance`, `bind_verified_phone`, `set_my_phone`, `enforce_rate_limit`, `match_faqs` are not executable by `anon` or `authenticated`; and the signed-in test login got `42501 permission denied` for the first three (`E2E-07`–`E2E-09`) |
| Money is conserved and every ledger row adds up | `DB-X01`: 300 seeded random operations (swaps, transfers, deposits, bookings, invalid input); the total changes only by deposits and each balance equals the net of its ledger |
| A Firebase proof cannot be forged or replayed | `PHONE-03`, `PHONE-06`, `PHONE-08`: number read from the token, 15-minute window, wrong audience / issuer / key / `alg:none` / HS256 all refused |
| Stripe amounts and payers are not trusted | `PAY-S02`, `PAY-W05` (14 refusal variants), `PAY-W06`, `PAY-W08` |
| The scanner's hard rules beat the model | `DOC-04`–`DOC-08`, `DOC-25` |
| No credential is committed in the current tree; secret files are ignored | tree and history scan; the only hits are the Firebase *web* key (public by design) and the webhook secret in SEC-27 |

### 10.2 Still open from the first pass, re-checked

- **SEC-02** is **still true live**: `saved_documents_source_engine_check` allows only `Gemini` and `On-device MRZ`, and the table holds 0 rows with `OpenRouter AI`. The core scan → keep loop is broken for contracts and visas.
- **SEC-08 / SEC-09 / SEC-12**: 27 of the 36 accounts on the project are anonymous, so anonymous sign-in is evidently still enabled. `lookup_recipient` still accepts them (`DB-L05`).
- **SEC-11**: the live migration ledger still lists 9 versions. New detail: a database cannot be built from the repo's migrations (`harden_rls_security.sql` needs the retired `wallets` table; `fix_rls_saved_documents_notices.sql` needs `saved_documents`), and `p2p_core.sql`, which says "safe to run more than once", fails when re-run after `sub_wallets.sql` (`DB-M02`, `DB-M03`). Replaying the unrecorded files from `verified_phone_gate` onward, which is what a `db push` would do, does reach the same working state (`DB-M01`).
- **SEC-17**: partly addressed. Hermetic suites now cover the webhook, `send-money`, `session-status`, phone binding, the scanner and the SQL. `server.test.ts` (creates a real Stripe test account per run) and `verify_payment_run_test.dart` (writes to the live database) are unchanged.

### 10.3 New findings

| Sev | ID | Title | Gate |
|---|---|---|---|
| Medium | SEC-27 | Webhook signing secret is in public git history and still configured locally | Live money |
| Low | SEC-28 | The verified-phone backstop in the funding functions was dropped; the docs still describe it | Live money |
| Medium | SEC-29 | The send form gates on wallet balance that a send never spends | **Now** |
| Low | SEC-30 | A scan with no `save` field stores the document | Real documents |
| Low | SEC-31 | A signed scan result can be saved repeatedly | Public |
| Low | SEC-32 | `/api/documents/mrz` needs no session and accepts impossible dates | Public |
| Medium | SEC-33 | Silent fallbacks in money code: recipient, connected account, session id | Live money |
| Medium | SEC-34 | "complete" is treated as "paid"; delayed payments are never booked | Live money |
| Low | SEC-35 | Recipient search ignores Bengali digits | Public |
| Low | SEC-36 | Dev tooling and stale secrets shipped with the app and `.env` | Public |
| Low | SEC-37 | The success dialog prints the taka sign for every currency | **Now** |

#### SEC-27: webhook signing secret is in public git history and still configured locally
- **Evidence.** Commit `60218e8` ("Save local progress before sync") added `process.env.STRIPE_WEBHOOK_SECRET || 'whsec_cbb9…'` to `backend_service/scripts/pentest_stripe_arbitrage.ts`; it is on `origin/main` and `origin/talha` (`github.com/talhatanzim2005/Probashi_guard`; earlier notes record that repository as public, which I could not re-check from here). A programmatic comparison (nothing printed) shows `backend_service/.env`'s `STRIPE_WEBHOOK_SECRET` is **identical** to that historical value; the file was last saved 2026-10-20 14:32. If the secret was rotated in the Stripe dashboard afterwards, the new value has not been written to this file (or is an unsaved editor change).
- **Impact.** Anyone who can read the repository history can sign a `checkout.session.completed` event the server accepts. The price-consistency gates and the database limit the damage today (a forged event can only plant ledger history rows for a payer id the attacker already knows; `settle_remittance` never changes a balance), which is why this is Medium and not High. It becomes High if booking ever raises a balance (SEC-01).
- **Fix.** Create a new endpoint secret in Stripe and write it to `.env`; delete the default from the script (read the variable and fail if it is absent); treat the old value as public forever, since history is not scrubbed unless you rewrite it.

#### SEC-28: the verified-phone backstop was dropped
- **Evidence.** [verified_phone_gate.sql](../supabase/migrations/20261019170000_verified_phone_gate.sql) made `deposit_to_wallet` raise `P0003` for an account with no verified phone. [sub_wallets.sql](../supabase/migrations/20261020100000_sub_wallets.sql) redefined `deposit_to_wallet` and added `settle_remittance` without it; the live function bodies contain no `P0003`. [webhooks.ts:204](../backend_service/src/routes/webhooks.ts#L204) still has a branch for it (dead code), and §3.3 of this document described it.
- **Impact.** The only remaining check that an unverified account cannot be credited is the one at Checkout creation. If that gate is ever bypassed, or its database read ever fails open, a paid session books regardless. Nothing is wrong today; the second line of defence is gone.
- **Fix.** Restore the check in both functions (keep the replay-before-gate order the earlier version used). `DB-R07` then passes.

#### SEC-29: the send form gates on a balance a send never spends
- **Evidence.** [send_amount_step.dart:177](../lib/frontend/payment/flows/send_amount_step.dart#L177) refuses when the typed amount plus VAT exceeds the selected **wallet** card's balance. The money is taken by Stripe from the person's own card on its hosted page, and `settle_remittance` credits and debits the same amount, so the wallet is never reduced.
- **Impact.** A brand-new account (0.00 on every card, by design) cannot start a send at all, and an account with a funded wallet is asked to hold money it will not spend. The balance check and the settlement model contradict each other; this is the user-visible face of SEC-01.
- **Fix.** Decide the settlement model (SEC-01). If the sender pays by card, drop the wallet-balance check; if the wallet funds the send, make `settle_remittance` debit it. Tests: `send_amount_step_test` (pinned) and `DB-R01`.

#### SEC-30: a scan with no `save` field stores the document
- **Evidence.** [documents.ts:694, 786](../backend_service/src/routes/documents.ts#L694): `req.body?.save !== false` saves. The README's design rule says a scan **never** saves itself. The app always sends `save: false`, so only other clients are affected.
- **Impact.** A script, an older build or a mis-written client puts a passport or contract in the vault without the person choosing it. Privacy-relevant for exactly the data SEC-05 worries about.
- **Fix.** Save only when `save === true`. `DOC-17`.

#### SEC-31 and SEC-32: replayable save token; `/mrz` validation
- **SEC-31.** The analysis token is an HMAC with a 30-minute expiry but is not single-use, so replaying one stores duplicate rows (`DOC-26`). Fix: remember a used `(user, token)` or key the vault row on `image_sha256`.
- **SEC-32.** `/api/documents/mrz` has no auth check (the README table says *session*), and `Date.parse` rolls `2030-02-31` into March, so impossible expiry dates are accepted and echoed into the summary (`DOC-31`, `DOC-32`). Fix: require a session; validate the calendar date.

#### SEC-33: silent fallbacks in money code
- **Evidence.** A missing recipient phone becomes `+8801700000000` in [checkout.ts:274](../backend_service/src/routes/checkout.ts#L274), [webhooks.ts:124](../backend_service/src/routes/webhooks.ts#L124), [stripe_payment_repository.dart:136](../lib/frontend/payment/repository/stripe_payment_repository.dart#L136) and [supabase_payment_repository.dart:276](../lib/frontend/payment/repository/supabase_payment_repository.dart#L276) (the first Firebase test number). The app sends a hard-coded `acct_1URCKREQ1XrhmDDe` when no connected account is given. When the server's answer has no session id the app invents `cs_<milliseconds>`, which `session-status` can never find, so a payment that was made reads as "not completed".
- **Impact.** In production a recipient could silently be a placeholder, and a missing id turns a real payment into an apparent failure. All three hide an upstream bug instead of surfacing it.
- **Fix.** Reject the request (server) and throw (app) when a recipient phone or a session id is missing; remove the default account. `PAY-S13`, `send_money_contract_test`.

#### SEC-34: "complete" is treated as "paid"
- **Evidence.** [checkout.ts:196](../backend_service/src/routes/checkout.ts#L196) `is_paid = payment_status === 'paid' || status === 'complete'`; the app repeats the same test. The webhook books only `payment_status === 'paid'` and does not handle `checkout.session.async_payment_succeeded`.
- **Impact.** With a delayed payment method (bank debit, voucher) a session is `complete` but `unpaid`: the app shows "Remittance Successful!", the webhook declines to book, and the later success event is ignored. Card-only sandbox testing never shows this.
- **Fix.** `is_paid` only for `payment_status === 'paid'`; handle `async_payment_succeeded` (book) and `async_payment_failed` (mark failed). `PAY-T06`, `PAY-W12`, and the skipped test in `send_money_contract_test`.

#### SEC-35, SEC-36, SEC-37: smaller items
- **SEC-35.** `PhoneSearchHelper` does not normalise Bengali digits, unlike the sign-in code field (`BanglaDigitsFormatter`); the app is Bangla-first.
- **SEC-36.** `flutter_skill` (an AI-agent test bridge) is listed under `dependencies` in `pubspec.yaml` and imported nowhere; it ships in release builds and should be a `dev_dependency` or removed. `backend_service/.env` still defines `GEMINI_API_KEY` and `GEMINI_MODEL`, which no code reads since the move to OpenRouter; delete the variables and revoke that key.
- **SEC-37.** [send_flow_view.dart:267](../lib/frontend/payment/flows/send_flow_view.dart#L267) builds the success message with a literal `৳` even when the recipient is paid in riyals or dirhams.

### 10.4 Corrections to the text above

- §3.3 item 3: the `P0003` backstop is no longer in the deposit function (SEC-28). (Corrected in place.)
- `docs/README.md` says `/api/documents/scan` accepts "one PDF"; the route refuses PDFs. It lists `/mrz` as needing a session; it does not (SEC-32). Its "no seed data" claim is true of the database and false of the app (SEC-03). It says nobody signs in anonymously; the live project has 27 anonymous accounts.
- `supabase/dev/seed_test_funds.sql` binds the receiver to `+8801700000001`, a Firebase test number. Test numbers are shared everywhere else and can never receive a transfer, so use a non-test number for a receiver you want to pay.
