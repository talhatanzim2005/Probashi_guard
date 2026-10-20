import test from 'node:test';
import assert from 'node:assert';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { EMBEDDING_DIMENSIONS, embedPassage, embedQuery, embeddingModelName } from '../ai/embeddings.js';
import { parseFaqDocument } from '../ai/faqParser.js';

/**
 * Runs the real embedding model over the real FAQ documents. Off by default:
 * the first run downloads the model (about 120 MB), which a plain `npm test`
 * should not need the network for. Run it when the model is changed:
 *
 *   EMBEDDING_LIVE_TEST=1 npm test
 *
 * It exists because the model first named for this feature (all-MiniLM-L6-v2,
 * English only) scored 12/12 on English questions and 0/12 on Bangla ones.
 */
const live = process.env.EMBEDDING_LIVE_TEST === '1';
const DOCS = path.resolve(__dirname, '..', '..', '..', 'instruction');

const chunks = [
  ...parseFaqDocument(readFileSync(path.join(DOCS, 'probashi_guard_ai_flow_english.txt'), 'utf8'), 'en'),
  ...parseFaqDocument(readFileSync(path.join(DOCS, 'probashi_guard_ai_flow_bangla.txt'), 'utf8'), 'bn'),
];

// A paraphrase of one stored question, and which question (same number in both languages) answers it.
const QUESTIONS: { language: 'en' | 'bn'; text: string; answer: string }[] = [
  { language: 'en', text: 'my employer wants me to put my thumbprint on an empty paper', answer: 's3-q2' },
  { language: 'en', text: 'how do I send money to my family', answer: 's4-q2' },
  { language: 'en', text: 'where can I see my balance', answer: 's4-q1' },
  { language: 'en', text: 'the police took cash from my pocket', answer: 's3-q13' },
  { language: 'bn', text: 'মালিক ফাঁকা কাগজে টিপসই দিতে বলছে', answer: 's3-q2' },
  { language: 'bn', text: 'পরিবারকে টাকা কীভাবে পাঠাবো', answer: 's4-q2' },
  { language: 'bn', text: 'আমার ব্যালেন্স কোথায় দেখব', answer: 's4-q1' },
  { language: 'bn', text: 'পুলিশ পকেট থেকে টাকা নিয়ে গেছে', answer: 's3-q13' },
];

const dot = (a: number[], b: number[]) => a.reduce((sum, x, i) => sum + x * b[i], 0);

test('the embedding model gives 384 unit-length numbers and finds Bangla answers as well as English ones', { skip: !live, timeout: 600_000 }, async () => {
  const vectors = await Promise.all(chunks.map((c) => embedPassage(c.content)));
  assert.ok(vectors.every((v) => v.length === EMBEDDING_DIMENSIONS));
  const norm = Math.sqrt(dot(vectors[0], vectors[0]));
  assert.ok(Math.abs(norm - 1) < 1e-3, `vectors are normalised, got ${norm}`);

  const misses: string[] = [];
  for (const q of QUESTIONS) {
    const query = await embedQuery(q.text);
    const ranked = chunks
      .map((c, i) => ({ key: c.key, score: dot(query, vectors[i]) }))
      .sort((a, b) => b.score - a.score);
    // The chat gives the model the three closest entries, so that is what has to
    // contain the answer. The English and Bangla entry for a question both count.
    const top = ranked.slice(0, 3).map((r) => r.key);
    if (!top.some((key) => key.endsWith(q.answer))) misses.push(`${q.language}: "${q.text}" -> ${top.join(', ')}`);
  }
  assert.deepStrictEqual(misses, [], `${embeddingModelName()} missed:\n${misses.join('\n')}`);
});
