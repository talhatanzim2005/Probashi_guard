import OpenAI from 'openai';

/**
 * One OpenRouter client for everything that talks to a language model: the
 * Prohori chat and the document scanner. OpenRouter speaks the OpenAI wire
 * format, so the `openai` SDK is pointed at it.
 *
 * Free models come and go (one named in the original plan has since been
 * removed) and answer 429 whenever they are busy, so callers give an ordered
 * list of models and [withModelFallback] walks it.
 */

export const DEFAULT_OPENROUTER_URL = 'https://openrouter.ai/api/v1';

let client: OpenAI | null = null;

export function openRouterConfigured(env: NodeJS.ProcessEnv = process.env): boolean {
  return Boolean(env.OPENROUTER_API_KEY);
}

/** Created on first use, so a missing key answers 503 instead of crashing the server at boot. */
export function getOpenRouter(): OpenAI | null {
  if (client) return client;
  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) return null;
  client = new OpenAI({
    apiKey,
    baseURL: process.env.OPENROUTER_BASE_URL || DEFAULT_OPENROUTER_URL,
    // Retrying is [withModelFallback]'s job; the SDK's own retries would run
    // past the deadline the callers set.
    maxRetries: 0,
    defaultHeaders: {
      // Shown on OpenRouter's dashboard so usage can be told apart.
      'HTTP-Referer': process.env.DOMAIN ? `https://${process.env.DOMAIN}` : 'https://probashiguard.app',
      'X-Title': 'Probashi Guard',
    },
  });
  return client;
}

/** `A,B ,C` becomes [A, B, C]; blank or missing gives [defaults]. */
export function modelList(value: string | undefined, defaults: readonly string[]): string[] {
  const list = (value ?? '')
    .split(',')
    .map((m) => m.trim())
    .filter(Boolean);
  return list.length > 0 ? list : [...defaults];
}

/** A model answered, but not with anything usable (empty, or not the JSON asked for). */
export class ModelOutputError extends Error {}

/** Statuses that mean "this model cannot help right now", so the next one may. */
const TRY_NEXT_STATUSES = new Set([402, 403, 404, 408, 409, 424, 429, 500, 502, 503, 504, 529]);

export function statusOf(err: unknown): number | undefined {
  return err instanceof OpenAI.APIError ? err.status : undefined;
}

function shouldTryNext(err: unknown): boolean {
  if (err instanceof ModelOutputError) return true;
  const status = statusOf(err);
  return status !== undefined && TRY_NEXT_STATUSES.has(status);
}

export interface Served<T> {
  value: T;
  /** The model that actually answered. */
  model: string;
}

/**
 * Tries [models] in order and returns the first answer. A model that is gone,
 * busy, erroring or returning nothing usable moves on to the next; anything
 * else (a bad request, a bad key, the caller's deadline) stops at once, since
 * another model would fail the same way. When every model fails, the last error
 * is thrown, with a 429 preferred so the caller can say "busy".
 */
export async function withModelFallback<T>(
  models: readonly string[],
  attempt: (model: string) => Promise<T>,
  signal?: AbortSignal,
): Promise<Served<T>> {
  let last: unknown;
  let sawBusy: unknown;
  for (const model of models) {
    if (signal?.aborted) break;
    try {
      return { value: await attempt(model), model };
    } catch (err) {
      if (signal?.aborted || !shouldTryNext(err)) throw err;
      console.warn(`[AI] ${model} could not answer (${describe(err)}); trying the next model`);
      last = err;
      if (statusOf(err) === 429) sawBusy = err;
    }
  }
  if (signal?.aborted) throw signal.reason ?? new Error('aborted');
  throw sawBusy ?? last ?? new Error('No model is configured');
}

function describe(err: unknown): string {
  const status = statusOf(err);
  if (status !== undefined) return `HTTP ${status}`;
  return err instanceof Error ? err.message.slice(0, 80) : 'error';
}
