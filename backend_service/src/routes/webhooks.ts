import { Router, Request, Response } from 'express';
import stripeClient from '../stripeClient.js';
import { triggerPaymentTasksSafely } from '../trigger/paymentTasks.js';

const router = Router();

/**
 * POST /api/webhooks/stripe
 * Handles both standard snapshot webhook events (checkout.session.completed)
 * and Stripe Connect thin events with cryptographic signature verification.
 */
router.post('/stripe', async (req: Request, res: Response) => {
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!webhookSecret) {
    console.error('CRITICAL: Missing STRIPE_WEBHOOK_SECRET environment variable.');
    return res.status(500).json({ error: 'CRITICAL: Missing STRIPE_WEBHOOK_SECRET' });
  }

  const sig = req.headers['stripe-signature'] as string;
  if (!sig) {
    return res.status(400).json({ error: 'Missing stripe-signature header' });
  }

  let event: any;
  const rawBody = (req as any).rawBody || req.body;

  try {
    // 1. Try standard Stripe snapshot event verification
    event = stripeClient.webhooks.constructEvent(rawBody, sig, webhookSecret);
  } catch (err: any) {
    // 2. If standard verification fails, try parsing as a thin event
    try {
      if (typeof (stripeClient as any).parseThinEvent === 'function') {
        const thinEvent = (stripeClient as any).parseThinEvent(rawBody, sig, webhookSecret);
        event = await (stripeClient.v2.core.events as any).retrieve(thinEvent.id);
      } else {
        throw err;
      }
    } catch (thinErr: any) {
      console.error('[Webhooks] Webhook signature verification failed:', err.message);
      return res.status(400).json({ error: `Webhook signature verification failed: ${err.message}` });
    }
  }

  try {
    console.log(`[Webhooks] Processing Stripe event: ${event.type}`);

    switch (event.type) {
      case 'checkout.session.completed': {
        const session = event.data?.object || event.object;
        const metadata = session.metadata || {};
        console.log(`[Webhooks] Checkout session completed: ${session.id}`, metadata);

        const cardId = metadata.cardId || 'card_wps';
        const amountBdt = Number(metadata.amountBdt || (session.amount_total ? session.amount_total / 100 : 0));
        const incentiveBdt = Number(metadata.incentiveBdt || 0);
        const sourceAmount = Number(metadata.sourceAmount || amountBdt);
        const sourceCurrency = metadata.sourceCurrency || 'SAR';
        const exchangeRate = Number(metadata.exchangeRate || 1.0);
        const recipientName = metadata.recipientName || session.customer_details?.name || 'Beneficiary';
        const recipientPhone = metadata.recipientPhone || session.customer_details?.phone || '+8801700000000';
        const destinationAccount = metadata.destinationAccount || process.env.STRIPE_TEST_ACCOUNT_ID;

        // Trigger Trigger.dev background tasks
        await triggerPaymentTasksSafely(
          {
            transactionId: session.id,
            recipientName,
            recipientPhone,
            amountBDT: amountBdt,
            incentiveBDT: incentiveBdt,
            currency: 'BDT',
            timestamp: new Date().toISOString(),
          },
          {
            transactionId: session.id,
            sourceCardId: cardId,
            destinationAccountId: destinationAccount,
            amount: amountBdt,
            currency: 'BDT',
            sourceAmount,
            sourceCurrency,
            exchangeRate,
          }
        );

        // Synchronize with Supabase if credentials are configured
        const supabaseUrl = process.env.SUPABASE_URL;
        const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY;
        if (supabaseUrl && supabaseKey) {
          try {
            // The Flutter app also records paid sessions, so skip the insert and
            // the wallet deduction if this session is already in history.
            const existingRes = await fetch(
              `${supabaseUrl}/rest/v1/transactions?stripe_payment_id=eq.${encodeURIComponent(session.id)}&select=id&limit=1`,
              {
                headers: {
                  'apikey': supabaseKey,
                  'Authorization': `Bearer ${supabaseKey}`,
                },
              }
            );
            const existing = (await existingRes.json()) as any[];
            if (Array.isArray(existing) && existing.length > 0) {
              console.log(`[Webhooks] Session ${session.id} already recorded; skipping Supabase sync`);
              break;
            }

            await fetch(`${supabaseUrl}/rest/v1/transactions`, {
              method: 'POST',
              headers: {
                'apikey': supabaseKey,
                'Authorization': `Bearer ${supabaseKey}`,
                'Content-Type': 'application/json',
                'Prefer': 'return=minimal',
              },
              body: JSON.stringify({
                title: recipientName,
                subtitle: `Remittance to ${recipientPhone}`,
                amount_bdt: amountBdt,
                converted_amount: sourceAmount,
                currency: sourceCurrency,
                exchange_rate: exchangeRate,
                incentive_bdt: incentiveBdt,
                type: 'send',
                card_id: cardId,
                stripe_payment_id: session.id,
                created_at: new Date().toISOString(),
              }),
            });

            // Decrement wallet balance in Supabase wallets table
            const walletRes = await fetch(`${supabaseUrl}/rest/v1/wallets?id=eq.${cardId}&select=*`, {
              headers: {
                'apikey': supabaseKey,
                'Authorization': `Bearer ${supabaseKey}`,
              },
            });
            const wallets = (await walletRes.json()) as any[];
            if (Array.isArray(wallets) && wallets.length > 0) {
              const currentBalance = Number(wallets[0].balance_bdt || 0);
              const newBalance = Math.max(0, currentBalance - amountBdt);
              await fetch(`${supabaseUrl}/rest/v1/wallets?id=eq.${cardId}`, {
                method: 'PATCH',
                headers: {
                  'apikey': supabaseKey,
                  'Authorization': `Bearer ${supabaseKey}`,
                  'Content-Type': 'application/json',
                },
                body: JSON.stringify({ balance_bdt: newBalance }),
              });
            }
            console.log(`[Webhooks] Synchronized transaction and wallet with Supabase for session ${session.id}`);
          } catch (sbErr: any) {
            console.warn('[Webhooks] Supabase sync warning (non-fatal):', sbErr.message);
          }
        }
        break;
      }

      case 'payment_intent.succeeded': {
        console.log(`[Webhooks] PaymentIntent succeeded: ${event.data?.object?.id}`);
        break;
      }

      case 'v2.core.account[requirements].updated':
        console.log('Account requirements updated:', event);
        break;

      default:
        console.log(`[Webhooks] Unhandled event: ${event.type}`);
    }

    res.json({ received: true });
  } catch (error: any) {
    console.error('[Webhooks] Error processing webhook event:', error.message);
    res.status(500).json({ error: error.message });
  }
});

export default router;
