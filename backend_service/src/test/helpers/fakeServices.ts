import http from 'node:http';
import type { AddressInfo } from 'node:net';
import type { Express } from 'express';
import { HERMETIC } from './hermeticEnv.js';

/**
 * In-process stand-ins for the services backend_service talks to over HTTP, so
 * the real route code can be driven end to end with nothing leaving the
 * machine. They speak only as much of each protocol as the backend uses.
 */

export type Recorded = {
  method: string;
  path: string;
  query: URLSearchParams;
  headers: http.IncomingHttpHeaders;
  body: any;
};

async function readBody(req: http.IncomingMessage): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk as Buffer);
  return Buffer.concat(chunks).toString('utf8');
}

function listen(handler: (req: http.IncomingMessage, res: http.ServerResponse) => void) {
  return new Promise<{ server: http.Server; url: string }>((resolve) => {
    const server = http.createServer(handler);
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address() as AddressInfo;
      resolve({ server, url: `http://127.0.0.1:${port}` });
    });
  });
}

function sendJson(res: http.ServerResponse, status: number, payload: unknown) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(payload));
}

async function record(req: http.IncomingMessage): Promise<Recorded> {
  const url = new URL(req.url ?? '/', 'http://fake');
  const raw = await readBody(req);
  let body: any;
  try {
    body = raw ? JSON.parse(raw) : undefined;
  } catch {
    body = raw;
  }
  return { method: req.method ?? 'GET', path: url.pathname, query: url.searchParams, headers: req.headers, body };
}

// ---------------------------------------------------------------------------
// Supabase: GoTrue's /auth/v1/user and the PostgREST routes backend_service calls.
// ---------------------------------------------------------------------------

export class FakeSupabase {
  readonly requests: Recorded[] = [];
  /** Access token -> the account it belongs to. */
  readonly tokens = new Map<string, { id: string; anonymous: boolean }>();
  /** User ids whose profile has `phone_verified_at` set. */
  readonly verifiedUsers = new Set<string>();
  /** Rows POSTed to /rest/v1/saved_documents. */
  readonly savedDocuments: any[] = [];

  settleMode: 'ok' | 'fail' | 'p0003' = 'ok';
  bindMode: 'ok' | 'taken' | 'error' = 'ok';
  /** Makes the profile lookup answer 500, as an outage would. */
  profilesDown = false;
  /** Makes the saved_documents insert answer 500. */
  documentsDown = false;

  private readonly settled = new Set<string>();
  private server?: http.Server;
  url = '';

  async start(): Promise<string> {
    const { server, url } = await listen(async (req, res) => {
      const r = await record(req);
      this.requests.push(r);
      this.route(r, res);
    });
    this.server = server;
    this.url = url;
    process.env.SUPABASE_URL = url;
    return url;
  }

  async stop() {
    await new Promise<void>((resolve) => this.server?.close(() => resolve()) ?? resolve());
  }

  /** Registers a signed-in (or anonymous) account and returns its access token. */
  addAccount(name: string, opts: { verified?: boolean; anonymous?: boolean } = {}) {
    const id = `00000000-0000-4000-8000-${Buffer.from(name).toString('hex').padEnd(12, '0').slice(0, 12)}`;
    const token = `tok-${name}`;
    this.tokens.set(token, { id, anonymous: opts.anonymous ?? false });
    if (opts.verified) this.verifiedUsers.add(id);
    return { id, token, headers: { Authorization: `Bearer ${token}` } as Record<string, string> };
  }

  calls(pathSuffix: string): Recorded[] {
    return this.requests.filter((r) => r.path.endsWith(pathSuffix));
  }

  reset() {
    this.requests.length = 0;
    this.savedDocuments.length = 0;
    this.settled.clear();
    this.settleMode = 'ok';
    this.bindMode = 'ok';
    this.profilesDown = false;
    this.documentsDown = false;
  }

  private isServiceCall(r: Recorded) {
    const key = HERMETIC.supabaseServiceKey;
    return r.headers.apikey === key && r.headers.authorization === `Bearer ${key}`;
  }

  private route(r: Recorded, res: http.ServerResponse) {
    if (r.method === 'GET' && r.path === '/auth/v1/user') {
      const token = String(r.headers.authorization ?? '').replace(/^Bearer /, '');
      const account = this.tokens.get(token);
      if (!account) return sendJson(res, 401, { code: 401, msg: 'invalid JWT' });
      return sendJson(res, 200, { id: account.id, is_anonymous: account.anonymous });
    }

    if (r.method === 'GET' && r.path === '/rest/v1/profiles') {
      if (!this.isServiceCall(r)) return sendJson(res, 401, { message: 'permission denied' });
      if (this.profilesDown) return sendJson(res, 500, { message: 'database unavailable' });
      const id = (r.query.get('user_id') ?? '').replace(/^eq\./, '');
      return sendJson(res, 200, this.verifiedUsers.has(id) ? [{ phone_verified_at: '2026-10-20T00:00:00Z' }] : []);
    }

    if (r.method === 'POST' && r.path === '/rest/v1/rpc/settle_remittance') {
      if (!this.isServiceCall(r)) return sendJson(res, 401, { message: 'permission denied for function settle_remittance' });
      if (this.settleMode === 'fail') return sendJson(res, 500, { message: 'boom' });
      if (this.settleMode === 'p0003') return sendJson(res, 400, { code: 'P0003', message: 'Paid but not credited' });
      const repeated = this.settled.has(r.body?.p_session_id);
      this.settled.add(r.body?.p_session_id);
      return sendJson(res, 200, { amount: r.body?.p_amount_bdt, repeated });
    }

    if (r.method === 'POST' && r.path === '/rest/v1/rpc/bind_verified_phone') {
      if (!this.isServiceCall(r)) return sendJson(res, 401, { message: 'permission denied for function bind_verified_phone' });
      if (this.bindMode === 'taken') {
        return sendJson(res, 409, { code: '23505', message: 'Another account has already verified that number' });
      }
      if (this.bindMode === 'error') return sendJson(res, 500, { message: 'boom' });
      return sendJson(res, 200, { phone: r.body?.p_phone, verified: true, shared: !!r.body?.p_shared });
    }

    if (r.method === 'POST' && r.path === '/rest/v1/saved_documents') {
      if (!this.isServiceCall(r)) return sendJson(res, 401, { message: 'permission denied' });
      if (this.documentsDown) return sendJson(res, 500, { message: 'database unavailable' });
      this.savedDocuments.push(r.body);
      return sendJson(res, 201, [{ id: `doc-${this.savedDocuments.length}` }]);
    }

    sendJson(res, 404, { message: `fake supabase has no route for ${r.method} ${r.path}` });
  }
}

// ---------------------------------------------------------------------------
// OpenRouter: POST /chat/completions in the OpenAI wire format.
// ---------------------------------------------------------------------------

export type ModelReply = { status?: number; content?: string; finish_reason?: string };

export class FakeOpenRouter {
  readonly requests: Recorded[] = [];
  /** Replies handed out in order; when it runs dry, [fallback] is used. */
  queue: ModelReply[] = [];
  fallback: ModelReply = { content: '{}' };
  private server?: http.Server;
  url = '';

  async start(): Promise<string> {
    const { server, url } = await listen(async (req, res) => {
      const r = await record(req);
      this.requests.push(r);
      if (r.method !== 'POST' || !r.path.endsWith('/chat/completions')) {
        return sendJson(res, 404, { error: { message: 'not found' } });
      }
      const next = this.queue.shift() ?? this.fallback;
      if (next.status && next.status >= 400) {
        return sendJson(res, next.status, { error: { message: `fake model error ${next.status}`, code: next.status } });
      }
      sendJson(res, 200, {
        id: 'chatcmpl-hermetic',
        object: 'chat.completion',
        created: Math.floor(Date.now() / 1000),
        model: r.body?.model,
        choices: [
          {
            index: 0,
            message: { role: 'assistant', content: next.content ?? '' },
            finish_reason: next.finish_reason ?? 'stop',
          },
        ],
      });
    });
    this.server = server;
    this.url = url;
    process.env.OPENROUTER_BASE_URL = url;
    return url;
  }

  async stop() {
    await new Promise<void>((resolve) => this.server?.close(() => resolve()) ?? resolve());
  }

  reset() {
    this.requests.length = 0;
    this.queue = [];
    this.fallback = { content: '{}' };
  }
}

// ---------------------------------------------------------------------------
// The real Express app, on a random port.
// ---------------------------------------------------------------------------

export async function startApp(app: Express) {
  const { server, url } = await new Promise<{ server: http.Server; url: string }>((resolve) => {
    const s = app.listen(0, '127.0.0.1', () => {
      resolve({ server: s, url: `http://127.0.0.1:${(s.address() as AddressInfo).port}` });
    });
  });
  return {
    url,
    close: () => new Promise<void>((resolve) => server.close(() => resolve())),
  };
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/** The smallest bytes the scanner accepts as a JPEG. */
export const JPEG_BASE64 = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0x10, 0x4a, 0x46, 0x49, 0x46]).toString('base64');

/** What a vision model returns for a plain employment contract, before the hard rules run. */
export function contractReply(overrides: Record<string, unknown> = {}) {
  return {
    document_category: 'CONTRACT',
    document_type: 'Employment contract',
    is_legible: true,
    identity: { document_kind: 'other' },
    authenticity: { signature_present: false, stamp_present: false, stamp_kind: 'none', stamp_text: '', notes: '' },
    salary: { amount: 1500, currency: 'SAR', period: 'monthly', monthly_amount: 1500, risk: 'low', explanation: 'Above the floor.' },
    fees: { items: [], risk: 'low', explanation: 'No fees.' },
    duration: { text: '24 months', months: 24 },
    cancellation: { text: 'One month notice.', risk: 'low', explanation: 'Fair.' },
    tip_shoi_detected: false,
    tip_shoi_findings: [],
    verdict: 'SAFE_TO_SIGN',
    summary_3_lines: ['A contract.', 'Terms look normal.', 'Safe to sign.'],
    translation_segments: [{ original: 'Salary SAR 1,500 per month', translated: 'Salary 1,500 riyals a month' }],
    ...overrides,
  };
}
