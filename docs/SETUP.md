# Probashi Guard: Setup and Handover Guide

How to get Probashi Guard running from a clean machine, and everything the next maintainer needs to take it over. For what the app does and why it's built the way it is, read the [README](README.md) first.

**Time needed:** about 2 hours on a first pass, most of it creating accounts.

## Contents

1. [Overview](#1-overview)
2. [Prerequisites and machine setup](#2-prerequisites-and-machine-setup)
3. [Accounts, keys and where they go](#3-accounts-keys-and-where-they-go)
4. [Supabase dashboard settings](#4-supabase-dashboard-settings)
5. [Database migrations](#5-database-migrations)
6. [Seed data and test accounts](#6-seed-data-and-test-accounts)
7. [Run it](#7-run-it)
8. [Payments and the Stripe webhook](#8-payments-and-the-stripe-webhook)
9. [Build and release (Android)](#9-build-and-release-android)
10. [Tests](#10-tests)
11. [Troubleshooting](#11-troubleshooting)
12. [Handover checklist](#12-handover-checklist)

---

## 1. Overview

Four pieces have to be configured. The code can't work around a missing one.

| Piece | What it is | Where its config lives |
|---|---|---|
| **Flutter app** | The mobile/web client | `lib/main.dart` (Supabase URL + publishable key), `android/app/google-services.json`, `--dart-define` flags |
| **backend_service** | Node/TypeScript API on port 3000 | `backend_service/.env` |
| **Supabase** | Auth and Postgres | Dashboard settings, plus the SQL in `supabase/migrations/` |
| **Firebase** | Phone-number verification only | `google-services.json`, `lib/firebase_options.dart`, console settings |

Plus **Stripe** (payments), **OpenRouter** (AI) and, optionally, **Trigger.dev**.

The order matters: Supabase → Firebase → backend `.env` → migrations → seed → run. Doing it in that order avoids most dead ends.

Three files hold secrets and are **gitignored**. They exist only on the previous maintainer's machine, so you must be handed them (or recreate them) separately:

| File | Holds |
|---|---|
| `backend_service/.env` | Every backend key |
| `android/app/google-services.json` | Firebase Android config |
| `android/key.properties` | Release signing passwords and keystore path |

---

## 2. Prerequisites and machine setup

| Tool | Version | Notes |
|---|---|---|
| Flutter | **3.44.2 stable** (Dart 3.12.2) | `pubspec.yaml` requires Dart `^3.12.2`. Check with `flutter --version` |
| Node.js | **22 or newer** | Developed on 22.22. `npm` comes with it |
| Android Studio | current | Install the Android SDK and an emulator. Its bundled JDK 17 is what Gradle uses |
| Git | any | |
| Chrome | any | For `flutter run -d chrome` |
| Stripe CLI | optional | `stripe listen` for local webhooks |

```bash
flutter doctor            # everything under Android toolchain should be green
git clone https://github.com/talhatanzim2005/Probashi_guard.git
cd Probashi_guard
git branch -a             # main, talha, onboarding. See below
flutter pub get
cd backend_service && npm install && cd ..
```

**Branches.** `main` is the integration branch and `talha` is the working branch. They're in step: `main` is one merge commit (PR #5 from `talha`) ahead. `origin/onboarding` is fully merged into `main` and is 14 commits behind it, so it can be deleted. Work from `main`.

**Gradle needs `JAVA_HOME`.** Android Studio's JDK isn't on `PATH` by default. On Windows (PowerShell):

```powershell
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
```

**Windows, split drives.** The project was developed with the source on `F:` and the pub cache on `C:`. That combination breaks Kotlin's incremental cache, which is why `android/gradle.properties` sets `kotlin.incremental=false`. Leave that line in.

**Only Android and Chrome have been exercised.** The `ios/`, `macos/`, `linux/` and `windows/` folders are Flutter scaffolding. iOS has no Firebase config and still carries the placeholder bundle id.

---

## 3. Accounts, keys and where they go

### 3.1 Supabase

Current project: ref `xfwxiawapksepskcevwe` (`https://xfwxiawapksepskcevwe.supabase.co`). To use a different project, you must also redo §4–§6.

1. Dashboard → **Project Settings → API Keys**. Copy the project URL, the **publishable** (anon) key and the **secret** (service-role) key.
2. Put all three in `backend_service/.env`:
   ```
   SUPABASE_URL=https://<ref>.supabase.co
   SUPABASE_ANON_KEY=<publishable key>
   SUPABASE_SERVICE_ROLE_KEY=<secret key>
   ```
3. The **app** gets only the URL and the publishable key. They're the defaults in `lib/main.dart`; for another project pass them at run time:
   ```bash
   flutter run --dart-define=SUPABASE_URL=https://<ref>.supabase.co --dart-define=SUPABASE_KEY=<publishable key>
   ```
4. **Never** put the secret (service-role) key in the app or in git. It bypasses all Row Level Security.
5. `SUPABASE_ACCESS_TOKEN` in `.env.example` is a personal access token for the Management API. The backend doesn't read it. You only need it to apply migrations from the command line (§5). Create one at supabase.com/dashboard/account/tokens and keep it in your shell environment, not in `.env`.

### 3.2 Firebase (phone verification only)

Current project id: `probashi-guard`. Firebase is **not** the identity system; Supabase is. It only proves that someone holds a phone number.

1. [Firebase console](https://console.firebase.google.com) → your project → **Authentication → Sign-in method → Phone → Enable**.
2. **Android app.** Project settings → Your apps → add an Android app with package **`com.probashiguard.app`**. Phone Auth is bound to this exact id plus the signing fingerprints, so don't rename the package without re-registering.
3. **Fingerprints.** Add the SHA-1 and SHA-256 for every key you build with:
   ```bash
   cd android && ./gradlew signingReport     # lists debug and release fingerprints
   ```
   - *Debug* differs on every developer's machine, so each developer adds their own.
   - *Release* comes from the release keystore (§9).
   - *Play App Signing*: after the first upload, Play Console → Setup → App signing shows a third fingerprint. **Add it**, or Phone Auth works in testing and breaks in production.
4. Download **`google-services.json`** and put it in `android/app/`. It's gitignored. Without it the app still builds (Gradle skips the Firebase plugin with a notice) but phone verification reports itself as not configured.
5. **Web.** `lib/firebase_options.dart` is committed and holds the web app's config. If you move to a new Firebase project, regenerate it for **web only**:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure --platforms=web
   ```
   Don't include Android. That tool rewrites the Gradle setup and breaks the conditional plugin guard. `DefaultFirebaseOptions.currentPlatform` deliberately throws on Android, because Android reads `google-services.json` instead.
6. Tell the backend which project issued the tokens:
   ```
   FIREBASE_PROJECT_ID=probashi-guard
   ```
7. **Test numbers (development).** Real SMS costs money and, on the free plan, only test numbers work. Ten test numbers are registered in the Firebase console (Authentication → Sign-in method → Phone → **Phone numbers for testing**), all with the same verification code:

   | Numbers | Verification code |
   |---|---|
   | `+8801700000000`, `+8801700000001`, `+8801700000002`, `+8801700000003`, `+8801700000004`, `+8801700000005`, `+8801700000006`, `+8801700000007`, `+8801700000008`, `+8801700000009` | `123456` (the same for every number) |

   Type the number with the `+880` country code on the app's phone screen, then enter `123456`. No SMS is sent.

   The backend has to know the same numbers, so list them in `backend_service/.env`:
   ```
   FIREBASE_TEST_PHONES=+8801700000000,+8801700000001,+8801700000002,+8801700000003,+8801700000004,+8801700000005,+8801700000006,+8801700000007,+8801700000008,+8801700000009
   ```
   To add more, create them in the console with a code, then append them to this line.

   A test number is the same string for every tester, so the backend treats it as a **shared pool**: up to 50 accounts can hold it at once, and the 51st evicts the oldest. If a number "un-verifies" itself, another account probably took it; verify again. A shared number **can't receive transfers** (it names no one), so you can't send money from one test account to another by phone number. This is ignored when `NODE_ENV=production`; a real number stays strictly one account.

### 3.3 Stripe

This is a prototype, so everything runs against the Stripe **sandbox** (test mode). Stay there until you're ready to go live.

1. Dashboard → **Developers → API keys**. Copy the secret key (`sk_test_…`) into `STRIPE_SECRET_KEY`. **The backend will not start without it.**
2. `STRIPE_WEBHOOK_SECRET`: see §8.
3. `STRIPE_TEST_ACCOUNT_ID` (optional): a connected account (`acct_…`) that receives destination charges. Without it, sessions are created as plain platform charges. To make one, enable Connect on the Stripe account, then call `POST /api/connect/create-account` followed by `POST /api/connect/account-link` and finish onboarding.
4. `DOMAIN`: the public base URL of the backend. Stripe's `success_url` and `cancel_url` are built from it (`${DOMAIN}/success`, `${DOMAIN}/cancel`). Locally: `http://localhost:3000`.
5. `STRIPE_PUBLISHABLE_KEY` is in `.env.example` but the code doesn't read it. Setting it does no harm.
6. Going live is a separate exercise: see [STRIPE_INTEGRATION_TODO.md](../STRIPE_INTEGRATION_TODO.md).

### 3.4 OpenRouter

One key powers both the document scanner and Prohori. Only **free** models are used.

1. Create a key at <https://openrouter.ai/keys> → `OPENROUTER_API_KEY`.
2. `OPENROUTER_BASE_URL=https://openrouter.ai/api/v1` (already the default in `.env.example`).
3. Free models are withdrawn or throttled often, so each feature tries a list in order. Override with comma-separated lists when one disappears:
   ```
   DOCUMENT_MODELS=nvidia/nemotron-3.5-super-vl:free,google/gemma-4-26b-a4b-it:free   # must accept images
   CHAT_MODELS=nvidia/nemotron-3-ultra-550b-a55b:free,google/gemma-4-26b-a4b-it:free
   ```
   `thinkingmachines/inkling:free` doesn't work: OpenRouter answers 403 to API calls.

### 3.5 Trigger.dev (optional)

Only the two stub tasks in `backend_service/src/trigger/paymentTasks.ts` use it, and they only log. Leave `TRIGGER_SECRET_KEY` empty and the backend skips them. If you want it: create a project, set `project` in `backend_service/trigger.config.ts` (currently `proj_dyezpzdwvlnnkslxzlzr`), put the secret key in `.env`, then run `npx trigger.dev@latest dev` from `backend_service/`.

### 3.6 Secrets you generate yourself

```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

| Variable | Use |
|---|---|
| `ANALYSIS_SIGNING_SECRET` | Signs scan results so `/api/documents/save` can tell they came from this server. Unset in development, results are unsigned (one warning). **Unset in production, saving is refused.** |
| `DEV_AUTH_BYPASS`, `DEV_AUTH_BYPASS_TOKEN`, `DEV_AUTH_BYPASS_USER_ID` | Lets `curl` and the automated tests call the API without a real session. **Leave blank** unless you need it. The server refuses to boot with the bypass on when `NODE_ENV=production` |
| `CORS_ORIGINS` | Extra browser origins, comma separated. Any `localhost` port is already allowed outside production. Native apps send no `Origin` and aren't affected |

### 3.7 Full variable reference

| Variable | Required | Default | Notes |
|---|---|---|---|
| `PORT` | no | `3000` | |
| `DOMAIN` | for Stripe | `http://localhost:3000` | Also sent to OpenRouter as the referer |
| `NODE_ENV` | no | | Set `production` when deployed |
| `STRIPE_SECRET_KEY` | **yes** | | Server exits at boot without it |
| `STRIPE_WEBHOOK_SECRET` | for payments | | |
| `STRIPE_TEST_ACCOUNT_ID` | no | | |
| `STRIPE_PUBLISHABLE_KEY` | no | | Not read by the code |
| `SUPABASE_URL` / `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` | **yes** | | |
| `SUPABASE_ACCESS_TOKEN` | no | | Not read by the backend; for the Management API |
| `OPENROUTER_API_KEY` | for scanner + chat | | |
| `OPENROUTER_BASE_URL` | no | `https://openrouter.ai/api/v1` | |
| `DOCUMENT_MODELS` / `DOCUMENT_MODEL` | no | built-in list | Must accept images |
| `DOCUMENT_MAX_TOKENS` | no | `16000` | |
| `CHAT_MODELS` / `CHAT_MODEL` | no | built-in list | |
| `EMBEDDING_MODEL` | no | `Xenova/multilingual-e5-small` | Changing it means re-running `npm run seed:faqs`. The default understands Bangla; `all-MiniLM-L6-v2` doesn't |
| `FAQ_MATCH_THRESHOLD` | no | `0.79` | Minimum similarity for a FAQ match |
| `TRANSFORMERS_CACHE_DIR` | no | library default | Where the embedding model is cached |
| `FIREBASE_PROJECT_ID` | for phone binding | | |
| `FIREBASE_TEST_PHONES` | no | | Ignored in production |
| `ANALYSIS_SIGNING_SECRET` | production | | |
| `DEV_AUTH_BYPASS*` | no | off | Never in production |
| `CORS_ORIGINS` | production, if a web client is hosted | | |
| `TRIGGER_SECRET_KEY` | no | | |

---

## 4. Supabase dashboard settings

The login screens depend on settings that live in the dashboard, not in code. If any is missing, the app *looks* finished and then silently fails.

1. **Authentication → Providers → Email.** Keep **Confirm email** switched **on**. (If it's off, `signUp` returns a session and the register screen skips the code screen on purpose.)
2. **Authentication → Email Templates.** Edit both **Confirm signup** and **Reset Password** so the body contains `{{ .Token }}`. The stock templates send a link, so no 6-digit code arrives and the app has nothing to ask for.
3. **Email sending.** Supabase's built-in sender is heavily rate limited. Configure a custom SMTP provider (Authentication → SMTP Settings) before real users sign up.
4. **Authentication → Providers → Google** and **GitHub.** Enable them and paste each provider's client ID and secret. Create the OAuth apps in Google Cloud Console and GitHub Developer Settings; their callback URL is the one Supabase shows on the provider page.
5. **Authentication → URL Configuration → Redirect URLs.** Add:
   ```
   io.supabase.probashiguard://login-callback/
   http://localhost:5000/**
   ```
   The first is the mobile deep link (registered in `AndroidManifest.xml` and `ios/Runner/Info.plist`; it must match `authRedirectUrl` in `lib/frontend/auth/auth_session.dart`). The second is Flutter web, which only works because the port is pinned with `--web-port 5000`. Add your deployed web origin if you host one.
6. **Anonymous sign-ins** can stay off. The app no longer signs anyone in anonymously; existing anonymous users are carried over by a database function at login.

---

## 5. Database migrations

> **Never run `supabase db push` on the live project.** Its migration history has drifted from the repo (below), and a push can abort partway and leave the database half-migrated. Apply SQL through the dashboard SQL editor or the Management API.

### What's applied on the live project

Read-only check against `xfwxiawapksepskcevwe`, 2026-10-20. Every migration in the repo has taken effect. But Supabase's own history table (`supabase_migrations.schema_migrations`) records only 9 versions, because the rest were pasted into the SQL editor.

| Migration (`supabase/migrations/`) | What it does | Live |
|---|---|---|
| `20261018120000_create_notices` | `notices` table for the news feed | Effect live |
| `20261018130000_harden_rls_security` | Strict RLS on wallets, beneficiaries, saved documents | Effect live. **Don't re-run on live:** it creates policies that already exist (`42710`) |
| `20261019005049_fix_rls_saved_documents_notices` | Grant/policy fixes on vault and notices | Recorded |
| `20261019005601_revoke_client_references_trigger` | Revokes `REFERENCES`/`TRIGGER` from clients | Recorded |
| `20261019120000_claim_anonymous_data` | Carries an anonymous device's data into the account it logs in to | Recorded |
| `20261019140000_p2p_core` | `profiles`, `wallets`, `payment_methods`, double-entry `transactions`, `p2p_transfer()` | Recorded |
| `20261019150000_tighten_client_grants` | Narrows client grants left by p2p_core | Recorded |
| `20261019160000_wallet_deposit` | `deposit_to_wallet()`, service role only | Recorded (as version `20261019073544`) |
| `20261019170000_verified_phone_gate` | `phone_verified_at`; transfers need a verified phone on both sides | Effect live |
| `20261019180000_enforce_rls_all_tables` | Turns RLS on for every public table | Effect live (0 tables without RLS) |
| `20261020100000_sub_wallets` | One wallet per card; `internal_transfer()`, `settle_remittance()` | Effect live |
| `20261020110000_shared_test_phones` | Shared pool for Firebase test numbers | Effect live |
| `20261020120000_faq_embeddings` | `pgvector`, `faq_embeddings`, `match_faqs()` | Effect live (78 rows) |

### The gap you need to know about

Three versions in the live history have **no file in the repo**: `create_saved_documents`, `saved_documents_translation_segments`, `transactions_strict_sender_privacy`. As a result, **no repo migration creates `saved_documents` or `beneficiaries`**. Later migrations assume both exist.

So the repo **cannot rebuild the database from scratch**. Nobody has replayed it on an empty project. If you need a second environment (staging, a new Supabase org), don't improvise from these files:

1. Take a schema dump of the live project: `pg_dump --schema-only --schema=public` using the connection string from Project Settings → Database, or dashboard Database → Backups.
2. Restore it into the new project.
3. Commit the dump as `supabase/baseline.sql`, and fix the migration history from there.

### Applying a new migration

**Dashboard (simplest).** SQL Editor → New query → paste the file → Run.

**Management API (scriptable).** Needs `SUPABASE_ACCESS_TOKEN` in your shell, not in `.env`:

```bash
PROJECT_REF=xfwxiawapksepskcevwe
curl -X POST "https://api.supabase.com/v1/projects/$PROJECT_REF/database/query" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  --data "$(jq -n --rawfile q supabase/migrations/<file>.sql '{query: $q}')"
```

Then record it so the history stops drifting further:

```sql
insert into supabase_migrations.schema_migrations (version, name)
values ('<14-digit version>', '<name>');
```

Check `select version, name from supabase_migrations.schema_migrations order by 1;` against `ls supabase/migrations/` before assuming anything is or isn't applied.

### Rules for writing migrations here

- **Check who holds EXECUTE** (`has_function_privilege`) before touching any money path. The grants are the whole security model.
- `deposit_to_wallet()` and `settle_remittance()` must stay `service_role`-only.
- A column-level `GRANT UPDATE (cols)` is *added to* an existing table-level `UPDATE`; it doesn't replace it. To narrow a grant, start with `REVOKE ALL`.
- `transactions.sender_id` has a default of `auth.uid()` that a strict INSERT policy depends on. Don't drop it.
- Don't add a column that could hold a card number, CVV or account number to `payment_methods`.

---

## 6. Seed data and test accounts

A fresh database has **no seed data**: every account starts at 0.00 on every card with no history. That's deliberate.

### Prohori's knowledge base

Needs migration `20261020120000` applied and `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` in `.env`.

```bash
cd backend_service
npm run seed:faqs -- --dry-run     # parse and embed, write nothing
npm run seed:faqs                  # parse, embed, write
```

The first run downloads the embedding model (about 120 MB) from Hugging Face; later runs reuse the cache. It's safe to re-run: questions are updated in place, never duplicated. The source is `instruction/probashi_guard_ai_flow_{english,bangla}.txt` (39 questions each). Edit those files and re-seed to change what Prohori knows. If you change `EMBEDDING_MODEL`, you must re-seed.

### News feed

```bash
npm run seed:notices -- --dry-run
npm run seed:notices
```

Scrapes the Open Graph tags of the article URLs listed at the top of `backend_service/scripts/seed_notices.ts` and caches them in `notices`. Edit that list to change the feed. Re-run to refresh. The app only ever reads the cache.

### Ready-made test login (prototype)

An account already exists on the Supabase project, with a verified test phone and funded cards, so you can try the app without signing up:

| | |
|---|---|
| Email | `sender@example.com` |
| Password | `Test1234!` |
| Phone | `+8801700000000` (already verified) |
| Verification code, any test number (§3.2) | `123456` |

Sign-in with these was checked against the live project on 2026-10-20, and the cards held balances then. Balances change as people use the account.

This is sandbox data for the prototype. Delete the account, and the Firebase test numbers, before real users arrive. To make more test accounts, sign up in the app with an email you can read, or add a user in the dashboard (Authentication → Users → Add user, tick *Auto Confirm User*), then verify any test number from §3.2.

### Funding a test account (dev only)

Run in the SQL editor. Both scripts are **not migrations**: never move them into `supabase/migrations/` and never run them on a production project, because they create money.

| Script | Does |
|---|---|
| `supabase/dev/fund_my_cards.sql` | Gives one account 50,000 / 25,000 / 10,000 BDT on its three cards |
| `supabase/dev/seed_test_funds.sql` | Gives two accounts a verified phone and a starting balance, using the production functions. Create both users first (Dashboard → Authentication → Users → Add user, tick *Auto Confirm User*), then edit the four values in its `DECLARE` block |

---

## 7. Run it

### Backend

```bash
cd backend_service
cp .env.example .env       # then fill it in (§3)
npm install
npm run dev                # tsx watch, reloads on save
```

Check it: `curl http://localhost:3000/api/health` returns `{"status":"ok",…}`. The first start warms the embedding model, which can take a moment.

Production build: `npm run build && npm start` (runs `dist/server.js`) with `NODE_ENV=production`.

### App

The backend has to be running for scanning, Prohori and sending money. Without it those fail by design.

| Target | Command | Reaches the backend at |
|---|---|---|
| Android emulator | `flutter run` | `http://10.0.2.2:3000` (built in) |
| Real Android phone | `flutter run --dart-define=BACKEND_URL=http://<PC-LAN-IP>:3000` | Your PC's LAN IP. Same Wi-Fi; allow port 3000 in the firewall |
| Chrome | `flutter run -d chrome --web-port 5000` | `http://localhost:3000` (built in) |
| Release build | `--dart-define=BACKEND_URL=https://…` | Must be **https**. Cleartext http is allowed in debug builds only |

On web the port must stay 5000, or OAuth redirects stop matching (§4).

### Checking everything works

1. `/api/health` answers.
2. Sign up in the app. The 6-digit code arrives by email (§4 if it doesn't).
3. On the phone screen, enter a test number such as `+8801700000001` and the code `123456` (§3.2). Or skip steps 2–4 and log in as `sender@example.com` / `Test1234!` (§6).
4. Fund the account (§6), then open **Payment**: the cards show balances.
5. **Scan** tab: photograph any document. An audit appears; nothing is saved until *Save to vault*.
6. Side menu → **Prohori**: ask "How do I send money?" and get an answer (needs `seed:faqs`).

---

## 8. Payments and the Stripe webhook

Sending money is a three-phase handoff, not an in-app charge:

1. `POST /api/checkout/send-money` creates a hosted Checkout session in **USD** and returns a URL. The server computes the amount, including the 0.01% "Vat on Commission". It also requires the payer to have a verified phone (`403 phone_not_verified` otherwise).
2. The app opens the URL in the browser and polls `GET /api/checkout/session-status/:id`.
3. Stripe calls the **webhook**, which verifies the signature and books the result into the ledger.

**Without a working webhook, payments complete on Stripe and nothing arrives in the wallet.**

### Local development

```bash
stripe login
stripe listen --forward-to localhost:3000/api/webhooks/stripe
```

It prints a `whsec_…` secret. Put it in `STRIPE_WEBHOOK_SECRET` and restart the backend. The secret changes each time you re-login or reset the CLI.

### Deployed

Stripe Dashboard → **Developers → Webhooks → Add endpoint**: `https://<your-domain>/api/webhooks/stripe`. Events the handler uses:

- `checkout.session.completed`
- `payment_intent.succeeded`
- `v2.core.account[requirements].updated` (Connect, delivered as a thin event)

Use that endpoint's signing secret for `STRIPE_WEBHOOK_SECRET`.

### Test cards

| Card | Result |
|---|---|
| `4242 4242 4242 4242` | Success |
| `4000 0000 0000 3063` | 3D Secure |
| `4000 0000 0000 0002` | Declined |

Any future expiry and any 3-digit CVC.

### Things that are intentional

- Wallet balances are **BDT**. USD is only what Stripe charges. The rate is a constant, `USD_TO_BDT = 119.5` in `backend_service/src/pricing.ts`.
- The webhook credits the **payer's** wallet, keyed on the Stripe session id, so Stripe's three days of retries book it once. With no payer in the session metadata it refuses to credit anyone.
- Moving money between your own cards uses `internal_transfer()` and never touches Stripe.

---

## 9. Build and release (Android)

Package id: **`com.probashiguard.app`**. The version is `version: 1.0.0+1` in `pubspec.yaml` (name `+` build number; Play needs the build number to rise on every upload).

### The release keystore

Release builds are signed with a keystore that is **deliberately outside the repo**:

| Item | Location |
|---|---|
| Keystore | `F:\Probashi_Guard_keystore\probashi-guard-release.jks` (alias `probashi-guard`, valid 10,000 days) |
| Passwords | `F:\Probashi_Guard_keystore\keystore-password.txt`, and `android/key.properties` |

> **If both the keystore and its password are lost, the app can never be updated on Google Play again.** A new key means a new store listing and a new app. Both currently sit on one local drive. Back them up somewhere durable (a password manager plus an offline copy) **before anything else**.

`android/key.properties` (gitignored) looks like this:

```properties
storeFile=F:/Probashi_Guard_keystore/probashi-guard-release.jks
storePassword=<password>
keyAlias=probashi-guard
keyPassword=<password>
```

**Use forward slashes.** In a Java `.properties` file a backslash is an escape character, so `F:\path` silently becomes `F:path`.

Without `key.properties`, a release build falls back to the **debug** key. That APK is for local testing only: Play rejects it, and its fingerprint isn't the one registered in Firebase.

### Build

```powershell
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
flutter build appbundle --release --dart-define=BACKEND_URL=https://<your-backend>   # for Play
flutter build apk --release --dart-define=BACKEND_URL=https://<your-backend>         # for sideloading
```

Before the first Play upload, register the release SHA-1/SHA-256 in Firebase (§3.2). After it, add the Play App Signing fingerprint too.

### Android settings that must not be undone

| Setting | Where | Why |
|---|---|---|
| `permission_handler: ^12.0.3` | `pubspec.yaml` | 13.x needs `compileSdk 37`, and AGP 9.0.1 stops at 36. Failure shows at `:app:checkDebugAarMetadata`. Lift the pin only together with an AGP upgrade |
| `kotlin.incremental=false` | `android/gradle.properties` | Split-drive builds fail with "Could not close incremental caches" without it |
| Conditional `google-services` plugin | `android/app/build.gradle.kts` | Applied unconditionally it breaks every build that lacks the JSON file |
| `INTERNET` and `CAMERA` permissions | `AndroidManifest.xml` | Network and the scanner. No photo/storage permission is declared on purpose: `image_picker` uses the system Photo Picker, and `READ_MEDIA_IMAGES` would need a Play justification |
| OAuth deep-link intent filter | `AndroidManifest.xml` | `io.supabase.probashiguard://login-callback` |
| `allowBackup="false"` | `AndroidManifest.xml` | Keeps app data out of device backups |
| `usesCleartextTraffic="true"` | `android/app/src/debug/AndroidManifest.xml` | Debug talks to the local backend over plain http. Release stays https-only |

### iOS

Not done. You'd need to rename `PRODUCT_BUNDLE_IDENTIFIER` (still `com.example.probashiGuard`), register an iOS app in Firebase and add `GoogleService-Info.plist`, and verify the build on a Mac. The OAuth URL scheme is already in `ios/Runner/Info.plist`. The project's deployment target is currently 13.0; an earlier note says the ML Kit-based passport scanner needed 15.5, so raise it on your first Mac build if CocoaPods complains.

---

## 10. Tests

```bash
flutter analyze                                  # currently reports no issues
flutter test test/document_scanner_test.dart     # run Flutter tests one file at a time
flutter test test/localization_test.dart
cd backend_service && npm run test:hermetic      # compiles, then runs 7 hermetic suites (181 tests); no network
```

Every test case, the test phones and code, and the live smoke script are in [TESTCASES.md](TESTCASES.md).

> **Don't run a bare `flutter test`.** `test/verify_payment_run_test.dart` ("Execute and verify live payment") inserts a transaction and updates a wallet in the **live** Supabase project each time. Run payment tests only on purpose.

**`npm test` (the original backend suites) loads `backend_service/.env`** and calls real endpoints, including Stripe: `server.test.ts` creates a test-mode connected account on every run. Point it at test-mode Stripe keys and a non-production Supabase project. It runs with `NODE_ENV=test` and a built-in dev-bypass token, so no real login is needed. **`npm run test:hermetic` does not read `.env` and touches nothing outside the process.**

**Known state when this guide was written:** `flutter analyze` and `tsc` are clean; `npm run test:hermetic` ran 181 tests with 164 passing and 17 deliberately failing (each one names the finding it is waiting on, see TESTCASES §7); every Flutter test file except `verify_payment_run_test.dart` passed (366, with 8 skipped on purpose). The original `npm test` suites were not re-run, because they hit live services.

A test failing with Postgres `42501` ("new row violates row-level security policy") means the test's Supabase client isn't signed in, not that the app is broken. Sign the test client in and pass its user id; don't loosen the policy.

`npm run pentest:*` are security probes (oversized upload, no-auth request, RLS cross-reads, a poisoned Stripe webhook, an Android backup-flag check). Run them against a **local** backend only.

---

## 11. Troubleshooting

| Problem | Cause and fix |
|---|---|
| "Payment Gateway Error" on send | `backend_service` isn't running, or `BACKEND_URL` is wrong. Correct behaviour, not a regression |
| "Cannot reach the scanner server" | Same cause. Real phone: use the LAN IP, same Wi-Fi, port 3000 open in the firewall |
| Backend exits at start: "Missing STRIPE_SECRET_KEY" | Set it in `.env` |
| Signup or reset code never arrives | Email templates lack `{{ .Token }}`, **Confirm email** is off, or Supabase's built-in email rate limit is hit (§4) |
| OAuth bounces back to the login screen | Redirect URL not allow-listed, or the provider's client ID/secret is missing (§4) |
| Chrome login "succeeds, then goes nowhere" | The page's port isn't in Redirect URLs. Run with `--web-port 5000` |
| Old anonymous data missing after login | `20261019120000_claim_anonymous_data` isn't applied |
| "Phone verification is not set up" | No `google-services.json` (Android), or `Firebase.initializeApp` failed. Check the debug log for `[main] Firebase not configured` |
| `[core/no-app]` on web | `lib/firebase_options.dart` missing or out of date; regenerate for web (§3.2) |
| Phone verification works in debug, fails in release | Release or Play App Signing SHA not registered in Firebase |
| `403 phone_not_verified` | The payer has no verified phone |
| `P0002` ("No Probashi Guard account uses that number") | The recipient's number isn't held by a verified, non-shared account: unregistered, unverified, or a shared test number |
| Balance is 0.00 everywhere | Expected: no seed data. Fund a dev account (§6) |
| Money paid on Stripe but wallet unchanged | Webhook not reaching the backend, wrong `STRIPE_WEBHOOK_SECRET`, or the session had no payer in its metadata (§8) |
| Prohori returns 503 | `OPENROUTER_API_KEY` unset; `faq_embeddings` empty; or built with a different embedding model than the server uses (re-run `seed:faqs`) |
| Scan fails with model error (403/404/429) | A free model was withdrawn or throttled. Update `DOCUMENT_MODELS` |
| *Save to vault* refused in production | `ANALYSIS_SIGNING_SECRET` isn't set |
| Server won't boot: "DEV_AUTH_BYPASS=1 … NODE_ENV=production" | Unset `DEV_AUTH_BYPASS`. Intentional guard |
| Scanner tab shows a placeholder | A merge reverted tab 2 to `OcrView`. It should be `DocumentScanView` (below) |
| Android: `JAVA_HOME` not set | Point it at Android Studio's `jbr` folder (§2) |
| Android: "Could not close incremental caches" | `kotlin.incremental=false` missing (§9) |
| Android: "File google-services.json is missing" | The conditional plugin guard was removed (§9) |
| Android: `:app:checkDebugAarMetadata` fails | `permission_handler` is on 13.x (§9) |

### After merging a teammate's branch

Past UI commits overwrote integration wiring that lives outside the files they were editing. Before debugging anything else, check:

1. **`pubspec.yaml`** still lists: `supabase_flutter`, `firebase_core`, `firebase_auth`, `camera`, `http`, `image_picker`, `passport_scanner`, `mrz_parser`, `font_awesome_flutter`, `url_launcher`, `shared_preferences`, `cached_network_image`, `permission_handler` (`^12.0.3`). To list what the code actually imports: `grep -rhoE "^import 'package:([a-z0-9_]+)/" lib/ test/ | sort -u`
2. **`lib/main.dart`** still calls `_initSupabase()` and `_initFirebase()`, and tab 2 of the shell is `DocumentScanView`.
3. **Android:** `INTERNET` + `CAMERA` permissions and the OAuth intent filter in `AndroidManifest.xml`; `kotlin.incremental=false` in `gradle.properties`; the `google-services` guard in `build.gradle.kts`.
4. **iOS:** the `io.supabase.probashiguard` URL scheme in `Info.plist`.
5. `flutter analyze`.

---

## 12. Handover checklist

### Do first

- [ ] **Back up the release keystore and its password** (§9) in two places.
- [ ] **Decide on repo visibility.** If the repo is public, keep it free of secrets and add a `LICENSE` file.
- [ ] **Replace the hard-coded Stripe test connected-account id.** It's a fallback in `stripe_payment_repository.dart` and `supabase_payment_repository.dart`; use real onboarding instead (§3.3).
- [ ] In Google Cloud Console, **restrict the Firebase web API key** in `lib/firebase_options.dart` to your web origins. It's an identifier rather than a secret, but it's in git.

### Accounts to transfer ownership of

| Account | Identifier |
|---|---|
| GitHub repo | `talhatanzim2005/Probashi_guard` (branches `main`, `talha`, `onboarding`) |
| Supabase project | `xfwxiawapksepskcevwe` |
| Firebase project | `probashi-guard` |
| Stripe account | sandbox (test mode) for now; the account owner holds the keys |
| OpenRouter | account that owns the API key |
| Trigger.dev | project `proj_dyezpzdwvlnnkslxzlzr` (optional) |
| Google Cloud / GitHub OAuth apps | the ones behind the Supabase Google and GitHub providers |
| Google Play Console | not recorded in this repo. Confirm whether a listing exists |

### Files to hand over securely (password manager, never git, chat or email)

Once ownership has moved, roll the keys inside them so the outgoing maintainer's copies stop working.

- [ ] `backend_service/.env`
- [ ] `android/key.properties`
- [ ] `android/app/google-services.json`
- [ ] `F:\Probashi_Guard_keystore\probashi-guard-release.jks` and `keystore-password.txt`

### Confirm and fill in

The repo can't answer these. Fill them in here once known:

- Production backend URL: `__________` (the repo has no Dockerfile, CI or hosting config)
- Where `NODE_ENV=production` secrets are stored: `__________`
- Is the app on Google Play, and which track: `__________`
- Who receives the Stripe, Firebase and Supabase billing and alert emails: `__________`
- Custom SMTP provider for Supabase auth email: `__________`

### Verify on your own machine

- [ ] `flutter doctor` is green and `flutter analyze` reports no issues
- [ ] `npm run dev` starts and `/api/health` answers
- [ ] You can sign up, receive the code, and verify a test phone
- [ ] A funded test account can scan a document, save it, and ask Prohori a question
- [ ] A Stripe test-mode payment books to the wallet through the webhook
- [ ] `./gradlew signingReport` shows your debug SHA, and it's added to Firebase
- [ ] A signed release build installs and phone verification works in it

### Known gaps (details in the [README](README.md#known-issues-and-next-steps))

- The migrations can't rebuild the database from scratch (§5); take a schema dump before creating a second environment.
- Stripe runs in the sandbox (this is a prototype); going live is its own task.
- iOS isn't set up.
- Several menu and profile entries are "coming soon" placeholders.
- The Trigger.dev tasks are stubs, and the rate limiter is in-memory.
