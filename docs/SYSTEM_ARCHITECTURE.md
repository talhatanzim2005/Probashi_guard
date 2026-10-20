# Probashi Guard — System Architecture

| | |
|---|---|
| **Audit snapshot** | 2026-10-20 · branch `talha` · commit `f125438` · app version `1.0.0+1` |
| **Stage** | Prototype; Stripe in **sandbox (test mode)**. "Not implemented" items below (payout, wallet funding) are expected at this stage; they are the work needed before going live. |
| **Companion documents** | [CORE_ALGORITHM.md](CORE_ALGORITHM.md) · [SECURITY_DESIGN.md](SECURITY_DESIGN.md) |
| **Evidence basis** | Every source file under `lib/`, `backend_service/src/`, `supabase/` and the Android/iOS config was read. `tsc --noEmit` and `flutter analyze` were run (both clean). The five offline backend test suites were run (43/43 pass). Live Supabase was inspected **metadata only** (table list, migration ledger, security advisors) — no row data was read. |
| **Not verified** | Stripe dashboard, Firebase console, Supabase Auth settings, OpenRouter account settings, any deployed environment (none exists in the repo). |

---

## 1. What the system is

Probashi Guard is a bilingual (Bangla / English) mobile app that protects Bangladeshi migrant workers and the families who depend on them. It does three jobs:

| Pillar | What the worker gets | Main code |
|---|---|---|
| **Fraud Checker** | Photograph a contract / visa / loan paper, get a plain-language audit, a translation and a *sign / don't sign* verdict. Passports are read on the phone from their MRZ. | `lib/frontend/documents/`, `backend_service/src/routes/documents.ts`, `src/documents/` |
| **Payment wallet** | Three card-style wallets, card-to-card swaps, and a "send money home" flow that collects payment through Stripe Checkout. | `lib/frontend/payment/`, `backend_service/src/routes/checkout.ts`, `webhooks.ts`, `supabase/migrations/` |
| **Prohori (প্রহরী)** | An AI assistant that answers from a curated FAQ knowledge base (retrieval-augmented generation), plus a news notice feed and a pre-departure checklist. | `lib/frontend/prohori/`, `backend_service/src/routes/chat.ts`, `src/ai/` |

Identity is Supabase Auth. Firebase is used for exactly one thing: proving a phone number over SMS.

---

## 2. System context

```
                       ┌───────────────────────────────────────────┐
   Migrant worker ───► │   Flutter app  (Android · iOS · Web)       │
   Family in BD        │   Bangla / English · local cache           │
                       └───┬──────────────┬────────────┬───────────┘
                           │              │            │
      direct, anon key     │              │ HTTPS      │ SMS proof (Firebase SDK or
      + user JWT, RLS      │              │ Bearer JWT │ Identity Toolkit REST)
      (reads, 2 RPCs)      │              │            ▼
                           ▼              ▼       ┌──────────┐
                  ┌────────────────┐  ┌──────────────────────┐   Firebase
                  │   Supabase     │◄─┤  backend_service     │   Phone Auth
                  │ Auth · Postgres│  │  Node 24 · Express 5 │   (proof only)
                  │ pgvector · RLS │  │  service-role key    │
                  └────────────────┘  └─┬───────┬──────┬─────┘
                                        │       │      │
              ┌─────────────────────────┘       │      └──────────────┐
              ▼                                 ▼                     ▼
        ┌───────────┐                    ┌─────────────┐      ┌───────────────┐
        │  Stripe   │  hosted Checkout   │ OpenRouter  │      │  Trigger.dev  │
        │ + webhook │◄── opened in the   │ free LLMs   │      │ (log-only     │
        └───────────┘    phone browser   └─────────────┘      │  stub tasks)  │
                                                              └───────────────┘
        Also: Google JWKS (verify Firebase tokens) · Hugging Face hub (one-time
        embedding-model download) · news sites (notice seeder, run by hand)
```

The app talks to **two** backends: Supabase directly (for data the user owns, protected by Row Level Security) and `backend_service` (for anything that needs a secret: Stripe, the LLM key, the service-role key).

---

## 3. Technology stack

| Layer | Technology | Version (from manifests) |
|---|---|---|
| Client | Flutter / Dart | Dart SDK `^3.12.2`; app `1.0.0+1` |
| Client state | `ChangeNotifier` singletons + `ValueNotifier` | — (no state-management package) |
| Client data | `supabase_flutter`, `http`, `shared_preferences` | `^2.8.0`, `^1.2.2`, `^2.5.6` |
| Client device | `camera`, `image_picker`, `passport_scanner`, `mrz_parser`, `permission_handler` | `^0.12.1`, `^1.2.4`, `^1.1.1`, `^2.0.1`, **pinned `^12.0.3`** |
| Client auth | `firebase_core` / `firebase_auth` (phone only), `url_launcher` | `^5.0.0` / `^7.0.0`, `^6.3.3` |
| Backend | Node.js, TypeScript, Express | TS `^5.9.3`, Express `^5.3.0`; Trigger runtime `node-24` |
| Payments | `stripe` | `^23.0.0` |
| AI | `openai` SDK → OpenRouter; `@huggingface/transformers` (local ONNX) | `^7.39.0`; `^4.3.1` |
| Token checks | `jose` (Firebase RS256 / JWKS) | `^6.2.12` |
| Background jobs | `@trigger.dev/sdk` | `4.7.4` |
| Database | Supabase Postgres + `pgvector` (`vector(384)`) | project `xfwxiawapksepskcevwe` |

`permission_handler` must stay on 12.x: 13.x needs Android `compileSdk 37`, and the project's AGP stops at 36.

---

## 4. Components

### 4.1 Flutter client

**Layering.** `View (StatefulWidget)` → `Controller (ChangeNotifier singleton)` → `Repository (interface + implementations)` → Supabase / HTTP.

```
lib/
├── main.dart                 boot sequence + MainNavigationShell (4 tabs + drawer)
├── config/backend_config.dart   one place that decides where backend_service is
├── l10n/                     AppStrings (every UI string is _p(english, bangla)),
│                             LanguageController (locale; persisted)
├── theme/ widget/            4-colour palette, app bar, bottom nav, shared widgets
└── frontend/
    ├── auth/        login · register · email-OTP · forgot password · phone setup
    │                auth_session.dart = goToApp / signOut / anonymous-data claim
    ├── home/        dashboard, in-app search registry
    ├── payment/     controllers · repositories · models · send flow · wallet widgets
    ├── documents/   scan view (camera/MRZ) · result view · vault · repository
    ├── prohori/     chat view + repository
    ├── notice/      news feed (read-only from Supabase)
    ├── profile/ crChecker/ menu/ splash/ Complaint/
```

Empty placeholders: `lib/backend/`, `lib/database/`. `lib/splash_view.dart` is only a re-export of `lib/frontend/splash/splash_view.dart`, kept so `main.dart` has a short import.

**Payment repositories** — three implementations behind one interface (`PaymentRepository`):

| Implementation | Role |
|---|---|
| `SupabasePaymentRepository` | **Default.** Reads `wallets` / `transactions` / `beneficiaries` from Supabase (RLS), calls `internal_transfer`, talks to `/api/checkout/*`. Falls back to the mock when a read fails or comes back empty. |
| `StripePaymentRepository` | Older HTTP-only variant that reads `/api/payment/*` (hard-coded demo data on the server). Not the default. |
| `MockPaymentRepository` | Seeded data (cards ৳50,000 / 25,000 / 10,000, five fake transactions, four fake contacts). Used as the offline fallback. See finding **SEC-03**. |

**Startup (`main()`).** Load saved language → load checklist, profile, payment cache in parallel → `Supabase.initialize` (failure is non-fatal) → `Firebase.initializeApp` (failure is non-fatal; phone proof then reports "not configured") → `runApp`.

**Navigation.**

```
SplashView ─ signed-in account? ──yes──► goToApp()
     │no                                    │ redeem anonymous claim · ensure_my_wallet
     ▼                                      │ phone on profile?
LoginView ⇄ RegisterView → OTP code         ├─no──► PhoneSetupView (skippable) ─┐
   │  (email+password · Google · GitHub)    └─yes─────────────────────────────┐ │
   └──────────────► goToApp() ─────────────────────────────────────────────────▼▼
                                MainNavigationShell
              tabs:  0 Home · 1 Payment · 2 Scan (full-bleed) · 3 Notice
              drawer: Prohori · Saved documents · Fraud checker (→ tab 2) · Logout …
              pushed: Profile · Search · Prohori chat · Saved documents
```

**Data kept on the device** (all in `SharedPreferences` — plain storage, not Keystore/Keychain):

| Key | Content | Cleared on logout |
|---|---|---|
| Supabase session | access + refresh token (library default storage) | yes (`auth.signOut`) |
| `app_language_code` | `bn` / `en` | **no** (kept on purpose) |
| `profile_user_name`, `profile_phone_number`, `profile_biometric_enabled` | profile mirror | yes |
| `predeparture_checklist_v1` | checklist ticks | yes |
| `payment_card_balances_v1`, `payment_transactions_v1`, `payment_added_beneficiaries_v1` | wallet mirror (offline fallback) | yes |
| `saved_documents_cache_v1` | up to 50 vault rows incl. passport fields + translations | yes |
| `auth_anonymous_claim_token` | one-time token to migrate pre-login data | yes |
| `probashi_recent_search_ids` | recent in-app searches | no |

Passport photos taken by the on-device scanner are deleted from the temp folder after reading (`_deletePassportImage`). Contract/visa photos are held in memory and sent to the backend; the backend does **not** persist images (only a SHA-256 of them).

**Backend address.** `BackendConfig.baseUrl`: `--dart-define=BACKEND_URL=…` if set; else `http://localhost:3000` (web), `http://10.0.2.2:3000` (Android emulator), `http://localhost:3000` otherwise. A release build with no define silently points at the emulator host. Android debug builds allow cleartext; release builds do not.

### 4.2 Backend service (`backend_service/`)

Single Node process, entry `src/server.ts`, default port 3000. **Middleware order matters:**

1. `cors` — native apps send no `Origin` and are not affected; browsers need an origin in `CORS_ORIGINS` (any `localhost` port is allowed outside production).
2. `/api/documents` router (mounted *before* global parsers; has its own 20 MB JSON parser and a friendly 413).
3. `/api/chat` router (own 16 KB parser).
4. `express.raw` on `/api/webhooks/stripe` — Stripe signs exact bytes, so the webhook must see the raw buffer.
5. Global `express.json` (2 MB, keeps `rawBody`) and `urlencoded`.
6. Routes, then a global error handler (500 + `err.message`).

**Route table**

| Route | Auth required | Rate limit | Purpose | Downstream |
|---|---|---|---|---|
| `GET /api/health` | none | none | liveness | — |
| `GET /api/rates` | none | none | BDT exchange rates (Stripe if available, else baseline table) | Stripe |
| `GET /success`, `/cancel` | none | none | post-Checkout landing pages | — |
| `POST /api/documents/scan` (alias `/analyze`) | any Supabase session, **anonymous allowed** | **none** | vision-model audit of 1–10 photos | OpenRouter, Supabase |
| `POST /api/documents/mrz` | optional session | **none** | validate on-device passport fields | Supabase (only if saving) |
| `POST /api/documents/save` | any session + signed token | none | persist a reviewed audit | Supabase |
| `POST /api/chat` | **non-anonymous** | 12 / min / user | Prohori answer | local embedder, Supabase RPC, OpenRouter |
| `POST /api/auth/bind-phone` | non-anonymous Supabase JWT **+** Firebase ID token | none | bind a *proven* phone | Google JWKS, Supabase RPC |
| `POST /api/checkout/send-money` | non-anonymous **+ verified phone** | 20 / min **per IP** | open a USD Checkout session | Stripe, Supabase read |
| `GET /api/checkout/session-status/:id` | non-anonymous, **session owner only** | none | paid? | Stripe |
| `POST /api/checkout/destination-charge` | non-anonymous | 30 / min / user | generic Connect checkout | Stripe |
| `POST /api/products/create` | non-anonymous | 30 / min / user | create product + price | Stripe |
| `POST /api/connect/create-account`, `/account-link`; `GET /account-status/:id` | non-anonymous | none | Stripe Connect v2 onboarding | Stripe |
| `GET /api/payment/{cards,beneficiaries,transactions}` | non-anonymous | none | **hard-coded demo data** | — |
| `POST /api/webhooks/stripe` | Stripe signature | none | book paid remittances | Stripe, Supabase (service role) |

The whole checkout router is mounted three times (`/api/checkout`, `/api/products`, `/api`), so each of its routes is reachable under three prefixes.

**Modules**

| Module | Responsibility |
|---|---|
| `supabaseUser.ts` | `resolveCaller()` validates the bearer token by asking Supabase (`/auth/v1/user`); `requireAuth` rejects anonymous accounts; `hasVerifiedPhone()`; gated developer bypass (`DEV_AUTH_BYPASS`, refused at boot in production). |
| `rateLimit.ts` | In-memory fixed-window limiter (per process). |
| `pricing.ts` | `USD_TO_BDT = 119.5`, `VAT_ON_COMMISSION_RATE = 0.0001`, 50-cent floor, card-id whitelist. Shared by Checkout and the webhook. |
| `analysisToken.ts` | HMAC token that binds a saved audit to the user, language and exact content. |
| `documents/fraudRules.ts` | Deterministic Tip Shoi and salary rules (multilingual regexes, SAR conversion table). |
| `documents/identity.ts` | Passport MRZ validation, expiry classification, synthetic audit for passports. |
| `ai/openrouter.ts` | One OpenRouter client + ordered model fallback. |
| `ai/embeddings.ts`, `faqParser.ts`, `faqStore.ts`, `prohori.ts` | Local multilingual embeddings, FAQ chunking, pgvector access, prompt + sanitiser. |
| `stripeClient.ts`, `stripeConnect.ts` | Stripe client (with a local `parseThinEvent` polyfill); destination-account vetting. |
| `testPhones.ts` | Firebase test-number pool (non-production only). |
| `trigger/paymentTasks.ts` | Two **log-only** Trigger.dev tasks (notification, reconciliation). |

**Configuration (`.env`, names only):** `PORT`, `DOMAIN`, `NODE_ENV`, `CORS_ORIGINS`; `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_TEST_ACCOUNT_ID`; `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ACCESS_TOKEN`; `OPENROUTER_API_KEY`, `OPENROUTER_BASE_URL`, `DOCUMENT_MODELS`, `CHAT_MODELS`, `DOCUMENT_MAX_TOKENS`; `EMBEDDING_MODEL`, `FAQ_MATCH_THRESHOLD`, `TRANSFORMERS_CACHE_DIR`; `FIREBASE_PROJECT_ID`, `FIREBASE_TEST_PHONES`; `ANALYSIS_SIGNING_SECRET`; `TRIGGER_SECRET_KEY`; `DEV_AUTH_BYPASS*`. `.env` is git-ignored; `.env.example` is tracked.

### 4.3 Data tier (Supabase)

**Auth.** Email + password (with a 6-digit email code for sign-up and password reset), Google and GitHub OAuth (PKCE is the `supabase_flutter` v2 default), and legacy anonymous sessions. The backend validates tokens by calling Supabase, not by checking signatures locally.

**Live schema** (12 tables in `public`, all with RLS enabled — verified 2026-10-20):

| Table | Purpose | Written by | Read by | Rows (live) |
|---|---|---|---|---|
| `profiles` | identity + the **phone a transfer is addressed to**; `phone_verified_at`, `phone_is_shared` | trigger `handle_new_user`; `bind_verified_phone` (service role); client may update `full_name`, `avatar_url` only | owner | 10 |
| `wallets` | **one row per (user, card)**; `balance numeric(14,2) CHECK ≥ 0` | SECURITY DEFINER functions only | owner | 30 |
| `transactions` | double-entry ledger; each leg stores `balance_before/after`, `reference`, `idempotency_key`, `card_id` | SECURITY DEFINER functions only | owner | 8 |
| `payment_methods` | card/bank metadata (`last4` CHECK `^[0-9]{4}$`; **no PAN/CVV column by design**) | owner (RLS) | owner | 0 — and no app code uses it |
| `saved_documents` | audit vault (identity, salary, fees, Tip Shoi findings, verdict, translation) | `backend_service` (service role) only | owner | 10 |
| `beneficiaries` | saved recipients (created in the dashboard; no migration in repo) | owner (RLS `FOR ALL`) | owner | 7 |
| `notices` | news feed (Open Graph scrape) | seeder (service role) | everyone | 7 |
| `faq_embeddings` | Prohori knowledge base, `vector(384)` + `embedding_model` | seeder (service role) | `match_faqs` (service role) | 78 (39 × 2 languages) |
| `anonymous_claims` | one-time tokens to move pre-login data | RPC functions | — | 0 |
| `rpc_rate_limits` | per-user counters for `lookup_recipient` | `enforce_rate_limit` | — | 0 |
| `wallets_legacy_20261019`, `transactions_legacy_20261019` | pre-P2P test data, renamed not dropped; client grants revoked | — | — | 1 / 30 |

```
auth.users 1──1 profiles 1──* wallets (one per card_id: card_wps | card_probashi | card_visa)
    │                                  │
    ├──* transactions ──(reference)──► paired legs: debit + credit share one reference
    │       └─ payment_method_id ─► payment_methods
    ├──* saved_documents        ├──* beneficiaries        └──* anonymous_claims
faq_embeddings, notices, rpc_rate_limits: standalone
```

**Server-side functions** (all `SECURITY DEFINER`, `search_path = public`):

| Function | Callable by | What it does |
|---|---|---|
| `ensure_my_wallet()` | authenticated | opens the three card wallets for the caller |
| `internal_transfer(from, to, amount, key)` | authenticated | moves the *caller's own* money between their cards, atomically |
| `p2p_transfer(phone, amount, desc, key)` | authenticated | moves money from the caller's `card_wps` to another account's, addressed by **verified** phone. *No app screen calls it.* |
| `lookup_recipient(phone)` | authenticated | name for a verified phone; 20 calls/min |
| `my_phone_status()` | authenticated | own phone + verified flag (unused by the app) |
| `issue_anonymous_claim()` / `claim_anonymous_data(token)` | authenticated | migrate documents + contacts from an old anonymous session |
| `deposit_to_wallet(...)` | **service_role only** | the only function that can *raise* a balance |
| `settle_remittance(...)` | **service_role only** | books a paid Stripe remittance as two ledger legs (net balance change: none) |
| `bind_verified_phone(...)` | **service_role only** | the only way to set `phone_verified_at` |
| `match_faqs(vector, threshold, k)` | **service_role only** | cosine search over FAQ embeddings |
| `enforce_rate_limit(...)` | none (internal) | fixed-window counter |
| `handle_new_user()` | trigger | profile + three zero wallets on sign-up |

**The security model of the money tables is the grants, not the application:** `authenticated` holds only `SELECT` on `wallets` and `transactions`; no `INSERT/UPDATE/DELETE` exists to be abused. See [SECURITY_DESIGN.md](SECURITY_DESIGN.md).

**Migrations.** Fourteen files in `supabase/migrations/`; the project rule is **never `supabase db push`** (history has drifted). Files are applied through the dashboard SQL editor.

| State | Files |
|---|---|
| Recorded in the live `schema_migrations` (9) | `create_saved_documents`, `saved_documents_translation_segments`, `transactions_strict_sender_privacy` (these three have **no file in the repo**), `fix_rls_saved_documents_notices`, `revoke_client_references_trigger`, `wallet_deposit` (recorded under `20261019073544`, repo file is `…160000`), `claim_anonymous_data`, `p2p_core`, `tighten_client_grants` |
| **Live schema contains them, but the ledger does not record them** | `verified_phone_gate` (`my_phone_status` exists), `sub_wallets` (30 wallet rows = 10 users × 3; `rpc_rate_limits` exists), `shared_test_phones` (`phone_is_shared` column exists), `faq_embeddings` (table + 78 rows), `create_notices` (table + 7 rows), `enforce_rls_all_tables` (all 12 tables have RLS) |
| In the repo, cannot be replayed | `harden_rls_security` — references the legacy columns `balance_bdt`, `sender_id`, `receiver_id`; superseded by `p2p_core` |
| Not in any migration | `saved_documents`, `beneficiaries` base tables; `public.rls_auto_enable()` function |

So the repo cannot rebuild the database from scratch, and `schema_migrations` is not a reliable record of what is deployed.

### 4.4 External services

| Service | Used for | Called by | Data that leaves the system | If it is down |
|---|---|---|---|---|
| **Supabase** | auth, data, vector search | app (RLS) and backend (service role) | everything the app stores | login and vault fail; wallet falls back to the mock (see SEC-03) |
| **Stripe** | USD Checkout, webhook, exchange rates, Connect | backend; the phone's browser | amount, recipient name/phone (in metadata), payer email | send-money returns an error; rates fall back to a baseline table |
| **OpenRouter** (free models) | document audit, Prohori answers | backend | **contract/visa/ID photos**, chat questions + retrieved FAQ text | scan → 502/503/504; Prohori → 503 |
| **Firebase Phone Auth** | SMS proof of a phone | app | phone number | phone proof reports "not configured"; account still usable without money movement |
| **Google JWKS** | verify Firebase ID tokens | backend (cached by `jose`) | none | bind-phone fails |
| **Trigger.dev** | async notification / reconciliation tasks | backend | recipient name + phone, amounts | non-fatal; tasks are stubs |
| **Hugging Face hub** | embedding model download (≈120 MB, once) | backend on first start | none | Prohori unavailable until downloaded |
| News sites | notice seeder (manual) | `npm run seed:notices` | none | feed not refreshed |

---

## 5. Key runtime flows

### 5.1 Sign-in and first run
1. Splash checks for a non-anonymous Supabase session. If present → `goToApp()`.
2. Otherwise Login/Register (email + password, email OTP for sign-up, Google/GitHub via browser and the `io.supabase.probashiguard://login-callback/` deep link).
3. `prepareSignIn()` mints a one-time claim token if the phone still holds an old anonymous session; `goToApp()` redeems it (`claim_anonymous_data`), calls `ensure_my_wallet()`, and reads `profiles.phone`.
4. No phone → `PhoneSetupView` (skippable). Skipping costs only the ability to move money.

### 5.2 Proving a phone number
```
App ── Firebase: send SMS code ──► (test-number REST route by default; real SMS needs
 │                                  --dart-define=ALLOW_REAL_SMS=true + Blaze billing)
 │◄─ code typed by user
 ├── Firebase: confirm ──► Firebase ID token (RS256, contains phone_number)
 └── POST /api/auth/bind-phone   Authorization: Bearer <Supabase JWT>
                                 { firebaseIdToken }
        backend: Supabase JWT → user id (non-anonymous)
                 jose.jwtVerify(RS256, issuer, audience) → phone_number claim, auth_time ≤ 15 min
                 rpc bind_verified_phone(user, phone, shared?, cap)   [service role]
```
The phone number comes from the verified token, never the request body.

### 5.3 Document scan → review → save
```
Contract/visa:  camera/gallery photo ─► POST /scan {filesBase64, language, save:false}
                   backend: validate → LLM audit (model chain) → normalise → rules → verdict
                   ◄─ { analysis, report, analysis_token(30 min) }       NOTHING STORED YET
                worker reads audit ─► "Save to vault" ─► POST /save {analysis, analysis_token}
                   backend: verify HMAC → re-normalise → insert (service role)
Passport:       on-device ML Kit reads MRZ ─► POST /mrz {fields} ─► same review/save path
Vault:          app reads saved_documents directly (RLS); keeps a 50-row offline cache
```
A scan is never saved automatically — that is a product decision. **Known live defect:** the `saved_documents.source_engine` CHECK allows only `'Gemini'` and `'On-device MRZ'`, but the backend writes `'OpenRouter AI'` for contract/visa audits, so the insert is rejected and *Save to vault* fails for those documents (SEC-02).

### 5.4 Sending money (remittance)
```
App                       backend_service                 Stripe                Supabase
 │ POST /send-money ─────►│ resolve payer (JWT) ──────────────────────────────► /auth/v1/user
 │  (amountBdt, card…)    │ phone verified? ──────────────────────────────────► profiles
 │                        │ usdCents = f(amountBdt)  (server-side, §CORE 3)
 │                        │ sessions.create(USD, metadata{payerUserId,cardId,…}) ─►
 │◄── checkoutUrl ───────│
 │ open browser ──────────┼─────────────────────────────────►│ customer pays
 │ poll session-status ──►│ retrieve; owner check ─────────►│
 │                        │◄──── checkout.session.completed (signed) ─┤
 │                        │ verify signature; kind=remittance; paid; USD; card id;
 │                        │ amount_total == f(metadata.amountBdt) ±1¢
 │                        │ rpc settle_remittance(payer, card, session_id, bdt…) ─► ledger (2 legs)
 │ refresh wallet ────────┼──────────────────────────────────────────────────► RLS read
```
What this flow does **not** do: pay anyone. The Checkout session is a plain platform charge (the connected-account result is verified, recorded in metadata, and discarded), and no code calls `transfers.create` or `payouts.create`. The recipient is a label on a ledger row. See SEC-01.

### 5.5 Card-to-card swap
App → `rpc('internal_transfer')` with a fresh idempotency key. The function locks both of the caller's wallet rows in `card_id` order, checks balance, updates both, writes two legs. No Stripe, no fee.

### 5.6 Prohori chat
App → `POST /api/chat {message, language}` → rate limit (12/min) → embed the question locally → `match_faqs` (cosine, threshold 0.79, top 3) → system prompt containing only the retrieved Q&A + rules, user message separate → OpenRouter model chain → strip markdown → reply.

### 5.7 Notices
App reads `notices` from Supabase (public read). Rows are produced by `npm run seed:notices`, which scrapes Open Graph tags from seven hard-coded article URLs. Nothing refreshes the feed automatically.

---

## 6. Cross-cutting concerns

| Concern | Current design | Gap |
|---|---|---|
| **Errors & offline** | Repositories catch and fall back; every network call has a timeout (4–15 s; scan 120 s; chat 60 s). | Fallback to mock data is silent (SEC-03). Webhook failures are logged and acknowledged (SEC-06). |
| **Localisation** | `AppStrings._p(en, bn)`; English is the fallback when Bangla is empty; document language (`bn/en/zh`) is separate from UI language. | Prohori replies in `bn`/`en` only; scanner supports Chinese. |
| **Observability** | `console.log/warn/error` and `debugPrint`. | No structured logs, metrics, tracing, alerting, or request ids. Logs contain phone numbers and Stripe session ids. |
| **Testing** | Backend: 8 suites. The 5 offline ones (token, test phones, FAQ parser, OpenRouter fallback, chat) pass 43/43; `server.test.ts` and `documents.test.ts` can reach live services and were not run; `embeddings.test.ts` is opt-in. Flutter: 21 test files. Five `pentest_*.ts` scripts. | `verify_payment_run_test.dart` writes to the live Supabase project; pentest scripts target legacy columns and can pass vacuously (SEC-17). No scanner accuracy benchmark. |
| **Scalability** | Single process; in-memory rate limits; embedding model loaded per process; token validated with one Supabase round-trip per request. | Cannot scale horizontally without Redis for limits; every authenticated request depends on Supabase latency. |
| **Build / release** | Android package `com.probashiguard.app`, release keystore kept outside the repo; iOS bundle id is still `com.example.probashiGuard`. | No CI/CD, no Dockerfile, no deployment config, no staging environment. A release build falls back to the **debug** signing key if the keystore is absent. |
| **Config management** | `--dart-define` for the client; `.env` for the server. | The Supabase URL and publishable key are hard-coded defaults in `main.dart` (acceptable — publishable by design — but ties builds to one project). |

---

## 7. Implementation status

| Capability | Status | Notes |
|---|---|---|
| Email/password, email OTP, Google/GitHub, password reset | ✅ Implemented | Needs Supabase dashboard config (`{{ .Token }}` email templates, OAuth clients, redirect URLs). Leaked-password protection is **off**; minimum password length is 6. |
| Phone proof (Firebase → backend → DB) | ✅ Implemented | Default build uses the **test-number route**; real SMS is off until `ALLOW_REAL_SMS=true`. |
| Contract / visa audit | ✅ Implemented, ⚠️ save broken | Live CHECK constraint rejects `'OpenRouter AI'` (SEC-02). |
| Passport MRZ scan | ✅ Implemented | Android/iOS only (ML Kit). |
| Document vault (list / detail / offline cache) | ✅ Implemented | Works for passports and legacy `'Gemini'` rows. |
| Prohori assistant | ✅ Implemented | 78 FAQ rows live. |
| Notices, pre-departure checklist, in-app search | ✅ Implemented | Checklist is local only. |
| Wallet display | ⚠️ Partial | Real ledger when reachable; mock data otherwise. |
| Send money (Stripe Checkout) | ⚠️ Partial | Collects USD; **no payout to the recipient** (SEC-01). |
| Card-to-card swap | ✅ Implemented | Server-side atomic RPC. |
| Funding a wallet | ❌ Not in production | Only dev SQL scripts call `deposit_to_wallet`; the webhook calls `settle_remittance`, which nets to zero. Every real account sits at ৳0. |
| P2P transfer by phone | 🔧 Backend only | SQL function exists; no screen calls it. |
| Cards on file (`payment_methods`) | 🔧 Schema only | No UI. |
| Stripe Connect onboarding | 🔧 Routes only | Not used by the app; no ownership checks (SEC-04). |
| Trigger.dev tasks | 🔧 Stub | Log-only; fires when the session is *created*, before payment. |
| Complaint, embassy contacts, help, about, share | ⏳ "Coming soon" | |
| Biometric / PIN lock, linked devices, notification settings | ⏳ "Coming soon" | A `biometric` boolean is stored but nothing enforces it. |
| CI/CD, deployment, monitoring | ❌ Absent | |

---

## 8. Architectural observations

1. **The grant model is the strongest part of the design.** Money tables expose no write path to clients; every mutation is a `SECURITY DEFINER` function with row locks, idempotency keys, rounding and CHECK constraints behind it. Keep that discipline.
2. **"LLM reads, code decides"** is the right shape for the scanner (see [CORE_ALGORITHM.md](CORE_ALGORITHM.md) §1): hard rules override the model, and the model's output is coerced into a fixed shape before anything is stored or shown.
3. **The money path is a sandbox prototype, not yet a remittance system.** Payment is collected (in test mode) but not delivered, wallets cannot be funded, and the pending/settled UI state is partly local. That is fine today; decide the real settlement model (Connect payouts, partner payout API, or wallet funding) before enabling live Stripe keys.
4. **The client must stop inventing data.** The mock repository exists for offline UI, but its seeded balances and transactions can appear on a real account.
5. **Database state is not reproducible from the repo.** Reconcile `schema_migrations`, add the missing base-table migrations, and delete or archive the dead migration.
6. **Operational maturity is the main gap:** no CI, no environments, no structured logging, no alerting, in-memory rate limiting, and a live defect (SEC-02) that a smoke test would have caught.

The prioritised fix list is in [SECURITY_DESIGN.md §8](SECURITY_DESIGN.md#8-hardening-roadmap).
