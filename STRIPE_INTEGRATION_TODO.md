# Stripe Integration Guide & Next Steps

This document is your single source of truth for completing the Stripe Checkout and Stripe Connect integration.

---

## Values to Replace

The following values are placeholders or dynamic runtime parameters and must be updated with your production URLs and live Stripe IDs before going live.

**Files containing placeholders:**
- [backend_service/.env](backend_service/.env)
- [backend_service/src/routes/checkout.ts](backend_service/src/routes/checkout.ts)

| Field | Current Value | What to Set |
|---|---|---|
| `STRIPE_SECRET_KEY` | `sk_test_51URCH...` (Configured) | Test key is active; switch to live key (`sk_live_...`) for production. |
| `STRIPE_TEST_ACCOUNT_ID` | `acct_1URCKREQ1XrhmDDe` (Configured) | Connected test account destination; update to production account for live remittances. |
| `TRIGGER_SECRET_KEY` | `tr_dev_sk_...` (Configured) | Dev key is active; switch to production Trigger.dev secret key for prod. |
| `STRIPE_WEBHOOK_SECRET` | `whsec_...` | Set from `stripe listen --forward-to localhost:3000/api/webhooks/stripe` or Stripe Dashboard. |
| `success_url` | `${origin}/success?session_id={CHECKOUT_SESSION_ID}` | Your actual post-payment success page URL in production. Keep `{CHECKOUT_SESSION_ID}` template. |
| `cancel_url` | `${origin}/cancel` | Your actual cancel/return page URL in production. |
| `line_items[].price` | Dynamic (`priceId` in request) | Your live Stripe Price IDs created in [Stripe Dashboard Prices](https://dashboard.stripe.com/prices) or via `/api/products/create`. |

---

## Configured Parameters

These parameters were configured in Checkout Studio and are already set correctly in your backend service.

**Files containing these parameters:**
- [backend_service/src/routes/checkout.ts](backend_service/src/routes/checkout.ts)

| Parameter | Value | Description |
|---|---|---|
| `ui_mode` | `hosted_page` | Configured for Stripe SDK v23.0.0 (SDK >= 21.0.0 uses `hosted_page`). |
| `billing_address_collection` | `auto` | Automatically requests billing address when required. |
| `phone_number_collection` | `{"enabled": true}` | Collects recipient/customer phone numbers at checkout. |
| `automatic_tax` | `{"enabled": true}` | Automatically calculates localized sales tax and VAT. |
| `allow_promotion_codes` | `true` | Allows customers to enter platform promo or discount codes. |
| `submit_type` | `auto` | Adapts button text automatically to the payment type. |
| `name_collection` | `{"individual": {"enabled": true, "optional": true}}` | Collects customer name during checkout. |
| `saved_payment_method_options` | `{"payment_method_save": "enabled"}` | Allows customers to save payment cards for repeat remittances. |
| `integration_identifier` | `hosted_mobile_app_0001` | Checkout studio integration ID. |
| `origin_context` | `mobile_app` | Context identifying mobile app remittance origin. |

---

## Setup and Next Steps

### 1. Environment Variables & Secret Configuration
In [backend_service/.env](backend_service/.env):
```env
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
PORT=3000
DOMAIN=http://localhost:3000
```

### 2. Project Architecture & Files Created
```text
f:\Probashi_Guard\
├── backend_service/
│   ├── src/
│   │   ├── routes/
│   │   │   ├── checkout.ts    # Checkout sessions (hosted_page, products, destination charges)
│   │   │   ├── connect.ts     # V2 Core Accounts API (create-account, account-link, account-status)
│   │   │   ├── webhooks.ts    # Thin Webhooks handler for v2 account events
│   │   │   └── payment.ts     # Cards, beneficiaries, and transaction syncing
│   │   ├── test/
│   │   │   └── server.test.ts # Automated backend test suite
│   │   ├── server.ts          # Express server with CORS & rawBody capture
│   │   └── stripeClient.ts    # Stripe client instance & parseThinEvent helper
│   ├── package.json
│   └── tsconfig.json
└── lib/frontend/payment/
    ├── controllers/
    │   └── payment_controller.dart          # Live controller wired to StripePaymentRepository
    ├── repository/
    │   ├── payment_repository.dart         # Repository interface
    │   ├── mock_payment_repository.dart    # Offline fallback
    │   └── stripe_payment_repository.dart  # HTTP client repository with auto-fallback
    ├── flows/                               # 3D Deck, Hold-to-confirm & wizard steps (100% preserved)
    └── widgets/
```

### 3. How the Integration Works
1. **Connected Accounts**: Expatriate agents and recipients onboard via `POST /api/connect/create-account` and `POST /api/connect/account-link` using Stripe V2 Core Accounts.
2. **Checkout & Remittances**: When the user triggers the 3-step send money flow in Flutter, `PaymentController.sendMoney()` calls `StripePaymentRepository.executeSendMoney()`, which invokes `POST /api/checkout/send-money` or `POST /api/checkout/destination-charge`.
3. **Thin Webhooks**: Stripe sends thin event notifications to `/api/webhooks/stripe`, which verifies the signature and fetches the full event from `stripeClient.v2.core.events.retrieve(thinEvent.id)`.
4. **Presentation Layer**: All Flutter UI components (3D card deck, hold-to-confirm button, stepper flows) are 100% preserved with zero design alterations.

### 4. Testing Credit Cards & Test Mode
Use Stripe's official test cards in test mode:
- Standard Successful Card: `4242 •••• •••• 4242` (Any future expiration date and 3-digit CVC)
- 3D Secure Authentication: `4000 •••• •••• 3063`
- Insufficient Funds: `4000 •••• •••• 0002`

### 5. Next Steps
1. Replace `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` in `backend_service/.env` with your real keys.
2. Start the backend service:
   ```bash
   cd backend_service
   npm run dev
   ```
3. Run the Flutter app:
   ```bash
   flutter run
   ```
4. Verify webhooks with Stripe CLI:
   ```bash
   stripe listen --forward-to localhost:3000/api/webhooks/stripe
   ```

### 6. Official Resources
- [Stripe Checkout Documentation](https://docs.stripe.com/payments/checkout)
- [Stripe Connect Documentation](https://docs.stripe.com/connect)
- [Stripe Model Context Protocol](https://docs.stripe.com/mcp)
- [Stripe Support](https://support.stripe.com)
