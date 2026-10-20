import express, { Request, Response, Router } from 'express';
import { embeddingModelName, embedQuery, matchThreshold } from '../ai/embeddings.js';
import { FaqMatch, knowledgeBaseConfigured, matchFaqs } from '../ai/faqStore.js';
import { ModelOutputError, getOpenRouter, modelList, statusOf, withModelFallback } from '../ai/openrouter.js';
import { ChatMessage, buildChatMessages, parseChatLanguage, plainText } from '../ai/prohori.js';
import { rateLimit } from '../rateLimit.js';
import { requireAuth } from '../supabaseUser.js';

/**
 * POST /api/chat: Prohori, the in-app AI assistant.
 *
 *   1. the question becomes a vector, locally (no API call);
 *   2. Supabase's match_faqs() returns the closest FAQ entries;
 *   3. an OpenRouter free model phrases an answer from those entries only.
 *
 * Body:    { message: string, language?: "bn" | "en" }   (language is guessed from
 *          the script when it is missing)
 * Header:  Authorization: Bearer <Supabase access token>
 * Answer:  { reply: string, matched: number, model: string }
 */

/** The free Nemotron the plan asked for has been withdrawn from OpenRouter; these are live ones. */
const DEFAULT_CHAT_MODELS = [
  'nvidia/nemotron-3-ultra-550b-a55b:free',
  'google/gemma-4-26b-a4b-it:free',
  'google/gemma-4-31b-it:free',
];

/** How many FAQ entries are put in front of the model. */
const MATCH_COUNT = 3;
const MAX_MESSAGE_LENGTH = 1000;
/** The app gives up at 60 s, so the server answers first and says why. */
const ANSWER_DEADLINE_MS = 55_000;
/** Room for a short answer, plus the thinking a reasoning model does first. */
const MAX_ANSWER_TOKENS = 1500;

/** Everything the route needs from outside, so tests can stand in for it. */
export interface ChatDeps {
  /** False when OpenRouter or Supabase is not set up on this server. */
  configured(): boolean;
  embedQuery(text: string): Promise<number[]>;
  matchFaqs(
    embedding: readonly number[],
    options: { threshold: number; count: number },
  ): Promise<FaqMatch[]>;
  complete(
    messages: ChatMessage[],
    models: string[],
    signal: AbortSignal,
  ): Promise<{ reply: string; model: string }>;
}

export async function completeWithOpenRouter(
  messages: ChatMessage[],
  models: string[],
  signal: AbortSignal,
): Promise<{ reply: string; model: string }> {
  const ai = getOpenRouter();
  if (!ai) throw new Error('OPENROUTER_API_KEY is not set');
  const served = await withModelFallback(
    models,
    async (model) => {
      const response = await ai.chat.completions.create(
        {
          model,
          messages,
          max_tokens: MAX_ANSWER_TOKENS,
          temperature: 0.2,
          reasoning_effort: 'low',
        },
        { signal, timeout: ANSWER_DEADLINE_MS },
      );
      const reply = plainText(response.choices?.[0]?.message?.content ?? '');
      if (!reply) throw new ModelOutputError('The model returned an empty answer');
      return reply;
    },
    signal,
  );
  return { reply: served.value, model: served.model };
}

const defaultDeps: ChatDeps = {
  configured: () => Boolean(getOpenRouter()) && knowledgeBaseConfigured(),
  embedQuery,
  matchFaqs,
  complete: completeWithOpenRouter,
};

let warnedAboutModel = false;

export function createChatRouter(deps: ChatDeps = defaultDeps): Router {
  const router = Router();

  router.post(
    '/',
    express.json({ limit: '16kb' }),
    requireAuth,
    // A signed-in account cannot spend the free-model quota for everyone.
    rateLimit({ name: 'chat', max: 12, windowMs: 60_000 }),
    async (req: Request, res: Response) => {
      const message = typeof req.body?.message === 'string' ? req.body.message.trim() : '';
      if (!message) return res.status(400).json({ error: 'message is required' });
      if (message.length > MAX_MESSAGE_LENGTH) {
        return res.status(400).json({ error: `message is too long (max ${MAX_MESSAGE_LENGTH} characters)` });
      }
      const language = parseChatLanguage(req.body?.language, message);

      if (!deps.configured()) {
        console.error('[Chat] OPENROUTER_API_KEY or the Supabase service-role key is not set');
        return res.status(503).json({ error: 'Prohori is not configured on the server.' });
      }

      // 1 + 2: find the closest FAQ entries.
      let matches: FaqMatch[];
      try {
        const vector = await deps.embedQuery(message);
        matches = await deps.matchFaqs(vector, { threshold: matchThreshold(), count: MATCH_COUNT });
      } catch (err) {
        console.error('[Chat] Knowledge lookup failed:', err instanceof Error ? err.message : err);
        return res.status(503).json({ error: 'Prohori is not available right now. Please try again later.' });
      }

      // Vectors from different models cannot be compared. If the table was built
      // by another model, the matches are noise: say so rather than answer from them.
      const expected = embeddingModelName();
      if (matches.some((m) => m.embedding_model !== expected)) {
        if (!warnedAboutModel) {
          warnedAboutModel = true;
          console.error(
            `[Chat] faq_embeddings was built with a different embedding model than ${expected}. ` +
              'Run `npm run seed:faqs` to rebuild it.',
          );
        }
        return res.status(503).json({ error: 'Prohori is not available right now. Please try again later.' });
      }

      // 3: phrase the answer.
      const deadline = AbortSignal.timeout(ANSWER_DEADLINE_MS);
      const models = modelList(process.env.CHAT_MODELS || process.env.CHAT_MODEL, DEFAULT_CHAT_MODELS);
      try {
        const { reply, model } = await deps.complete(buildChatMessages(message, language, matches), models, deadline);
        return res.json({ reply, matched: matches.length, model });
      } catch (err) {
        if (deadline.aborted) {
          return res.status(504).json({ error: 'Prohori took too long to answer. Please try again.' });
        }
        const status = statusOf(err);
        if (status === 429) {
          return res.status(429).json({ error: 'Prohori is busy right now. Please try again in a minute.' });
        }
        if (status === 401) console.error('[Chat] OpenRouter rejected the API key (401)');
        else console.error('[Chat] Model request failed:', err instanceof Error ? err.message : err);
        return res.status(status === 401 ? 503 : 502).json({ error: 'Prohori could not answer that. Please try again.' });
      }
    },
  );

  return router;
}

export default createChatRouter();
