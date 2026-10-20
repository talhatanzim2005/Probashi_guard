import { Router, Request, Response } from 'express';
import stripeClient from '../stripeClient.js';
import { triggerPaymentTasksSafely } from '../trigger/paymentTasks.js';
import { buildDestinationChargeData } from '../stripeConnect.js';
import { resolveUserId, hasVerifiedPhone, requireAuth } from '../supabaseUser.js';
import { rateLimit } from '../rateLimit.js';
import {
  SETTLEMENT_CURRENCY,
  USD_TO_BDT,
  VAT_ON_COMMISSION_RATE,
  toUsdCents,
  isCardId,
} from '../pricing.js';

const router = Router();

/// Routes that create things on Stripe cost API quota, so they need a signed-in
/// account and a modest per-account ceiling.
const stripeGuard = [requireAuth, rateLimit({ name: 'stripe', max: 30, windowMs: 60_000 })];

const ALLOWED_PRODUCT_CURRENCIES = ['usd', 'bdt'];
const MAX_PRODUCT_AMOUNT = 100_000;
const MAX_APPLICATION_FEE = 10_000;

/**
 * GET /api/rates
 * Returns real-time or baseline exchange rates for remittance currencies against BDT.
 */
router.get('/rates', async (_req: Request, res: Response) => {
  const baselineRates: Record<string, number> = {
    BDT: 1.0,
    SAR: 31.85,
    AED: 32.50,
    QAR: 32.80,
    KWD: 388.50,
    OMR: 310.20,
    MYR: 27.20,
    SGD: 91.40,
    USD: 119.50,
    GBP: 154.20,
    EUR: 130.10,
    INR: 1.42,
    PKR: 0.43,
  };

  try {
    const exchangeRates: any = await (stripeClient as any).exchangeRates?.retrieve('usd');
    if (exchangeRates && exchangeRates.rates) {
      const bdtPerUsd = exchangeRates.rates.bdt || 119.5;
      const computedRates: Record<string, number> = { BDT: 1.0 };
      for (const [currency, perUsdRate] of Object.entries(exchangeRates.rates)) {
        const currUpper = currency.toUpperCase();
        if (baselineRates[currUpper] !== undefined) {
          computedRates[currUpper] = Number((bdtPerUsd / (perUsdRate as number)).toFixed(4));
        }
      }
      return res.json({
        success: true,
        base: 'BDT',
        timestamp: new Date().toISOString(),
        rates: { ...baselineRates, ...computedRates },
      });
    }
  } catch (err: any) {
    console.warn('[Rates] Fallback to baseline rates:', err.message);
  }

  res.json({
    success: true,
    base: 'BDT',
    timestamp: new Date().toISOString(),
    rates: baselineRates,
  });
});

/**
 * POST /api/products/create
 */
router.post('/products/create', ...stripeGuard, async (req: Request, res: Response) => {
  try {
    const { name, description, amount, currency } = req.body;
    const price = Number(amount ?? 10);
    const cur = String(currency || 'bdt').toLowerCase();
    if (!Number.isFinite(price) || price <= 0 || price > MAX_PRODUCT_AMOUNT) {
      return res.status(400).json({ error: 'amount must be between 0 and ' + MAX_PRODUCT_AMOUNT });
    }
    if (!ALLOWED_PRODUCT_CURRENCIES.includes(cur)) {
      return res.status(400).json({ error: 'currency must be one of: ' + ALLOWED_PRODUCT_CURRENCIES.join(', ') });
    }
    const product = await stripeClient.products.create({
      name: String(name || 'Probashi Service Item').slice(0, 120),
      description: String(description || 'Digital remittance protection guarantee').slice(0, 500),
    });

    const stripePrice = await stripeClient.prices.create({
      product: product.id,
      unit_amount: Math.round(price * 100),
      currency: cur,
    });

    res.status(201).json({
      productId: product.id,
      priceId: stripePrice.id,
      product,
      price: stripePrice,
    });
  } catch (error: any) {
    console.error('Error creating product:', error);
    res.status(500).json({ error: error.message || 'Failed to create product' });
  }
});

/**
 * POST /api/checkout/destination-charge
 */
router.post('/destination-charge', ...stripeGuard, async (req: Request, res: Response) => {
  try {
    const { priceId, quantity, applicationFeeAmount, connectedAccountId, customerEmail } = req.body;
    const feeAmount = applicationFeeAmount !== undefined ? Number(applicationFeeAmount) : 150;
    if (typeof priceId !== 'string' || !/^price_[A-Za-z0-9]+$/.test(priceId)) {
      return res.status(400).json({ error: 'priceId is required' });
    }
    if (!Number.isFinite(feeAmount) || feeAmount < 0 || feeAmount > MAX_APPLICATION_FEE) {
      return res.status(400).json({ error: 'applicationFeeAmount is out of range' });
    }
    const qty = Number(quantity ?? 1);
    if (!Number.isInteger(qty) || qty < 1 || qty > 10) {
      return res.status(400).json({ error: 'quantity must be a whole number from 1 to 10' });
    }

    // Only route funds through Connect when the destination is a real connected
    // account that can receive a transfer; otherwise charge the platform directly.
    const { paymentIntentData, destinationAccountId } = await buildDestinationChargeData(
      connectedAccountId,
      feeAmount
    );
    const resolvedEmail =
      customerEmail ||
      req.body.senderEmail ||
      req.body.email ||
      req.body.userEmail ||
      undefined;

    const origin = req.headers.origin || process.env.DOMAIN || 'http://localhost:3000';
    const session = await stripeClient.checkout.sessions.create({
      mode: 'payment',
      customer_email: resolvedEmail,
      billing_address_collection: 'auto',
      payment_intent_data: paymentIntentData,
      line_items: [
        {
          price: priceId,
          quantity: qty,
        },
      ],
      success_url: `${origin}/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${origin}/cancel`,
    });

    if (!session || !session.url) {
      return res.status(500).json({ error: 'Stripe did not return a checkout URL' });
    }

    res.json({
      checkoutUrl: session.url,
      sessionId: session.id,
      destinationAccountId,
      isDestinationCharge: Boolean(destinationAccountId),
    });
  } catch (error: any) {
    console.error('[Checkout] Error creating destination charge session:', error);
    res.status(500).json({ error: error.message || 'Failed to create destination charge session' });
  }
});

/**
 * GET /api/checkout/session-status/:sessionId
 */
router.get('/session-status/:sessionId', requireAuth, async (req: Request, res: Response) => {
  try {
    const sessionId = String(req.params.sessionId || '');
    if (!/^cs_[A-Za-z0-9_]{8,200}$/.test(sessionId)) {
      return res.status(400).json({ error: 'Missing or malformed sessionId' });
    }
    const session = await stripeClient.checkout.sessions.retrieve(sessionId);
    // Only the account that opened the session may ask about it. 404 rather
    // than 403, so a stranger learns nothing about whether it exists.
    if (session.metadata?.payerUserId !== res.locals.userId) {
      return res.status(404).json({ error: 'Session not found' });
    }
    res.json({
      success: true,
      status: session.status,
      payment_status: session.payment_status,
      customer_email: session.customer_details?.email,
      is_paid: session.payment_status === 'paid' || session.status === 'complete',
    });
  } catch (error: any) {
    console.error('[Checkout] Error fetching session status:', error);
    res.status(500).json({ error: error.message || 'Failed to retrieve session status' });
  }
});

/**
 * POST /api/checkout/send-money
 * Map the remittance flow directly to Stripe Checkout Session with integer unit_amount (poisha).
 */
router.post('/send-money', rateLimit({ name: 'send-money', max: 20, windowMs: 60_000 }), async (req: Request, res: Response) => {
  try {
    // Who is paying. The webhook credits THIS account's wallet once Stripe
    // reports the session paid, so the id has to come from a verified token
    // rather than from the request body.
    const payerUserId = await resolveUserId(req);

    // Refuse an unverified account BEFORE Stripe takes anything. The matching
    // check inside p2p_transfer guards the onward send; this one guards the
    // charge, because a refusal after payment would strand real money.
    if (!payerUserId || !(await hasVerifiedPhone(payerUserId))) {
      return res.status(403).json({
        error: 'Verify your phone number before sending money',
        code: 'phone_not_verified',
      });
    }

    const {
      cardId,
      sourceCardId,
      beneficiary,
      recipientName,
      recipientPhone,
      sourceAmount,
      sourceCurrency,
      exchangeRate,
      amountBdt,
      incentiveBdt,
      customerEmail,
      connectedAccountId,
    } = req.body;

    const rawSourceAmount = Number(sourceAmount || 0);
    const rawExchangeRate = Number(exchangeRate || (String(sourceCurrency).toUpperCase() === 'BDT' ? 1.0 : 31.85));

    let bdtValue = Number(amountBdt);
    if (!Number.isFinite(bdtValue) || bdtValue <= 0) {
      bdtValue = rawSourceAmount > 0 ? rawSourceAmount * rawExchangeRate : 100;
    }

    // Every remittance is charged in USD, whatever the sender typed in, so the
    // gateway only ever sees one settlement currency.
    // The fee and the figure actually charged are derived here, never taken
    // from the request. The sender picks how much to send; letting them also
    // name the USD total would let the charge and the credit disagree.
    const resolvedVat = bdtValue * VAT_ON_COMMISSION_RATE;
    const usdValue = (bdtValue + resolvedVat) / USD_TO_BDT;
    const unitAmount = toUsdCents(usdValue);
    const domain = process.env.DOMAIN || 'http://localhost:3000';
    // Verify the routing target before recording it. The session itself stays a
    // platform charge, but this id is persisted in metadata and replayed by the
    // webhook into ledger reconciliation, so it must not be the platform's own
    // account or an account that never finished onboarding.
    const { destinationAccountId } = await buildDestinationChargeData(connectedAccountId, 0);
    const destinationAccount = destinationAccountId || '';

    const resolvedRecipientName =
      recipientName ||
      (typeof beneficiary === 'object' ? beneficiary?.name : beneficiary) ||
      'Beneficiary';

    const resolvedRecipientPhone =
      recipientPhone ||
      (typeof beneficiary === 'object'
        ? (beneficiary?.phoneOrAccount || beneficiary?.phone_number || beneficiary?.phone)
        : '') ||
      '+8801700000000';

    const resolvedSourceCurrency = String(sourceCurrency || 'SAR').toUpperCase();
    const requestedCardId = cardId || sourceCardId || 'card_wps';
    if (!isCardId(requestedCardId)) {
      return res.status(400).json({ error: 'Unknown source card' });
    }
    const resolvedCardId = requestedCardId;
    const resolvedIncentiveBdt = Number(incentiveBdt || 0);

    const sessionParams: any = {
      mode: 'payment',
      customer_email: customerEmail || undefined,
      success_url: `${domain}/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${domain}/cancel`,
      line_items: [
        {
          price_data: {
            currency: SETTLEMENT_CURRENCY,
            unit_amount: unitAmount,
            product_data: {
              name: `Remittance to ${resolvedRecipientName}`,
              description: `Probashi Guard Cross-Border Transfer (${rawSourceAmount || bdtValue} ${resolvedSourceCurrency}) • incl. VAT on commission`,
            },
          },
          quantity: 1,
        },
      ],
      billing_address_collection: 'auto',
      phone_number_collection: {
        enabled: true,
      },
      submit_type: 'auto',
      metadata: {
        kind: 'remittance',
        cardId: resolvedCardId,
        sourceAmount: String(rawSourceAmount || bdtValue),
        sourceCurrency: resolvedSourceCurrency,
        exchangeRate: String(rawExchangeRate),
        amountBdt: String(bdtValue),
        incentiveBdt: String(resolvedIncentiveBdt),
        vatOnCommission: String(resolvedVat),
        usdToBdt: String(USD_TO_BDT),
        recipientName: resolvedRecipientName,
        recipientPhone: resolvedRecipientPhone,
        destinationAccount: destinationAccount,
        // Stripe metadata values must be strings, and a key whose value is
        // undefined is dropped — so an unauthenticated call simply carries no
        // payer, and the webhook declines to credit anyone.
        ...(payerUserId ? { payerUserId } : {}),
      },
    };

    const session = await stripeClient.checkout.sessions.create(sessionParams);

    if (!session || !session.url) {
      return res.status(500).json({ error: 'Stripe failed to return a checkout session URL' });
    }

    // Trigger async background tasks non-blockingly
    triggerPaymentTasksSafely(
      {
        transactionId: session.id,
        recipientName: resolvedRecipientName,
        recipientPhone: resolvedRecipientPhone,
        amountBDT: bdtValue,
        incentiveBDT: resolvedIncentiveBdt,
        currency: 'BDT',
        timestamp: new Date().toISOString(),
      },
      {
        transactionId: session.id,
        sourceCardId: resolvedCardId,
        destinationAccountId: destinationAccount || undefined,
        amount: bdtValue,
        currency: 'BDT',
        sourceAmount: rawSourceAmount || bdtValue,
        sourceCurrency: resolvedSourceCurrency,
        exchangeRate: rawExchangeRate,
      }
    );

    return res.status(201).json({
      success: true,
      checkoutUrl: session.url,
      sessionId: session.id,
      transaction: {
        id: session.id,
        stripe_payment_id: session.id,
        title: resolvedRecipientName,
        subtitle: `Remittance to ${resolvedRecipientPhone}`,
        amount: bdtValue,
        converted_amount: rawSourceAmount || bdtValue,
        currency: resolvedSourceCurrency,
        exchange_rate: rawExchangeRate,
        incentive_bdt: resolvedIncentiveBdt,
        timestamp: new Date().toISOString(),
        type: 'send',
        card_id: resolvedCardId,
        checkout_url: session.url,
      },
    });
  } catch (error: any) {
    console.error('Error creating Stripe Checkout Session:', error);
    return res.status(500).json({ error: error.message || 'Internal Server Error' });
  }
});

export default router;