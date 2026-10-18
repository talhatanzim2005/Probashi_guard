import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import ogs from 'open-graph-scraper';

dotenv.config();

/**
 * Fills the `notices` feed from the Open Graph tags the news sites already
 * serve to Facebook and X. No news API and no paid plan: one fetch per
 * article, cached in Supabase, and the app only ever reads the cache.
 *
 *   npm run seed:notices              scrape and write
 *   npm run seed:notices -- --dry-run  scrape and print, write nothing
 *
 * Writes use the service role key because the table's RLS policy grants
 * SELECT only; nothing in the app may write to the feed.
 */

const NOTICE_URLS = [
  'https://www.tbsnews.net/bangladesh/migration/hotline-launched-migrant-workers-assistance-490534',
  'https://www.tbsnews.net/bangladesh/migration/saudi-arabia-extends-expired-work-permit-renewal-deadline-until-end-2026',
  'https://www.tbsnews.net/bangladesh/migration/laos-suspends-new-work-permits-bangladeshis-until-end-2026-1544871',
  'https://en.prothomalo.com/bangladesh/pfydrq5l7w',
  'https://www.tbsnews.net/bangladesh/migration/govt-revokes-licences-49-recruiting-agencies-over-malaysia-labour-syndicate',
  'https://www.tbsnews.net/bangladesh/govt-continue-25-cash-incentive-remittances-1460256',
  'https://thefinancialexpress.com.bd/home/ugc-warns-against-fake-foreign-university-branches-in-bangladesh',
];

/** Some publishers serve a block page to a bare fetch; a browser UA gets the real article. */
const USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

/** Seconds, per article. open-graph-scraper takes seconds, not milliseconds. */
const SCRAPE_TIMEOUT = 20;

interface NoticeRow {
  title: string;
  description: string | null;
  image_url: string | null;
  source_url: string;
}

const isDryRun = process.argv.includes('--dry-run');

/** "www.tbsnews.net/..." -> "tbsnews.net", the last-resort headline. */
function hostOf(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch {
    return url;
  }
}

/** og:image is often a path, and the app needs something it can load directly. */
function absoluteUrl(candidate: string | undefined, pageUrl: string): string | null {
  if (!candidate) return null;
  try {
    return new URL(candidate, pageUrl).toString();
  } catch {
    return null;
  }
}

function clean(value: string | undefined): string | null {
  const trimmed = value?.replace(/\s+/g, ' ').trim();
  return trimmed ? trimmed : null;
}

/**
 * One article. Returns null when the page could not be read at all — a single
 * dead link must not stop the other six.
 */
async function scrapeNotice(url: string): Promise<NoticeRow | null> {
  try {
    const { error, result } = await ogs({
      url,
      timeout: SCRAPE_TIMEOUT,
      fetchOptions: { headers: { 'user-agent': USER_AGENT } },
    });

    if (error) {
      console.warn(`  ! skipped, could not read the page: ${hostOf(url)}`);
      return null;
    }

    // Twitter card tags are the usual fallback: publishers that set one
    // normally set both, and the few that skip og: still fill twitter:.
    const title = clean(result.ogTitle) ?? clean(result.twitterTitle) ?? hostOf(url);
    const description = clean(result.ogDescription) ?? clean(result.twitterDescription);
    const image = absoluteUrl(
      result.ogImage?.[0]?.url ?? result.twitterImage?.[0]?.url,
      url,
    );

    return { title, description, image_url: image, source_url: url };
  } catch (e) {
    console.warn(`  ! skipped, scrape threw: ${hostOf(url)} — ${(e as Error).message}`);
    return null;
  }
}

async function main(): Promise<void> {
  const supabaseUrl = process.env.SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!isDryRun && (!supabaseUrl || !serviceRoleKey)) {
    console.error(
      'Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in backend_service/.env.\n' +
        'Run with --dry-run to scrape without writing.',
    );
    process.exit(1);
  }

  console.log(
    `Scraping ${NOTICE_URLS.length} articles${isDryRun ? ' (dry run, nothing will be written)' : ''}...`,
  );

  const rows: NoticeRow[] = [];
  for (const url of NOTICE_URLS) {
    console.log(`- ${hostOf(url)}`);
    const notice = await scrapeNotice(url);
    if (!notice) continue;

    const missing = [
      notice.description ? null : 'description',
      notice.image_url ? null : 'image',
    ].filter(Boolean);
    console.log(
      `  ${notice.title}${missing.length ? `  [no ${missing.join(', no ')}]` : ''}`,
    );
    rows.push(notice);
  }

  if (rows.length === 0) {
    console.error('\nNothing could be scraped; leaving the notices table untouched.');
    process.exit(1);
  }

  if (isDryRun) {
    console.log(`\nDry run: ${rows.length}/${NOTICE_URLS.length} articles scraped, nothing written.`);
    console.log(JSON.stringify(rows, null, 2));
    return;
  }

  const supabase = createClient(supabaseUrl!, serviceRoleKey!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Upsert on source_url so running the seeder again refreshes the headlines
  // instead of stacking a second copy of every card into the feed.
  const { error } = await supabase
    .from('notices')
    .upsert(rows, { onConflict: 'source_url' });

  if (error) {
    console.error(`\nSupabase rejected the write: ${error.message}`);
    process.exit(1);
  }

  console.log(`\nDone: ${rows.length}/${NOTICE_URLS.length} notices written to Supabase.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
