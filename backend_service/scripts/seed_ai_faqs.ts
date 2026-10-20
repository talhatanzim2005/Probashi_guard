import dotenv from 'dotenv';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { embedPassage, embeddingModelName, EMBEDDING_DIMENSIONS } from '../src/ai/embeddings.js';
import { FaqChunk, FaqLanguage, parseFaqDocument } from '../src/ai/faqParser.js';
import { FaqRow, knowledgeBaseConfigured, replaceFaqs } from '../src/ai/faqStore.js';

dotenv.config();

/**
 * Fills Prohori's knowledge base (`faq_embeddings`) from the two AI flow
 * documents in instruction/:
 *
 *   probashi_guard_ai_flow_english.txt   39 questions
 *   probashi_guard_ai_flow_bangla.txt    39 questions
 *
 * Each question with its answer is one chunk; each chunk gets a 384-number
 * vector from the local embedding model (no API, no cost). Safe to run again:
 * a question is written under a stable key, so it is updated, never duplicated,
 * and a question deleted from the documents is removed from the table.
 *
 *   npm run seed:faqs              parse, embed and write
 *   npm run seed:faqs -- --dry-run  parse and embed, write nothing
 *
 * Needs supabase/migrations/20261020120000_faq_embeddings.sql applied, and
 * SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY in .env (the table is closed to the
 * app, so only the service role can write it).
 *
 * The first run downloads the embedding model (about 120 MB for the default
 * multilingual one) from the Hugging Face hub; later runs reuse the cached copy.
 */

const DOCUMENTS: { file: string; language: FaqLanguage }[] = [
  { file: 'probashi_guard_ai_flow_english.txt', language: 'en' },
  { file: 'probashi_guard_ai_flow_bangla.txt', language: 'bn' },
];

// scripts/ sits one level under backend_service/, which sits under the repo root.
const DOCUMENTS_DIR = path.resolve(__dirname, '..', '..', 'instruction');

async function main() {
  const dryRun = process.argv.includes('--dry-run');
  const model = embeddingModelName();

  if (!dryRun && !knowledgeBaseConfigured()) {
    console.error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set in backend_service/.env.');
    process.exit(1);
  }

  const chunks: FaqChunk[] = [];
  for (const { file, language } of DOCUMENTS) {
    const parsed = parseFaqDocument(readFileSync(path.join(DOCUMENTS_DIR, file), 'utf8'), language);
    console.log(`${file}: ${parsed.length} questions`);
    chunks.push(...parsed);
  }

  console.log(`Embedding ${chunks.length} chunks with ${model} (first run downloads the model)...`);
  const rows: FaqRow[] = [];
  for (const [i, chunk] of chunks.entries()) {
    const embedding = await embedPassage(chunk.content);
    if (embedding.length !== EMBEDDING_DIMENSIONS) {
      throw new Error(`${chunk.key}: got ${embedding.length} dimensions, expected ${EMBEDDING_DIMENSIONS}`);
    }
    rows.push({ chunk, embedding });
    if ((i + 1) % 10 === 0 || i + 1 === chunks.length) console.log(`  ${i + 1}/${chunks.length}`);
  }

  if (dryRun) {
    console.log('\n--dry-run: nothing was written. First three chunks:');
    for (const { chunk } of rows.slice(0, 3)) {
      console.log(`  ${chunk.key} [${chunk.section}]\n    ${chunk.question}`);
    }
    return;
  }

  const { written, removed } = await replaceFaqs(rows, model);
  console.log(`\nDone: ${written} questions written, ${removed} stale removed.`);
}

main().catch((err) => {
  console.error('\nSeeding failed:', err instanceof Error ? err.message : err);
  process.exit(1);
});
