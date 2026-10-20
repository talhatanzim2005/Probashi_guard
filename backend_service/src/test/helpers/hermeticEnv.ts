/**
 * Import this FIRST in every hermetic test file:
 *
 *   import './helpers/hermeticEnv.js';
 *   import app from '../server.js';
 *
 * It pins every environment variable the backend reads to a fake value before
 * the server (and the Stripe client, which throws without a key) is loaded.
 * `dotenv` never overrides a variable that is already set, so nothing in
 * backend_service/.env can leak in: a hermetic test cannot reach the real
 * Stripe, Supabase, OpenRouter or Firebase accounts, however the keys on this
 * machine are configured. Empty strings are used instead of `delete`, because
 * dotenv would refill a deleted variable from .env.
 *
 * node:test runs each test file in its own process, so this affects only the
 * files that import it. The fake Supabase / OpenRouter servers in
 * fakeServices.ts overwrite SUPABASE_URL / OPENROUTER_BASE_URL with their real
 * (random) port when they start.
 */
export const HERMETIC = {
  stripeWebhookSecret: 'whsec_hermetic_test_secret',
  supabaseAnonKey: 'anon-key-hermetic',
  supabaseServiceKey: 'service-key-hermetic',
  firebaseProjectId: 'hermetic-project',
  analysisSecret: 'hermetic-analysis-signing-secret',
  /** The ten Firebase console test numbers from README / SETUP §3.2. */
  testPhones: Array.from({ length: 10 }, (_, i) => `+880170000000${i}`),
  /** The one fixed verification code Firebase accepts for every test number. */
  testCode: '123456',
} as const;

const env = process.env;
env.NODE_ENV = 'test';
env.STRIPE_SECRET_KEY = 'sk_test_hermetic_not_a_real_key';
env.STRIPE_PUBLISHABLE_KEY = '';
env.STRIPE_TEST_ACCOUNT_ID = '';
env.STRIPE_WEBHOOK_SECRET = HERMETIC.stripeWebhookSecret;
env.TRIGGER_SECRET_KEY = '';
env.SUPABASE_URL = 'http://127.0.0.1:9';
env.SUPABASE_ANON_KEY = HERMETIC.supabaseAnonKey;
env.SUPABASE_SERVICE_ROLE_KEY = HERMETIC.supabaseServiceKey;
env.OPENROUTER_API_KEY = 'or-key-hermetic';
env.OPENROUTER_BASE_URL = 'http://127.0.0.1:9';
env.DOCUMENT_MODELS = 'model-a,model-b';
env.DOCUMENT_MODEL = '';
env.CHAT_MODELS = '';
env.CHAT_MODEL = '';
env.FIREBASE_PROJECT_ID = HERMETIC.firebaseProjectId;
env.FIREBASE_TEST_PHONES = HERMETIC.testPhones.join(',');
env.ANALYSIS_SIGNING_SECRET = HERMETIC.analysisSecret;
env.DEV_AUTH_BYPASS = '';
env.DEV_AUTH_BYPASS_TOKEN = '';
env.DEV_AUTH_BYPASS_USER_ID = '';
env.DOMAIN = 'http://localhost:3000';
env.CORS_ORIGINS = '';
