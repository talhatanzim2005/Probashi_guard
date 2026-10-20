/**
 * Text to vector, on this machine: no API, no key, no cost per call.
 *
 * `@huggingface/transformers` (the successor of `@xenova/transformers`) runs a
 * small sentence-embedding model through ONNX in Node. The model is fetched from
 * the Hugging Face hub the first time and kept on disk after that, then held in
 * memory: loading takes seconds (and the very first download a minute or two),
 * so the pipeline is created once and every caller shares it. The models are
 * still published under the "Xenova/" name on the hub; only the library moved.
 *
 * Which model: the FAQ documents come in Bangla and English and workers ask in
 * either, so the model has to understand Bangla. The plan named
 * Xenova/all-MiniLM-L6-v2, which is English-only: measured on the real documents
 * it found the right answer for 12 of 12 English questions but 0 of 12 Bangla
 * ones (every Bangla question landed on the same unrelated answer, with a high
 * similarity score, so a threshold could not catch it). Xenova/multilingual-e5-small
 * has the same 384 dimensions, so the table is unchanged, and found 12/12 English
 * and 10/12 Bangla (12/12 within the top three). Set EMBEDDING_MODEL to change it;
 * the FAQ table must then be re-seeded (npm run seed:faqs).
 */

/** What `faq_embeddings.embedding` is declared as (`vector(384)`). */
export const EMBEDDING_DIMENSIONS = 384;

/**
 * Which weights to load. 'q8' (8-bit quantized) is what the previous library
 * loaded by default; the current one defaults to full precision. The vectors
 * stored in faq_embeddings were made with q8, and a query is only comparable to
 * them if it is made the same way, so this is pinned. Changing it means
 * re-seeding (npm run seed:faqs).
 */
const EMBEDDING_DTYPE = 'q8';

export const DEFAULT_EMBEDDING_MODEL = 'Xenova/multilingual-e5-small';

/** Quirks of a model family: how it wants its input worded, and what "similar" means for it. */
export interface EmbeddingProfile {
  /** E5 models are trained with these prefixes and score poorly without them. */
  queryPrefix: string;
  passagePrefix: string;
  /**
   * The cosine similarity below which a stored answer is not offered to the
   * language model. Scores are not comparable across models: MiniLM puts
   * unrelated text near 0.1, E5 near 0.75, so each needs its own floor. It is
   * a coarse filter; the language model is told to ignore context that does not
   * answer the question.
   */
  matchThreshold: number;
}

export function embeddingProfile(model: string = embeddingModelName()): EmbeddingProfile {
  if (/e5/i.test(model)) {
    return { queryPrefix: 'query: ', passagePrefix: 'passage: ', matchThreshold: 0.79 };
  }
  return { queryPrefix: '', passagePrefix: '', matchThreshold: 0.3 };
}

/** The floor for this process: FAQ_MATCH_THRESHOLD, else the model's own. */
export function matchThreshold(env: NodeJS.ProcessEnv = process.env): number {
  const set = Number(env.FAQ_MATCH_THRESHOLD);
  return env.FAQ_MATCH_THRESHOLD && Number.isFinite(set) ? set : embeddingProfile().matchThreshold;
}

type Extractor = (
  text: string,
  options: { pooling: 'mean'; normalize: boolean },
) => Promise<{ data: ArrayLike<number> }>;

let extractor: Promise<Extractor> | null = null;

export function embeddingModelName(env: NodeJS.ProcessEnv = process.env): string {
  return env.EMBEDDING_MODEL || DEFAULT_EMBEDDING_MODEL;
}

/** The shared pipeline. A failed load is forgotten, so the next call tries again. */
export function loadEmbedder(): Promise<Extractor> {
  if (!extractor) {
    const loading = (async () => {
      const { pipeline, env } = await import('@huggingface/transformers');
      // Models are fetched, not shipped: where they are kept can be moved off
      // the package folder (e.g. onto a volume) without a code change.
      if (process.env.TRANSFORMERS_CACHE_DIR) env.cacheDir = process.env.TRANSFORMERS_CACHE_DIR;
      return (await pipeline('feature-extraction', embeddingModelName(), {
        dtype: EMBEDDING_DTYPE,
      })) as unknown as Extractor;
    })();
    extractor = loading;
    loading.catch(() => {
      if (extractor === loading) extractor = null;
    });
  }
  return extractor;
}

async function embed(text: string): Promise<number[]> {
  const run = await loadEmbedder();
  const output = await run(text, { pooling: 'mean', normalize: true });
  const vector = Array.from(output.data);
  if (vector.length !== EMBEDDING_DIMENSIONS) {
    throw new Error(
      `Embedding model ${embeddingModelName()} returned ${vector.length} dimensions; ` +
        `faq_embeddings stores ${EMBEDDING_DIMENSIONS}.`,
    );
  }
  return vector;
}

/**
 * Unit-length vectors, so cosine similarity is a plain dot product and
 * pgvector's `<=>` distance is `1 - similarity`.
 * [embedQuery] is for what a person asks; [embedPassage] for a stored answer.
 */
export const embedQuery = (text: string) => embed(embeddingProfile().queryPrefix + text);
export const embedPassage = (text: string) => embed(embeddingProfile().passagePrefix + text);

/** Starts loading the model in the background so the first question is not the one that waits. */
export function warmEmbedder(): void {
  loadEmbedder().then(
    () => console.log(`[AI] Embedding model ready (${embeddingModelName()})`),
    (err) => console.error('[AI] Embedding model failed to load:', err),
  );
}
