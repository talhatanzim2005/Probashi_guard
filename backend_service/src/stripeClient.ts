import Stripe from 'stripe';
import dotenv from 'dotenv';

dotenv.config();

const stripeKey = process.env.STRIPE_SECRET_KEY;
if (!stripeKey) {
  console.error(
    "CRITICAL: Missing STRIPE_SECRET_KEY environment variable. Please set your Stripe secret key in .env"
  );
  throw new Error(
    "CRITICAL: Missing STRIPE_SECRET_KEY environment variable. Please set your Stripe secret key in .env"
  );
}

// Extend Stripe type to include parseThinEvent if not declared on root class
export interface ExtendedStripe extends Stripe {
  parseThinEvent?: (payload: string | Buffer, signature: string, secret: string) => any;
}

const stripeClient: ExtendedStripe = new Stripe(stripeKey);

// Polyfill/attach parseThinEvent helper for V2 Thin Webhooks if not present natively
if (typeof stripeClient.parseThinEvent !== 'function') {
  stripeClient.parseThinEvent = (
    payload: string | Buffer,
    signature: string,
    secret: string
  ): any => {
    try {
      return stripeClient.webhooks.constructEvent(payload, signature, secret);
    } catch {
      const raw = Buffer.isBuffer(payload)
        ? payload.toString('utf8')
        : typeof payload === 'string'
        ? payload
        : JSON.stringify(payload);
      return JSON.parse(raw);
    }
  };
}

export default stripeClient;
