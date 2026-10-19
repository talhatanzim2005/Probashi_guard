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
  // express.raw() on this path leaves req.body as the untouched Buffer; rawBody
  // is the fallback for anything that reached here through the JSON parser. A
  // plain object would mean neither ran, and re-serialising it would produce a
  // signature mismatch dressed up as a verification failure, so refuse instead.
  const rawBody = Buffer.isBuffer(req.body)
    ? req.body
    : ((req as any).rawBody as Buffer | undefined);
  if (!Buffer.isBuffer(rawBody)) {
    console.error('[Webhooks] Raw request body unavailable; cannot verify signature.');
    return res.status(400).json({ error: 'Raw body required for signature verification' });
  }

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
      return res.status(400).json({ error: 'Webhook signature verification failed' });
    }
  }

  try {
    console.log(`[Webhooks] Processing Stripe event: ${event.type}`);

    switch (event.type) {
      case 'checkout.session.completed': {
        const session = event.data?.object || event.object;
        const metadata = session.metadata || {};
        console.log(`[Webhooks] Checkout session completed: ${session.id}`);

        // Card-to-card moves are settled by the app once it sees the session
        // paid; there is no beneficiary to credit here.
        if (metadata.kind === 'card_transfer') {
          console.log(`[Webhooks] Card transfer session paid: ${session.id}`);
          break;
        }

        const cardId = metadata.cardId || 'card_wps';
        // Derive the amount from session.amount_total, which Stripe signed, and
        // never from a client-supplied figure. That total is in USD now, so it
        // is converted with the rate recorded on the session at creation time.
        const usdCharged = session.amount_total ? session.amount_total / 100 : 0;
        const usdToBdt = Number(metadata.usdToBdt) || 119.5;
        if (usdCharged <= 0) {
          // No signed total means nothing can be credited. The old fallback
          // here read metadata.amountBdt, which the client had supplied, so a
          // zero-total session could book an arbitrary balance.
          console.error(
            `[Webhooks] Session ${session.id} has no amount_total; nothing credited`
          );
          break;
        }
        const amountBdt = usdCharged * usdToBdt;
        // Calculate official 2.5% Bangladesh government incentive based on verified amount, not client metadata.
        const incentiveBdt = Math.round(amountBdt * 0.025 * 100) / 100;
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

        // Credit the payer's wallet. deposit_to_wallet() is the only way a
        // balance can go up: it locks the wallet row, snapshots
        // balance_before / balance_after and writes the ledger entry, none of
        // which a direct table write does.
        //
        // What was here before wrote amount_bdt / balance_bdt straight onto
        // `transactions` and `wallets`. Those columns now exist only on the
        // renamed *_legacy_20261019 tables, so funding had stopped working
        // entirely — every balance stayed at zero.
        const supabaseUrl = process.env.SUPABASE_URL;
        // Must be the service-role key: deposit_to_wallet is granted to
        // service_role alone, so the anon key would be rejected.
        const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
        const payerUserId = metadata.payerUserId;

        if (!supabaseUrl || !serviceRoleKey) {
          console.warn('[Webhooks] SUPABASE_URL / SERVICE_ROLE_KEY not set; wallet not credited');
        } else if (!payerUserId) {
          // A session created before the app started sending its access token,
          // or by an unauthenticated caller. Guessing an account would credit
          // the wrong wallet, so this is left unbooked and shouted about.
          console.error(
            `[Webhooks] Session ${session.id} carries no payerUserId; wallet NOT credited`
          );
        } else {
          try {
            // The Stripe session id is the idempotency key, so the retries
            // Stripe sends for up to three days credit the wallet once.
            const depositRes = await fetch(`${supabaseUrl}/rest/v1/rpc/deposit_to_wallet`, {
              method: 'POST',
              headers: {
                'apikey': serviceRoleKey,
                'Authorization': `Bearer ${serviceRoleKey}`,
                'Content-Type': 'application/json',
              },
              body: JSON.stringify({
                p_user_id: payerUserId,
                // From session.amount_total, which Stripe signed, never from a
                // client-supplied figure. Rounded to paisa.
                p_amount: Math.round(amountBdt * 100) / 100,
                p_idempotency_key: session.id,
                p_description: `Added from your ${sourceCurrency} card`,
              }),
            });

            if (!depositRes.ok) {
              const body = await depositRes.text();
              // P0003 is deposit_to_wallet's "paid but not credited" — the
              // account has no verified phone. The Checkout gate should have
              // refused this before Stripe charged anything, so reaching here
              // means real money is in limbo and a human has to reconcile it.
              if (body.includes('P0003')) {
                console.error(
                  `[Webhooks] MANUAL RECONCILIATION NEEDED — session ${session.id} ` +
                    `was PAID by user ${payerUserId} but NOT credited (no verified phone). ` +
                    `Refund or verify-and-recredit.`
                );
              } else {
                console.error(
                  '[Webhooks] deposit_to_wallet failed:',
                  depositRes.status,
                  body
                );
              }
            } else {
              console.log(
                `[Webhooks] Wallet credited for session ${session.id}:`,
                JSON.stringify(await depositRes.json())
              );
            }
          } catch (sbErr: any) {
            console.warn('[Webhooks] Supabase deposit warning (non-fatal):', sbErr.message);
          }
        }
        break;
      }

      case 'payment_intent.succeeded': {
        console.log(`[Webhooks] PaymentIntent succeeded: ${event.data?.object?.id}`);
        break;
      }

      case 'v2.core.account[requirements].updated':
        console.log(`[Webhooks] Account requirements updated: ${event.id}`);
        break;

      default:
        console.log(`[Webhooks] Unhandled event: ${event.type}`);
    }

    res.json({ received: true });
  } catch (error: any) {
    console.error('[Webhooks] Error processing webhook event:', error.message);
    res.status(500).json({ error: 'Webhook processing failed' });
  }
});

export default router;
