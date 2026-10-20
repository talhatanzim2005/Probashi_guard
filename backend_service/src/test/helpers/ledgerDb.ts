import { randomUUID } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';

/**
 * A real Postgres (PGlite: Postgres compiled to WebAssembly, running inside the
 * test process) with this repo's money migrations applied, so the SQL that
 * actually moves balances can be tested without touching the live Supabase
 * project. Nothing is mocked: the functions, constraints, grants and row-level
 * security under test are the ones in supabase/migrations.
 *
 * What Supabase provides and the migrations assume, and the shim below recreates:
 *   - the roles anon / authenticated / service_role
 *   - auth.users and auth.uid() (here read from the `request.jwt.claim.sub`
 *     setting, which is how PostgREST passes the caller's id)
 *   - default privileges that hand every new table and function to those roles,
 *     which is why the migrations REVOKE so much
 */

export const MIGRATIONS_DIR = path.resolve(__dirname, '..', '..', '..', '..', 'supabase', 'migrations');

/** In the order they were written; each one builds on the last. */
export const MONEY_MIGRATIONS = [
  '20261019140000_p2p_core.sql',
  '20261019150000_tighten_client_grants.sql',
  '20261019160000_wallet_deposit.sql',
  '20261019170000_verified_phone_gate.sql',
  '20261019120000_claim_anonymous_data.sql',
  '20261020100000_sub_wallets.sql',
  '20261020110000_shared_test_phones.sql',
];

export const AUTH_SHIM = `
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
create schema auth;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  phone text,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  is_anonymous boolean not null default false
);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema public, auth to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
`;

/**
 * saved_documents and beneficiaries were created by hand in the Supabase
 * dashboard and appear in no migration (finding SEC-11). claim_anonymous_data()
 * reads and writes them, so a test that exercises it has to create them.
 */
export const DASHBOARD_TABLES = `
create table public.saved_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  created_at timestamptz not null default now()
);
create table public.beneficiaries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  name text,
  phone_number text,
  created_at timestamptz not null default now()
);
`;

export type Role = 'anon' | 'authenticated' | 'service_role';

export function migrationSql(file: string): string {
  return readFileSync(path.join(MIGRATIONS_DIR, file), 'utf8');
}

/** Every migration in the repo, in order, except the one that needs pgvector. */
export function allMigrationFiles(): string[] {
  return readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql') && !f.includes('faq_embeddings'))
    .sort();
}

export async function emptyDatabase(): Promise<PGlite> {
  const pg = new PGlite({ extensions: { pgcrypto } });
  await pg.exec(AUTH_SHIM);
  return pg;
}

/** The SQLSTATE a statement fails with, or 'OK'. */
export async function sqlState(attempt: Promise<unknown>): Promise<string> {
  try {
    await attempt;
    return 'OK';
  } catch (err: any) {
    return err?.code ?? `NO-CODE: ${err?.message}`;
  }
}

export const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export class LedgerDb {
  private counter = 0;

  private constructor(readonly pg: PGlite) {}

  static async create(opts: { dashboardTables?: boolean } = {}): Promise<LedgerDb> {
    const pg = await emptyDatabase();
    if (opts.dashboardTables !== false) await pg.exec(DASHBOARD_TABLES);
    for (const file of MONEY_MIGRATIONS) await pg.exec(migrationSql(file));
    return new LedgerDb(pg);
  }

  /** Runs as the superuser: for setup and for reading the truth directly. */
  async query<T = any>(sql: string, params: unknown[] = []): Promise<T[]> {
    return (await this.pg.query<T>(sql, params)).rows;
  }

  /** Runs [fn] as a database role, with `auth.uid()` returning [userId]. */
  async as<T>(role: Role, userId: string | null, fn: () => Promise<T>): Promise<T> {
    await this.pg.query(`select set_config('request.jwt.claim.sub', $1, false)`, [userId ?? '']);
    await this.pg.exec(`set role ${role}`);
    try {
      return await fn();
    } finally {
      await this.pg.exec('reset role');
      await this.pg.query(`select set_config('request.jwt.claim.sub', '', false)`);
    }
  }

  call<T = any>(role: Role, userId: string | null, sql: string, params: unknown[] = []): Promise<T[]> {
    return this.as(role, userId, () => this.query<T>(sql, params));
  }

  /** The jsonb a function returned, as an object. */
  async rpc(role: Role, userId: string | null, sql: string, params: unknown[] = []): Promise<any> {
    return (await this.call(role, userId, `select (${sql}) as r`, params))[0].r;
  }

  // --- people -------------------------------------------------------------

  /** Inserts an auth.users row; the on_auth_user_created trigger opens the profile and wallets. */
  async addUser(opts: { name?: string; anonymous?: boolean } = {}): Promise<string> {
    const id = randomUUID();
    const n = ++this.counter;
    await this.query(
      `insert into auth.users (id, email, raw_user_meta_data, is_anonymous) values ($1, $2, $3::jsonb, $4)`,
      [id, opts.anonymous ? null : `user${n}@example.test`, JSON.stringify({ full_name: opts.name ?? `User ${n}` }), !!opts.anonymous],
    );
    return id;
  }

  /** A phone nobody else in this database has. */
  freshPhone(): string {
    return `+88019${String(++this.counter).padStart(8, '0')}`;
  }

  async bindPhone(userId: string, phone: string, shared = false, cap = 50) {
    return this.rpc('service_role', null, 'select public.bind_verified_phone($1::uuid, $2, $3::boolean, $4::integer)', [
      userId,
      phone,
      shared,
      cap,
    ]);
  }

  async deposit(userId: string, amount: number, card = 'card_wps') {
    return this.rpc('service_role', null, 'select public.deposit_to_wallet($1::uuid, $2::numeric, $3, $4, $5)', [
      userId,
      amount,
      `fund-${userId}-${card}-${++this.counter}`,
      'test funding',
      card,
    ]);
  }

  /** A verified account (own number unless [shared]) holding [funds] on the WPS card. */
  async verifiedUser(opts: { name?: string; funds?: number; shared?: boolean; phone?: string } = {}) {
    const id = await this.addUser({ name: opts.name });
    const phone = opts.phone ?? this.freshPhone();
    await this.bindPhone(id, phone, !!opts.shared);
    if (opts.funds) await this.deposit(id, opts.funds);
    return { id, phone };
  }

  // --- reading ------------------------------------------------------------

  async balance(userId: string, card = 'card_wps'): Promise<number> {
    const rows = await this.query(`select balance from public.wallets where user_id = $1 and card_id = $2`, [userId, card]);
    return Number(rows[0]?.balance);
  }

  async balances(userId: string): Promise<Record<string, number>> {
    const rows = await this.query(`select card_id, balance from public.wallets where user_id = $1`, [userId]);
    return Object.fromEntries(rows.map((r: any) => [r.card_id, Number(r.balance)]));
  }

  async ledger(userId: string, card?: string) {
    return this.query(
      `select * from public.transactions where user_id = $1 ${card ? 'and card_id = $2' : ''} order by created_at, direction`,
      card ? [userId, card] : [userId],
    );
  }

  async totalMoney(): Promise<number> {
    return Number((await this.query(`select coalesce(sum(balance), 0) as s from public.wallets`))[0].s);
  }

  /**
   * The invariants that must hold after ANY sequence of operations. Returns a
   * list of human-readable violations, empty when the ledger is sound.
   */
  async ledgerViolations(): Promise<string[]> {
    const problems: string[] = [];
    const add = (label: string, rows: unknown[]) => {
      if (rows.length) problems.push(`${label}: ${JSON.stringify(rows.slice(0, 3))}`);
    };

    add(
      'a wallet balance differs from the net of its ledger',
      await this.query(`
        select w.user_id, w.card_id, w.balance
        from public.wallets w
        left join public.transactions t on t.user_id = w.user_id and t.card_id = w.card_id
        group by w.user_id, w.card_id, w.balance
        having w.balance <> coalesce(sum(case when t.direction = 'credit' then t.amount else -t.amount end), 0)`),
    );
    add('a negative balance', await this.query(`select user_id, card_id, balance from public.wallets where balance < 0`));
    add(
      'a ledger row whose before/after does not match its amount',
      await this.query(`
        select id, direction, amount, balance_before, balance_after from public.transactions
        where balance_after <> balance_before + case when direction = 'credit' then amount else -amount end
           or balance_after < 0`),
    );
    add(
      'a transfer whose debit and credit differ',
      await this.query(`
        select reference,
               sum(case when direction = 'credit' then amount else 0 end) as credits,
               sum(case when direction = 'debit' then amount else 0 end) as debits
        from public.transactions
        group by reference
        having sum(case when direction = 'credit' then amount else 0 end)
            <> sum(case when direction = 'debit' then amount else 0 end)
           and bool_or(purpose = 'transfer')`),
    );
    add(
      'a reference that does not have exactly one debit and one credit leg',
      await this.query(`
        select reference, count(*) as legs from public.transactions
        where purpose in ('transfer', 'withdrawal') or reference in (select reference from public.transactions where purpose = 'withdrawal')
        group by reference having count(*) <> 2`),
    );
    return problems;
  }
}
