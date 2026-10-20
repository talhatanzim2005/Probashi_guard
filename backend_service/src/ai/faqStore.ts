import { SupabaseClient, createClient } from '@supabase/supabase-js';
import type { FaqChunk, FaqLanguage } from './faqParser.js';

/**
 * The FAQ knowledge base in Supabase (`faq_embeddings`, see
 * supabase/migrations/20261020120000_faq_embeddings.sql). Only this server
 * touches it, with the service-role key: the table has RLS on and no policies,
 * and `match_faqs` is granted to service_role alone, so the app can never read
 * or write it directly.
 */

let client: SupabaseClient | null = null;

export function knowledgeBaseConfigured(env: NodeJS.ProcessEnv = process.env): boolean {
  return Boolean(env.SUPABASE_URL && env.SUPABASE_SERVICE_ROLE_KEY);
}

export function getServiceClient(): SupabaseClient | null {
  if (client) return client;
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return null;
  client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  return client;
}

/** pgvector's text form, which PostgREST accepts for both inserts and function arguments. */
export const toVectorLiteral = (vector: readonly number[]): string => `[${vector.join(',')}]`;

export interface FaqMatch {
  id: number;
  chunk_key: string;
  language: FaqLanguage;
  section: string | null;
  content: string;
  /** 1 is identical; higher is closer. */
  similarity: number;
  /** The model that made the stored vector, so a model change cannot go unnoticed. */
  embedding_model: string;
}

export async function matchFaqs(
  embedding: readonly number[],
  options: { threshold: number; count: number },
): Promise<FaqMatch[]> {
  const sb = getServiceClient();
  if (!sb) throw new Error('Supabase is not configured (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY)');
  const { data, error } = await sb.rpc('match_faqs', {
    query_embedding: toVectorLiteral(embedding),
    match_threshold: options.threshold,
    match_count: options.count,
  });
  if (error) throw new Error(`match_faqs failed: ${error.message}`);
  return (data ?? []) as FaqMatch[];
}

export interface FaqRow {
  chunk: FaqChunk;
  embedding: number[];
}

/**
 * Makes the table hold exactly [rows] for the given model: each question is
 * written under its stable key (so re-running never duplicates it), and any
 * stored question that is no longer in the documents is removed.
 */
export async function replaceFaqs(rows: FaqRow[], model: string): Promise<{ written: number; removed: number }> {
  const sb = getServiceClient();
  if (!sb) throw new Error('Supabase is not configured (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY)');

  const payload = rows.map(({ chunk, embedding }) => ({
    chunk_key: chunk.key,
    language: chunk.language,
    section: chunk.section,
    content: chunk.content,
    embedding: toVectorLiteral(embedding),
    embedding_model: model,
  }));
  // Small batches keep each request well under the body limit (384 numbers a row).
  for (let i = 0; i < payload.length; i += 20) {
    const { error } = await sb.from('faq_embeddings').upsert(payload.slice(i, i + 20), { onConflict: 'chunk_key' });
    if (error) throw new Error(`Could not write FAQs: ${error.message}`);
  }

  const keep = new Set(payload.map((p) => p.chunk_key));
  const { data: stored, error: listError } = await sb.from('faq_embeddings').select('chunk_key');
  if (listError) throw new Error(`Could not list FAQs: ${listError.message}`);
  const stale = (stored ?? []).map((r) => r.chunk_key as string).filter((k) => !keep.has(k));
  if (stale.length > 0) {
    const { error } = await sb.from('faq_embeddings').delete().in('chunk_key', stale);
    if (error) throw new Error(`Could not remove old FAQs: ${error.message}`);
  }
  return { written: payload.length, removed: stale.length };
}
