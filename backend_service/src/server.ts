import express, { Request, Response } from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import connectRoutes from './routes/connect.js';
import webhookRoutes from './routes/webhooks.js';
import checkoutRoutes from './routes/checkout.js';
import paymentRoutes from './routes/payment.js';
import documentRoutes from './routes/documents.js';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3000;

// Enable CORS for Flutter web / mobile clients and dev origin
app.use(cors());

// Mounted before the global parsers: it parses its own (image) bodies and turns
// an oversized photo into a clear 413 instead of a generic error.
app.use('/api/documents', documentRoutes);

// Middleware to capture rawBody for webhook signature verification while parsing JSON.
// Standard 2mb limit for general JSON routes (documents handles its own larger limit).
app.use(
  express.json({
    limit: '2mb',
    verify: (req: any, _res, buf) => {
      req.rawBody = buf;
    },
  })
);

// Form data middleware
app.use(express.urlencoded({ limit: '2mb', extended: true }));

// Health check
app.get('/api/health', (_req: Request, res: Response) => {
  res.json({
    status: 'ok',
    service: 'Probashi Guard Stripe Connect Service',
    timestamp: new Date().toISOString(),
  });
});

// Post-checkout success landing page
app.get('/success', (req: Request, res: Response) => {
  const sessionId = req.query.session_id as string;
  res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Remittance Successful</title>
  <style>
    /* Palette: Cloud Dancer #F5F2EB, Royal Blue #1A4B9C, Emerald #1E824C, Crimson #D32F2F, ink #040303. */
    body { font-family: system-ui, -apple-system, sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; background: #F5F2EB; color: #040303; text-align: center; }
    .card { background: #F5F2EB; padding: 40px; border-radius: 20px; border: 1px solid rgba(26, 75, 156, 0.18); max-width: 400px; box-shadow: 0 10px 30px rgba(4, 3, 3, 0.10); }
    .icon { font-size: 54px; color: #1E824C; margin-bottom: 16px; }
    h1 { font-size: 22px; font-weight: 800; margin-bottom: 8px; color: #1A4B9C; }
    p { color: rgba(4, 3, 3, 0.7); font-size: 14px; font-weight: 600; margin-bottom: 24px; line-height: 1.5; }
    .btn { display: inline-block; background: #1E824C; color: #F5F2EB; padding: 12px 24px; border-radius: 12px; text-decoration: none; font-weight: 800; cursor: pointer; }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">✓</div>
    <h1>Remittance Verified</h1>
    <p>Your payment session ${sessionId ? `(${sessionId.slice(0, 16)}...)` : ''} has been completed successfully. You may return to the Probashi Guard app.</p>
    <a href="probashiguard://checkout/success?session_id=${sessionId || ''}" class="btn">Return to App</a>
  </div>
</body>
</html>`);
});

// Post-checkout cancellation landing page
app.get('/cancel', (_req: Request, res: Response) => {
  res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Checkout Cancelled</title>
  <style>
    /* Palette: Cloud Dancer #F5F2EB, Royal Blue #1A4B9C, Emerald #1E824C, Crimson #D32F2F, ink #040303. */
    body { font-family: system-ui, -apple-system, sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; background: #F5F2EB; color: #040303; text-align: center; }
    .card { background: #F5F2EB; padding: 40px; border-radius: 20px; border: 1px solid rgba(26, 75, 156, 0.18); max-width: 400px; box-shadow: 0 10px 30px rgba(4, 3, 3, 0.10); }
    .icon { font-size: 54px; color: #D32F2F; margin-bottom: 16px; }
    h1 { font-size: 22px; font-weight: 800; margin-bottom: 8px; color: #1A4B9C; }
    p { color: rgba(4, 3, 3, 0.7); font-size: 14px; font-weight: 600; margin-bottom: 24px; }
    .btn { display: inline-block; background: #1A4B9C; color: #F5F2EB; padding: 12px 24px; border-radius: 12px; text-decoration: none; font-weight: 800; cursor: pointer; }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">✕</div>
    <h1>Checkout Cancelled</h1>
    <p>The remittance checkout session was cancelled. No charges were made to your account.</p>
    <a href="probashiguard://checkout/cancel" class="btn">Return to App</a>
  </div>
</body>
</html>`);
});

// Mount Routes
app.use('/api/connect', connectRoutes);
app.use('/api/webhooks', webhookRoutes);
app.use('/api/checkout', checkoutRoutes);
app.use('/api/products', checkoutRoutes); // Also mount at /api/products for /api/products/create
app.use('/api/payment', paymentRoutes);
app.use('/api', checkoutRoutes); // Mounts /api/rates directly

// Global Error Handler
app.use((err: any, _req: Request, res: Response, _next: any) => {
  console.error('Unhandled server error:', err);
  res.status(500).json({ error: err.message || 'Internal Server Error' });
});

// Start listening if run directly and not in test environment
const isTestEnv = process.env.NODE_ENV === 'test' ||
  process.argv.some(arg => arg.includes('test')) ||
  process.execArgv.some(arg => arg.includes('test'));

if (!isTestEnv) {
  app.listen(PORT, () => {
    console.log(`[Stripe Connect Backend] Listening on http://localhost:${PORT}`);
    console.log(`- Health Check: http://localhost:${PORT}/api/health`);
    console.log(`- Connected Accounts: POST http://localhost:${PORT}/api/connect/create-account`);
    console.log(`- Account Onboarding: POST http://localhost:${PORT}/api/connect/account-link`);
    console.log(`- Account Status: GET http://localhost:${PORT}/api/connect/account-status/:accountId`);
    console.log(`- Thin Webhooks: POST http://localhost:${PORT}/api/webhooks/stripe`);
    console.log(`- Destination Checkout: POST http://localhost:${PORT}/api/checkout/destination-charge`);
    console.log(`- Document Scanner: POST http://localhost:${PORT}/api/documents/scan`);
    console.log(`- Passport MRZ (on-device): POST http://localhost:${PORT}/api/documents/mrz`);
  });
}

export default app;
