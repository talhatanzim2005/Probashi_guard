# Probashi Guard - Payment & Remittance Feature Specification

**Document Path:** `d:/flutter/probashi_Guard/Probashi_guard/.plans/payment-feature-spec.md`  
**Status:** Approved & Ready for Implementation  
**Created:** 2026-10-16  

---

## 1. Overview & Objectives

The Payment module in Probashi Guard delivers a world-class, dynamic mobile wallet and remittance interface tailored specifically for expatriate migrant workers (Probashis). The screen brings to life the high-fidelity UI design from `05c5618e-0eb0-4b98-ba20-c357fb21ef04.png` while strictly adhering to the **4-color palette** defined in `lib/theme/app_colors.dart` and the animation principles from `skills/animate`.

### Core Goals
1. **Visual Fidelity**: Faithful recreation of the card-stacked wallet, quick send avatars, pill action buttons, and transaction history.
2. **Color Palette Adherence**: Strictly restricted to `AppColors.cloudDancer`, `AppColors.royalBlue`, `AppColors.emeraldGreen`, and `AppColors.crimsonRed`.
3. **Pluggable & Decoupled Architecture**: Repository pattern with abstract contracts (`PaymentRepository`, `PaymentGatewayService`) and `PaymentController` (ChangeNotifier). Instant mock data now, zero-UI-refactor transition to Supabase and Stripe later.
4. **Multi-Currency Support**: Real-time switching and conversion between BDT (৳), USD ($), SAR (﷼), AED (د.إ), and QAR (ر.ق).
5. **Interactive Stacked Card Deck**: Tap or swipe to cycle through Wage Protection System (WPS) Payroll Card, Probashi Expatriate Multi-Currency Account, and bKash/Nagad Remittance Link.
6. **bKash-Style 3-Step Send Flow**: Recipient selection -> Dual-currency amount entry with live conversion -> Hold-to-confirm slide animation with haptic feedback.
7. **Dynamic QR Receive & Instant Transfer**: Standardized QR payload with copy/share actions and inter-wallet transfer.

---

## 2. Color System & Design Tokens

Strictly applied throughout the Payment subsystem:
- **`AppColors.cloudDancer` (`#F5F2EB`)**: App background, container surfaces, pill backgrounds, and contrast base.
- **`AppColors.royalBlue` (`#1A4B9C`)**: Primary brand identity, active states, card accents, icons, and headers.
- **`AppColors.emeraldGreen` (`#1E824C`)**: Positive balance indicators, incoming remittances (+ amounts), successful states, and hold-to-confirm progress.
- **`AppColors.crimsonRed` (`#D32F2F`)**: Outgoing payments (- amounts), fee warnings, alerts, and destructive actions.
- **Dark Obsidian Tone**: Deep contrast card body (`#111625` or saturated royal dark) for the main balance card container as in the design reference.

---

## 3. Architecture & Data Model (Supabase & Stripe Ready)

### 3.1 Domain Models
- **`WalletCardModel`**:
  - `id`: String (UUID)
  - `title`: String ("WPS Payroll Card", "Probashi Multi-Currency", "bKash Direct")
  - `provider`: String ("WPS / Al Rajhi", "Probashi Bank", "bKash Remittance")
  - `cardNumberMasked`: String ("•••• 8420")
  - `balance`: double
  - `currency`: String ("SAR", "BDT", "USD", etc.)
  - `cardColor`: Color / theme styling
  - `cardType`: CardType enum
  - `toJson()` / `fromJson()` / `toMap()`

- **`CurrencyModel`**:
  - `code`: "BDT", "USD", "SAR", "AED", "QAR"
  - `symbol`: "৳", "$", "﷼", "د.إ", "ر.ق"
  - `exchangeRateToBdt`: double (e.g. 1 SAR = 31.85 BDT)

- **`BeneficiaryModel`**:
  - `id`: String
  - `name`: String
  - `phone`: String
  - `avatarUrl`: String
  - `walletType`: String ("bKash", "Nagad", "Bank Account")
  - `isRecent`: bool

- **`TransactionModel`**:
  - `id`: String
  - `title`: String (e.g. "Google", "Elizabeth", "Remittance to Family")
  - `subtitle`: String (e.g. "Subscription", "Received Money", "bKash Transfer")
  - `amount`: double
  - `currency`: String
  - `timestamp`: DateTime
  - `type`: TransactionType (`send`, `receive`, `subscription`, `transfer`)
  - `status`: String ("Completed", "Pending", "Failed")

### 3.2 Service & Repository Contracts
- **`abstract class PaymentRepository`**:
  - `Future<List<WalletCardModel>> getCards();`
  - `Future<List<BeneficiaryModel>> getBeneficiaries();`
  - `Future<List<TransactionModel>> getTransactions({String? cardId});`
  - `Future<TransactionModel> executeTransfer({required String sourceCardId, required String recipientPhone, required double amount, required String currency});`
- **`MockPaymentRepository implements PaymentRepository`**:
  - High-fidelity in-memory provider populated with expatriate realistic data.
- **`PaymentController extends ChangeNotifier`**:
  - State holder for active card index, currency, balance visibility, filter states, and transfer pipeline.

---

## 4. Screen Layout & Interactive Features

### 4.1 Payment Main View (`payment_view.dart`)
1. **Persistent Top Bar Alignment**: Integrated directly with `main.dart`'s `CustomAppBar` — no duplicate greeting header.
2. **Interactive Stacked Card Deck (`payment_card_deck.dart`)**:
   - Visual stack of 3 layered cards with realistic depth (scale: 1.0, 0.94, 0.88; translateY offset).
   - Tap any peeking card or swipe horizontally to cycle cards to front with smooth spring animation.
   - Front card displays: Total Balance with currency symbol, eye toggle for masking (`••••••`), card network badge, and expiry.
3. **Currency Switcher Pill**:
   - Quick selector pill for BDT, USD, SAR, AED, QAR that instantly recalculates and displays the converted equivalent.
4. **Primary Action Pills (`quick_action_row.dart`)**:
   - `[ ↗ Send ]`: Navigates to the 3-step bKash remittance flow.
   - `[ ↙ Receive ]`: Opens the dynamic QR code & IBAN bottom sheet with copy/share.
   - `[ ⇄ Transfer ]`: Opens instant inter-card swap dialog.
5. **Quick Send Contact Row (`quick_send_list.dart`)**:
   - Horizontal list of contact avatars (Elizabeth, William, Adam, Tony, Emma, Sarah).
   - Tapping directly opens Step 2 (Amount Entry) pre-populated with that recipient.
6. **Transaction History (`transaction_history_section.dart`)**:
   - Header with "Transaction History" and "See all".
   - Rich list tiles with merchant/avatar icons, timestamp, category, and styled amount (`+` emerald green, `-` dark/crimson).

---

## 5. Dedicated Multi-Step Send Flow (bKash-Style)

### Step 1: Beneficiary / Recipient Selection (`send_contact_step.dart`)
- Search bar for phone number, name, or account ID.
- Quick filter chips: "All", "bKash", "Nagad", "Bank".
- List of saved expatriate beneficiaries and recent transfers.

### Step 2: Dual-Currency Amount Entry (`send_amount_step.dart`)
- Live dual currency converter: Host currency (e.g. SAR/AED) on one side, Home currency (BDT ৳) on the other.
- Real-time exchange rate badge (e.g., `1 SAR = 31.85 BDT • Govt 2.5% Incentive Applied`).
- Preset amount chips (500, 1000, 2500, 5000 BDT).
- Source card selector dropdown.

### Step 3: Review & Hold-to-Confirm (`send_confirm_step.dart`)
- Receipt summary: Recipient name, number, provider logo, exchange rate, transfer fee, government remittance bonus.
- **Hold-to-Confirm Slider (`hold_to_confirm_button.dart`)**:
  - Animated progress bar that fills over 1.2s when pressed and held.
  - Haptic feedback tick.
  - Cancels smoothly if released before completion.
  - Triggers success animation and updates state dynamically upon completion.

---

## 6. Receive Modal (Standardized Dynamic QR)

- Standardized URI format: `probashiguard://pay?account={USER_ID}&name={NAME}&iban={IBAN}`.
- Custom vector-rendered high-contrast QR code with logo avatar.
- Display of Account ID / Remittance IBAN with 1-tap Copy to clipboard and Share intent.
- Offline cached fallback.

---

## 7. Animation Principles (Emil Kowalski Philosophy)

- **Purpose**: Spatial consistency for card stack, state clarity for balance masking, and feedback for button interactions.
- **Curves & Timing**:
  - Card Stack Cycling: `Curves.easeOutCubic`, 320ms duration.
  - Hold-to-Confirm: Linear progress over 1200ms with spring rebound on release (`Curves.elasticOut`, 400ms).
  - Bottom Sheets & Modals: `Curves.easeOutQuad`, 280ms.
- **Hardware Acceleration**: Only animate `transform` and `opacity`. No layout recalculation jumps.
