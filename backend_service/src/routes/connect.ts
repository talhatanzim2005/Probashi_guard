import { Router, Request, Response } from 'express';
import stripeClient from '../stripeClient.js';

const router = Router();

/**
 * POST /api/connect/create-account
 * Create a V2 Core connected account where platform manages pricing and fee collection.
 */
router.post('/create-account', async (req: Request, res: Response) => {
  try {
    const { displayName, email, country } = req.body;

    // Do NOT pass top-level type: 'express', 'standard', or 'custom'.
    const account = await (stripeClient.v2.core.accounts as any).create({
      display_name: displayName || 'Probashi Expatriate Partner',
      contact_email: email,
      identity: {
        country: country || 'us',
      },
      dashboard: 'express',
      defaults: {
        responsibilities: {
          fees_collector: 'application',
          losses_collector: 'application',
        },
      },
      configuration: {
        merchant: {
          capabilities: {
            card_payments: {
              requested: true,
            },
          },
        },
        recipient: {
          capabilities: {
            stripe_balance: {
              stripe_transfers: {
                requested: true,
              },
            },
          },
        },
      },
    });

    res.status(201).json({ accountId: account.id });
  } catch (error: any) {
    console.error('Error creating V2 connected account:', error);
    res.status(500).json({
      error: error.message || 'Failed to create connected account',
    });
  }
});

/**
 * POST /api/connect/account-link
 * Generate an onboarding link for the V2 connected account.
 */
router.post('/account-link', async (req: Request, res: Response) => {
  try {
    const { accountId } = req.body;
    if (!accountId) {
      return res.status(400).json({ error: 'Missing accountId in request body' });
    }

    const origin = req.headers.origin || 'http://localhost:3000';
    const accountLink = await (stripeClient.v2.core.accountLinks as any).create({
      account: accountId,
      use_case: {
        type: 'account_onboarding',
        account_onboarding: {
          configurations: ['recipient'],
          refresh_url: `${origin}/onboard/refresh`,
          return_url: `${origin}/onboard/complete?accountId=${accountId}`,
        },
      },
    });

    res.json({ url: accountLink.url });
  } catch (error: any) {
    console.error('Error creating account link:', error);
    res.status(500).json({
      error: error.message || 'Failed to create account link',
    });
  }
});

/**
 * GET /api/connect/account-status/:accountId
 * Dynamically retrieve real-time status directly from Stripe API.
 */
router.get('/account-status/:accountId', async (req: Request, res: Response) => {
  try {
    const { accountId } = req.params;
    if (!accountId) {
      return res.status(400).json({ error: 'Missing accountId parameter' });
    }

    const account = await (stripeClient.v2.core.accounts as any).retrieve(accountId, {
      include: ['configuration.recipient', 'requirements'],
    });

    const readyToReceivePayments =
      account?.configuration?.recipient?.capabilities?.stripe_balance?.stripe_transfers?.status ===
      'active';
    const requirementsStatus =
      account.requirements?.summary?.minimum_deadline?.status;
    const onboardingComplete =
      requirementsStatus !== 'currently_due' && requirementsStatus !== 'past_due';

    res.json({
      readyToReceivePayments,
      onboardingComplete,
      details: account,
    });
  } catch (error: any) {
    console.error('Error retrieving account status:', error);
    res.status(500).json({
      error: error.message || 'Failed to retrieve account status',
    });
  }
});

export default router;
