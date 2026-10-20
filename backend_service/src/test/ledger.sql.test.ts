import test from 'node:test';
import assert from 'node:assert/strict';
import {
  LedgerDb,
  MONEY_MIGRATIONS,
  allMigrationFiles,
  emptyDatabase,
  migrationSql,
  sleep,
  sqlState,
} from './helpers/ledgerDb.js';

/**
 * The money-moving SQL, run for real.
 *
 * supabase/migrations is applied to an in-memory Postgres (PGlite) and the
 * functions are called exactly as the app and the backend call them: the app's
 * ones as the `authenticated` role with a user id, the backend's as
 * `service_role`. No mocks and no network; the live project is never touched.
 *
 * What this cannot cover is concurrency: PGlite has one connection, so two
 * transfers cannot truly race. The row locks (FOR UPDATE, taken in a fixed
 * order) are read in review, and `npm run pentest:*` probes them on a live copy.
 *
 * IDs: DB-A accounts, DB-G grants and row-level security, DB-I card-to-card,
 * DB-P person-to-person, DB-R funding and remittance booking, DB-V phone proof
 * and the shared test-number pool, DB-L recipient lookup, DB-C anonymous
 * carry-over, DB-X whole-ledger properties, DB-M the migrations themselves.
 */

let db: LedgerDb;
test.before(async () => {
  db = await LedgerDb.create();
});

const send = (from: string, phone: string, amount: number | string | null, key: string | null = null) =>
  db.rpc('authenticated', from, 'select public.p2p_transfer($1, $2::numeric, $3, $4::text)', [phone, amount, 'rent', key]);
const swap = (user: string, from: string | null, to: string | null, amount: number | string | null, key: string | null = null) =>
  db.rpc('authenticated', user, 'select public.internal_transfer($1, $2, $3::numeric, $4::text)', [from, to, amount, key]);
const settle = (user: string | null, card: string | null, session: string | null, amount: number | null, name = 'Rahim', phone: string | null = '+8801900000114') =>
  db.rpc('service_role', null, 'select public.settle_remittance($1::uuid, $2, $3, $4::numeric, $5, $6)', [user, card, session, amount, name, phone]);
const lookup = (user: string, phone: string) =>
  db.rpc('authenticated', user, 'select public.lookup_recipient($1)', [phone]);

async function failure(attempt: Promise<unknown>): Promise<{ code: string; message: string }> {
  try {
    await attempt;
  } catch (err: any) {
    return { code: err.code, message: String(err.message) };
  }
  assert.fail('expected the statement to fail, but it succeeded');
}

// ===========================================================================
// DB-A  Accounts
// ===========================================================================

test('DB-A01 a new account gets a profile and exactly three EMPTY card wallets, and no history', async () => {
  const id = await db.addUser({ name: 'Nasima Begum' });
  assert.deepEqual(await db.balances(id), { card_wps: 0, card_probashi: 0, card_visa: 0 });
  const profile = (await db.query(`select full_name, phone, phone_verified_at from public.profiles where user_id = $1`, [id]))[0];
  assert.equal(profile.full_name, 'Nasima Begum');
  assert.equal(profile.phone, null);
  assert.equal(profile.phone_verified_at, null);
  assert.equal((await db.ledger(id)).length, 0, 'no seed data: no transactions');
});

test('DB-A02 verifying a number opens any wallet an older account is missing', async () => {
  const id = await db.addUser();
  await db.query(`delete from public.wallets where user_id = $1 and card_id <> 'card_wps'`, [id]);
  await db.bindPhone(id, db.freshPhone());
  assert.equal(Object.keys(await db.balances(id)).length, 3);
});

test('DB-A03 ensure_my_wallet repairs a missing wallet and reports the WPS balance', async () => {
  const id = await db.addUser();
  await db.deposit(id, 125.5);
  await db.query(`delete from public.wallets where user_id = $1 and card_id = 'card_visa'`, [id]);
  const balance = (await db.call('authenticated', id, 'select public.ensure_my_wallet() as b'))[0].b;
  assert.equal(Number(balance), 125.5);
  assert.equal(Object.keys(await db.balances(id)).length, 3);
  assert.equal(await sqlState(db.call('authenticated', null, 'select public.ensure_my_wallet()')), '42501', 'needs a session');
});

// ===========================================================================
// DB-G  Grants and row-level security
// ===========================================================================

test('DB-G01 a signed-in client cannot write a balance or a ledger row directly', async () => {
  const { id } = await db.verifiedUser({ funds: 100 });
  const attempts = [
    `update public.wallets set balance = 1000000 where user_id = '${id}'`,
    `insert into public.wallets (user_id, balance, card_id) values ('${id}', 5, 'card_wps')`,
    `delete from public.wallets where user_id = '${id}'`,
    `insert into public.transactions (reference, user_id, direction, amount, balance_before, balance_after, card_id) values (gen_random_uuid(), '${id}', 'credit', 1, 0, 1, 'card_wps')`,
    `update public.transactions set amount = 1 where user_id = '${id}'`,
    `delete from public.transactions where user_id = '${id}'`,
    `truncate public.transactions`,
  ];
  for (const sql of attempts) {
    assert.equal(await sqlState(db.call('authenticated', id, sql)), '42501', sql);
  }
  assert.equal(await db.balance(id), 100, 'and the balance did not move');
});

test('DB-G02 the anonymous role can read nothing and write nothing', async () => {
  const { id } = await db.verifiedUser({ funds: 10 });
  for (const table of ['wallets', 'transactions', 'profiles', 'payment_methods', 'rpc_rate_limits', 'anonymous_claims']) {
    assert.equal(await sqlState(db.call('anon', null, `select * from public.${table}`)), '42501', `read ${table}`);
  }
  assert.equal(await sqlState(db.call('anon', null, `update public.wallets set balance = 1`)), '42501');
  assert.equal(await sqlState(db.call('anon', null, `select public.p2p_transfer('+8801', 1, '', null)`)), '42501');
  assert.equal(await sqlState(db.call('anon', null, `select public.internal_transfer('card_wps', 'card_visa', 1, null)`)), '42501');
  assert.equal(await sqlState(db.call('anon', null, `select public.lookup_recipient('+8801')`)), '42501');
  void id;
});

test('DB-G03 a client can edit its own name and avatar, and nothing about its phone', async () => {
  const { id } = await db.verifiedUser({ name: 'Old Name' });
  await db.call('authenticated', id, `update public.profiles set full_name = 'New Name', avatar_url = 'x' where user_id = '${id}'`);
  assert.equal((await db.query(`select full_name from public.profiles where user_id = $1`, [id]))[0].full_name, 'New Name');
  for (const column of ['phone', 'phone_verified_at', 'phone_is_shared', 'user_id']) {
    const value = column === 'phone_verified_at' ? 'now()' : column === 'phone_is_shared' ? 'true' : column === 'user_id' ? 'gen_random_uuid()' : `'+8801911111111'`;
    assert.equal(
      await sqlState(db.call('authenticated', id, `update public.profiles set ${column} = ${value} where user_id = '${id}'`)),
      '42501',
      column,
    );
  }
});

test('DB-G04 row-level security: each account sees only its own rows', async () => {
  const a = await db.verifiedUser({ funds: 50 });
  const b = await db.verifiedUser({ funds: 70 });
  assert.deepEqual(
    (await db.call('authenticated', a.id, 'select card_id, balance from public.wallets order by card_id')).map((r) => r.card_id),
    ['card_probashi', 'card_visa', 'card_wps'],
  );
  assert.equal((await db.call('authenticated', a.id, `select * from public.wallets where user_id = '${b.id}'`)).length, 0);
  assert.equal((await db.call('authenticated', a.id, `select * from public.transactions where user_id = '${b.id}'`)).length, 0);
  assert.equal((await db.call('authenticated', a.id, `select * from public.profiles where user_id = '${b.id}'`)).length, 0);
  // An UPDATE aimed at someone else's row matches nothing rather than succeeding.
  await db.call('authenticated', a.id, `update public.profiles set full_name = 'hacked' where user_id = '${b.id}'`);
  assert.notEqual((await db.query(`select full_name from public.profiles where user_id = $1`, [b.id]))[0].full_name, 'hacked');
});

test('DB-G05 who may run which function', async () => {
  const rows = await db.query(`
    select p.proname,
           has_function_privilege('anon', p.oid, 'EXECUTE') as anon,
           has_function_privilege('authenticated', p.oid, 'EXECUTE') as authed,
           has_function_privilege('service_role', p.oid, 'EXECUTE') as service
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any($1)`, [[
    'p2p_transfer', 'internal_transfer', 'lookup_recipient', 'ensure_my_wallet', 'my_phone_status',
    'issue_anonymous_claim', 'claim_anonymous_data',
    'deposit_to_wallet', 'settle_remittance', 'bind_verified_phone', 'set_my_phone', 'enforce_rate_limit',
  ]]);
  const by = Object.fromEntries(rows.map((r: any) => [r.proname, r]));
  for (const name of ['p2p_transfer', 'internal_transfer', 'lookup_recipient', 'ensure_my_wallet', 'my_phone_status', 'issue_anonymous_claim', 'claim_anonymous_data']) {
    assert.equal(by[name].authed, true, `${name} is for signed-in clients`);
    assert.equal(by[name].anon, false, `${name} is not for the anon role`);
  }
  // These raise or relabel balances and phones: the backend (service_role) only.
  for (const name of ['deposit_to_wallet', 'settle_remittance', 'bind_verified_phone', 'set_my_phone', 'enforce_rate_limit']) {
    assert.equal(by[name].authed, false, `${name} must NOT be callable by a signed-in client`);
    assert.equal(by[name].anon, false, `${name} must NOT be callable by anon`);
    assert.equal(by[name].service, true, `${name} is the backend's`);
  }
});

test('DB-G06 a signed-in client calling the privileged functions is refused, and nothing changes', async () => {
  const { id, phone } = await db.verifiedUser();
  const before = await db.balance(id);
  for (const sql of [
    `select public.deposit_to_wallet('${id}', 1000000, 'k1', '', 'card_wps')`,
    `select public.settle_remittance('${id}', 'card_wps', 'cs_x', 100, 'x', null)`,
    `select public.bind_verified_phone('${id}', '+8801555555555', false, 50)`,
    `select public.set_my_phone('+8801555555555')`,
  ]) {
    assert.equal(await sqlState(db.call('authenticated', id, sql)), '42501', sql);
  }
  assert.equal(await db.balance(id), before);
  assert.equal((await db.query(`select phone from public.profiles where user_id = $1`, [id]))[0].phone, phone);
});

test('DB-G07 payment_methods can hold a brand and last four digits, never a card number', async () => {
  const columns = (await db.query(
    `select column_name from information_schema.columns where table_schema = 'public' and table_name = 'payment_methods'`,
  )).map((r: any) => r.column_name as string);
  for (const forbidden of ['pan', 'card_number', 'number', 'cvv', 'cvc', 'pin', 'account_number', 'iban', 'secret']) {
    assert.ok(!columns.includes(forbidden), `payment_methods must not have a "${forbidden}" column`);
  }
  const { id } = await db.verifiedUser();
  const insert = (last4: string) =>
    `insert into public.payment_methods (user_id, kind, last4, brand) values ('${id}', 'card', '${last4}', 'visa')`;
  assert.equal(await sqlState(db.call('authenticated', id, insert('4242'))), 'OK');
  for (const bad of ['4242424242424242', '424', '42a2', '']) {
    assert.equal(await sqlState(db.call('authenticated', id, insert(bad))), '23514', `last4 = "${bad}"`);
  }
  const other = await db.verifiedUser();
  assert.equal(
    await sqlState(db.call('authenticated', id, `insert into public.payment_methods (user_id, kind, last4) values ('${other.id}', 'card', '1111')`)),
    '42501',
    'a card cannot be added to someone else\'s account',
  );
});

test('DB-G08 the table constraints hold even for the superuser: no negative balance, no zero amount', async () => {
  const { id } = await db.verifiedUser({ funds: 10 });
  assert.equal(await sqlState(db.query(`update public.wallets set balance = -0.01 where user_id = $1 and card_id = 'card_wps'`, [id])), '23514');
  assert.equal(await sqlState(db.query(`update public.wallets set card_id = 'card_gold' where user_id = $1 and card_id = 'card_wps'`, [id])), '23514');
  assert.equal(
    await sqlState(db.query(`insert into public.transactions (reference, user_id, direction, amount, balance_before, balance_after) values (gen_random_uuid(), $1, 'credit', 0, 0, 0)`, [id])),
    '23514',
  );
  assert.equal(
    await sqlState(db.query(`insert into public.transactions (reference, user_id, direction, amount, balance_before, balance_after) values (gen_random_uuid(), $1, 'sideways', 5, 0, 5)`, [id])),
    '23514',
  );
});

// ===========================================================================
// DB-I  Card-to-card (internal_transfer)
// ===========================================================================

test('DB-I01 a swap moves money between my own cards and writes two linked ledger legs', async () => {
  const { id } = await db.verifiedUser({ funds: 1000 });
  const result = await swap(id, 'card_wps', 'card_visa', 300.25);
  assert.equal(result.repeated, false);
  assert.equal(Number(result.amount), 300.25);
  assert.equal(Number(result.from_balance), 699.75);
  assert.equal(Number(result.to_balance), 300.25);
  assert.deepEqual(await db.balances(id), { card_wps: 699.75, card_probashi: 0, card_visa: 300.25 });

  const legs = (await db.ledger(id)).filter((r: any) => r.reference === result.reference);
  assert.equal(legs.length, 2);
  const debit = legs.find((r: any) => r.direction === 'debit');
  const credit = legs.find((r: any) => r.direction === 'credit');
  assert.equal(debit.card_id, 'card_wps');
  assert.equal(credit.card_id, 'card_visa');
  assert.equal(Number(debit.balance_before), 1000);
  assert.equal(Number(debit.balance_after), 699.75);
  assert.equal(Number(credit.balance_before), 0);
  assert.equal(Number(credit.balance_after), 300.25);
  assert.equal(debit.purpose, 'transfer');
  assert.equal(debit.counterparty_id, null, 'no counterparty: it is my own money');
  assert.deepEqual(await db.ledgerViolations(), []);
});

test('DB-I02 a swap never creates or destroys money', async () => {
  const { id } = await db.verifiedUser();
  await db.deposit(id, 500, 'card_wps');
  await db.deposit(id, 200, 'card_probashi');
  const total = async () => Object.values(await db.balances(id)).reduce((a, b) => a + b, 0);
  const before = await total();
  await swap(id, 'card_wps', 'card_probashi', 123.45);
  await swap(id, 'card_probashi', 'card_visa', 300);
  await swap(id, 'card_visa', 'card_wps', 0.01);
  assert.equal(Number((await total()).toFixed(2)), before);
});

test('DB-I03 refusals: not enough balance, same card, unknown card, bad amount', async () => {
  const { id } = await db.verifiedUser({ funds: 50 });
  const cases: Array<[string, Promise<unknown>, RegExp]> = [
    ['overdraw', swap(id, 'card_wps', 'card_visa', 50.01), /does not have enough balance/],
    ['empty source card', swap(id, 'card_visa', 'card_wps', 1), /does not have enough balance/],
    ['same card', swap(id, 'card_wps', 'card_wps', 1), /two different cards/],
    ['unknown source', swap(id, 'card_gold', 'card_wps', 1), /Unknown card/],
    ['unknown destination', swap(id, 'card_wps', 'card_gold', 1), /Unknown card/],
    ['null card', swap(id, null, 'card_wps', 1), /Unknown card/],
    ['zero', swap(id, 'card_wps', 'card_visa', 0), /greater than zero/],
    ['negative', swap(id, 'card_wps', 'card_visa', -5), /greater than zero/],
    ['null amount', swap(id, 'card_wps', 'card_visa', null), /greater than zero/],
    ['rounds to zero', swap(id, 'card_wps', 'card_visa', 0.004), /greater than zero/],
  ];
  for (const [label, attempt, message] of cases) {
    const failed = await failure(attempt);
    assert.equal(failed.code, '22023', label);
    assert.match(failed.message, message, label);
  }
  assert.deepEqual(await db.balances(id), { card_wps: 50, card_probashi: 0, card_visa: 0 });
  assert.equal((await db.ledger(id)).length, 1, 'only the original funding row exists');
});

test('DB-I04 the whole balance can be moved, to the paisa, and amounts are rounded to 2 places', async () => {
  const { id } = await db.verifiedUser({ funds: 10.01 });
  await swap(id, 'card_wps', 'card_visa', 10.005); // rounds to 10.01
  assert.deepEqual(await db.balances(id), { card_wps: 0, card_probashi: 0, card_visa: 10.01 });
});

test('DB-I05 a retried request with the same key reports the first result and moves nothing more', async () => {
  const { id } = await db.verifiedUser({ funds: 100 });
  const first = await swap(id, 'card_wps', 'card_visa', 40, 'swap-key-1');
  const retry = await swap(id, 'card_wps', 'card_visa', 40, 'swap-key-1');
  assert.equal(first.repeated, false);
  assert.equal(retry.repeated, true);
  assert.equal(retry.reference, first.reference);
  assert.deepEqual(await db.balances(id), { card_wps: 60, card_probashi: 0, card_visa: 40 });
  assert.equal((await db.ledger(id)).filter((r: any) => r.purpose === 'transfer').length, 2);
  // A different key is a different request.
  await swap(id, 'card_wps', 'card_visa', 10, 'swap-key-2');
  assert.equal(await db.balance(id, 'card_visa'), 50);
});

test('DB-I06 signed-out and anonymous callers are refused; a number need not be verified', async () => {
  const guest = await db.addUser({ anonymous: true });
  await db.deposit(guest, 100);
  assert.equal(await sqlState(swap(guest, 'card_wps', 'card_visa', 1)), '42501', 'anonymous');
  assert.equal(await sqlState(db.call('authenticated', null, `select public.internal_transfer('card_wps','card_visa',1,null)`)), '42501', 'no session');

  const unverified = await db.addUser();
  await db.deposit(unverified, 100);
  assert.equal(await sqlState(swap(unverified, 'card_wps', 'card_visa', 1)), 'OK', 'it is the owner\'s own money');
});

test('DB-I07 the function takes no user argument, so it cannot touch anyone else\'s wallets', async () => {
  const names = (await db.query(
    `select proargnames from pg_proc where proname = 'internal_transfer' and pronamespace = 'public'::regnamespace`,
  ))[0].proargnames as string[];
  assert.deepEqual(names, ['p_from_card', 'p_to_card', 'p_amount', 'p_idempotency_key']);
  const a = await db.verifiedUser({ funds: 100 });
  const b = await db.verifiedUser({ funds: 100 });
  await swap(a.id, 'card_wps', 'card_visa', 100);
  assert.deepEqual(await db.balances(b.id), { card_wps: 100, card_probashi: 0, card_visa: 0 });
});

// ===========================================================================
// DB-P  Person-to-person (p2p_transfer)
// ===========================================================================

test('DB-P01 a transfer debits the sender, credits the recipient, and writes two linked legs', async () => {
  const alice = await db.verifiedUser({ name: 'Alice', funds: 1000 });
  const bob = await db.verifiedUser({ name: 'Bob' });
  const r = await send(alice.id, bob.phone, 250.5);
  assert.equal(r.repeated, false);
  assert.equal(Number(r.amount), 250.5);
  assert.equal(Number(r.balance), 749.5);
  assert.equal(r.recipient_name, 'Bob');
  assert.equal(await db.balance(alice.id), 749.5);
  assert.equal(await db.balance(bob.id), 250.5);

  const debit = (await db.ledger(alice.id)).find((x: any) => x.reference === r.reference);
  const credit = (await db.ledger(bob.id)).find((x: any) => x.reference === r.reference);
  assert.equal(debit.direction, 'debit');
  assert.equal(debit.counterparty_id, bob.id);
  assert.equal(debit.counterparty_phone, bob.phone);
  assert.equal(credit.direction, 'credit');
  assert.equal(credit.counterparty_id, alice.id);
  assert.equal(credit.counterparty_name, 'Alice');
  assert.equal(credit.counterparty_phone, null, 'the recipient is not shown the sender\'s number');
  assert.equal(Number(credit.balance_before), 0);
  assert.equal(Number(credit.balance_after), 250.5);
  assert.equal(debit.card_id, 'card_wps');
  assert.equal(credit.card_id, 'card_wps');
  assert.deepEqual(await db.ledgerViolations(), []);
});

test('DB-P02 a transfer always spends the WPS card: money on the other cards is not reachable', async () => {
  const alice = await db.verifiedUser();
  await db.deposit(alice.id, 900, 'card_visa');
  const bob = await db.verifiedUser();
  const failed = await failure(send(alice.id, bob.phone, 10));
  assert.equal(failed.code, '22023');
  assert.match(failed.message, /balance is not enough/);
});

test('DB-P03 the sender must have proven their own number', async () => {
  const unverified = await db.addUser();
  await db.deposit(unverified, 100);
  const bob = await db.verifiedUser();
  const failed = await failure(send(unverified, bob.phone, 5));
  assert.equal(failed.code, '42501');
  assert.match(failed.message, /Verify your phone number/);
  assert.equal(await db.balance(bob.id), 0);
});

test('DB-P04 only a proven, exclusive number can be paid', async () => {
  const alice = await db.verifiedUser({ funds: 500 });

  // Unknown number.
  assert.equal((await failure(send(alice.id, '+8801000000000', 5))).code, 'P0002');

  // A number someone merely CLAIMED (set_my_phone is the backend's, never proven).
  const claimer = await db.addUser();
  const claimed = db.freshPhone();
  await db.call('service_role', claimer, 'select public.set_my_phone($1)', [claimed]);
  const claimFailed = await failure(send(alice.id, claimed, 5));
  assert.equal(claimFailed.code, 'P0002', 'an unproven claim cannot receive money');
  assert.match(claimFailed.message, /No Probashi Guard account uses that number/);

  // A Firebase test number is shared by many accounts, so it names nobody.
  const tester = await db.verifiedUser({ shared: true, phone: '+8801700000001' });
  const sharedFailed = await failure(send(alice.id, '+8801700000001', 5));
  assert.equal(sharedFailed.code, 'P0002', 'a shared test number can never receive a transfer');
  assert.equal(await db.balance(tester.id), 0);
  assert.equal(await db.balance(alice.id), 500, 'and nothing left the sender');
});

test('DB-P05 an account verified with a shared TEST number can still SEND (it just cannot receive)', async () => {
  // This is how the seeded sender account works: +8801700000000, funded.
  const sender = await db.verifiedUser({ shared: true, phone: '+8801700000000', funds: 800 });
  const receiver = await db.verifiedUser();
  await send(sender.id, receiver.phone, 300);
  assert.equal(await db.balance(sender.id), 500);
  assert.equal(await db.balance(receiver.id), 300);
  assert.equal((await failure(send(receiver.id, '+8801700000000', 10))).code, 'P0002', 'and the way back is closed');
});

test('DB-P06 you cannot pay yourself', async () => {
  const alice = await db.verifiedUser({ funds: 100 });
  const failed = await failure(send(alice.id, alice.phone, 10));
  assert.equal(failed.code, '22023');
  assert.match(failed.message, /yourself/);
  assert.equal(await db.balance(alice.id), 100);
});

test('DB-P07 bad amounts are refused and amounts are rounded to the paisa', async () => {
  const alice = await db.verifiedUser({ funds: 100 });
  const bob = await db.verifiedUser();
  for (const amount of [0, -1, '-0.001', 0.004, null]) {
    assert.equal((await failure(send(alice.id, bob.phone, amount))).code, '22023', String(amount));
  }
  await send(alice.id, bob.phone, 10.005);
  assert.equal(await db.balance(bob.id), 10.01, 'both legs use the rounded figure');
  assert.equal(await db.balance(alice.id), 89.99);
});

test('DB-P08 the balance is a hard ceiling; an exact-balance send leaves zero', async () => {
  const alice = await db.verifiedUser({ funds: 75.5 });
  const bob = await db.verifiedUser();
  assert.equal((await failure(send(alice.id, bob.phone, 75.51))).code, '22023');
  await send(alice.id, bob.phone, 75.5);
  assert.equal(await db.balance(alice.id), 0);
  assert.equal((await failure(send(alice.id, bob.phone, 0.01))).code, '22023');
  assert.deepEqual(await db.ledgerViolations(), []);
});

test('DB-P09 a retried transfer with the same key is paid once', async () => {
  const alice = await db.verifiedUser({ funds: 100 });
  const bob = await db.verifiedUser();
  const first = await send(alice.id, bob.phone, 30, 'pay-1');
  const retry = await send(alice.id, bob.phone, 30, 'pay-1');
  assert.equal(retry.repeated, true);
  assert.equal(retry.reference, first.reference);
  assert.equal(await db.balance(bob.id), 30);
  assert.equal(await db.balance(alice.id), 70);
  // The same key from another sender is unrelated.
  const carol = await db.verifiedUser({ funds: 100 });
  assert.equal((await send(carol.id, bob.phone, 5, 'pay-1')).repeated, false);
});

test('DB-P10 the number is matched however it is typed', async () => {
  const alice = await db.verifiedUser({ funds: 100 });
  const bob = await db.verifiedUser({ phone: '+8801900000044' });
  for (const typed of ['+8801900000044', '+880 1900-000044', '+880-1900 000 044', '(+880) 1900 000044']) {
    assert.equal((await send(alice.id, typed, 1)).repeated, false, typed);
  }
  assert.equal(await db.balance(bob.id), 4);
  // Without the + it is a different string, and nobody has it.
  assert.equal((await failure(send(alice.id, '8801900000044', 1))).code, 'P0002');
});

test('DB-P11 signed-out and anonymous callers cannot transfer', async () => {
  const bob = await db.verifiedUser();
  const guest = await db.addUser({ anonymous: true });
  await db.deposit(guest, 100);
  await db.query(`update public.profiles set phone = '+8801777777777', phone_verified_at = now() where user_id = $1`, [guest]);
  assert.equal(await sqlState(send(guest, bob.phone, 5)), '42501', 'anonymous, even with a verified profile');
  assert.equal(await sqlState(db.call('authenticated', null, `select public.p2p_transfer('${bob.phone}', 5, '', null)`)), '42501');
});

// ===========================================================================
// DB-R  Funding and booking a paid remittance (backend only)
// ===========================================================================

test('DB-R01 settle_remittance books money in and out, so the card balance ends where it started', async () => {
  const { id } = await db.verifiedUser({ funds: 1000 });
  const result = await settle(id, 'card_wps', 'cs_test_r01', 3185.5, 'Rahim Uddin', '+8801900000114');
  assert.equal(result.repeated, false);
  assert.equal(Number(result.balance), 1000);
  assert.equal(await db.balance(id), 1000, 'the wallet balance is unchanged (finding SEC-01: nothing is deducted for the send)');

  const legs = (await db.ledger(id)).filter((r: any) => r.reference === result.reference);
  assert.equal(legs.length, 2);
  const credit = legs.find((r: any) => r.direction === 'credit');
  const debit = legs.find((r: any) => r.direction === 'withdrawal' || r.direction === 'debit');
  assert.equal(credit.purpose, 'deposit');
  assert.equal(credit.idempotency_key, 'cs_test_r01:credit');
  assert.equal(debit.purpose, 'withdrawal');
  assert.equal(debit.idempotency_key, 'cs_test_r01:debit');
  assert.equal(debit.counterparty_name, 'Rahim Uddin');
  assert.equal(debit.counterparty_phone, '+8801900000114');
  assert.equal(Number(credit.balance_after), 4185.5);
  assert.equal(Number(debit.balance_after), 1000);
  assert.deepEqual(await db.ledgerViolations(), []);
});

test('DB-R02 Stripe retrying the webhook books the session once', async () => {
  const { id } = await db.verifiedUser({ funds: 10 });
  const first = await settle(id, 'card_visa', 'cs_test_r02', 100);
  const second = await settle(id, 'card_visa', 'cs_test_r02', 100);
  const third = await settle(id, 'card_visa', 'cs_test_r02', 100);
  assert.equal(first.repeated, false);
  assert.equal(second.repeated, true);
  assert.equal(third.repeated, true);
  assert.equal(second.reference, first.reference);
  assert.equal((await db.ledger(id, 'card_visa')).length, 2, 'two legs, not six');
  // A different session id is a different payment.
  assert.equal((await settle(id, 'card_visa', 'cs_test_r02b', 100)).repeated, false);
});

test('DB-R03 settle_remittance refuses incomplete or impossible bookings', async () => {
  const { id } = await db.verifiedUser();
  const cases: Array<[string, Promise<unknown>]> = [
    ['no account', settle(null, 'card_wps', 'cs_a', 10)],
    ['no session id', settle(id, 'card_wps', null, 10)],
    ['blank session id', settle(id, 'card_wps', '   ', 10)],
    ['unknown card', settle(id, 'card_gold', 'cs_b', 10)],
    ['no card', settle(id, null, 'cs_c', 10)],
    ['zero', settle(id, 'card_wps', 'cs_d', 0)],
    ['negative', settle(id, 'card_wps', 'cs_e', -10)],
    ['null amount', settle(id, 'card_wps', 'cs_f', null)],
    ['rounds to zero', settle(id, 'card_wps', 'cs_g', 0.001)],
  ];
  for (const [label, attempt] of cases) assert.equal((await failure(attempt)).code, '22023', label);
  assert.equal((await db.ledger(id)).length, 0);
});

test('DB-R04 deposit_to_wallet is the only way a balance goes up, and it is exact and idempotent', async () => {
  const { id } = await db.verifiedUser();
  const dep = await db.rpc('service_role', null, `select public.deposit_to_wallet($1::uuid, 120.456::numeric, 'dep-1', 'top up', 'card_probashi')`, [id]);
  assert.equal(Number(dep.amount), 120.46, 'rounded to paisa');
  assert.equal(await db.balance(id, 'card_probashi'), 120.46);
  const again = await db.rpc('service_role', null, `select public.deposit_to_wallet($1::uuid, 999::numeric, 'dep-1', 'top up', 'card_probashi')`, [id]);
  assert.equal(again.repeated, true);
  assert.equal(Number(again.amount), 120.46, 'a replay reports the first amount, not the new one');
  assert.equal(await db.balance(id, 'card_probashi'), 120.46);
  const credit = (await db.ledger(id, 'card_probashi'))[0];
  assert.equal(credit.purpose, 'deposit');
  assert.equal(credit.direction, 'credit');
  assert.equal(credit.counterparty_id, null);
});

test('DB-R05 deposit_to_wallet refuses bad input', async () => {
  const { id } = await db.verifiedUser();
  const dep = (user: string | null, amount: number | null, key: string | null, card = 'card_wps') =>
    db.rpc('service_role', null, 'select public.deposit_to_wallet($1::uuid, $2::numeric, $3, $4, $5)', [user, amount, key, '', card]);
  assert.equal((await failure(dep(null, 10, 'k'))).code, '22023');
  assert.equal((await failure(dep(id, 10, null))).code, '22023');
  assert.equal((await failure(dep(id, 10, '  '))).code, '22023');
  assert.equal((await failure(dep(id, 0, 'k0'))).code, '22023');
  assert.equal((await failure(dep(id, -5, 'k1'))).code, '22023');
  assert.equal((await failure(dep(id, null, 'k2'))).code, '22023');
  assert.equal((await failure(dep(id, 10, 'k3', 'card_gold'))).code, '22023');
  assert.equal(await db.balance(id), 0);
});

test('DB-R06 a booking for an account that does not exist is rejected by the database, not silently created', async () => {
  const ghost = '99999999-9999-4999-8999-999999999999';
  assert.equal(await sqlState(settle(ghost, 'card_wps', 'cs_ghost', 10)), '23503');
});

test('DB-R07 todo: funding and booking still require a verified phone, as the migration comment promises', { todo: 'SEC-28: sub_wallets.sql redefined deposit_to_wallet / settle_remittance and dropped the P0003 verified-phone gate; the webhook still has a handler for it' }, async () => {
  const unverified = await db.addUser();
  const dep = await failure(
    db.rpc('service_role', null, `select public.deposit_to_wallet($1::uuid, 10::numeric, 'dep-unverified', '', 'card_wps')`, [unverified]),
  );
  assert.equal(dep.code, 'P0003');
  assert.equal((await failure(settle(unverified, 'card_wps', 'cs_unverified', 10))).code, 'P0003');
});

// ===========================================================================
// DB-V  Phone proof and the shared test-number pool
// ===========================================================================

test('DB-V01 a real number belongs to one account; proving it again on the same account is fine', async () => {
  const phone = db.freshPhone();
  const a = await db.addUser();
  const b = await db.addUser();
  const bound = await db.bindPhone(a, phone);
  assert.deepEqual(bound, { phone, verified: true, shared: false });
  const row = (await db.query(`select phone, phone_verified_at, phone_is_shared from public.profiles where user_id = $1`, [a]))[0];
  assert.equal(row.phone, phone);
  assert.ok(row.phone_verified_at);
  assert.equal(row.phone_is_shared, false);

  const taken = await failure(db.bindPhone(b, phone));
  assert.equal(taken.code, '23505');
  assert.match(taken.message, /already verified/);

  assert.equal((await db.bindPhone(a, phone)).verified, true, 're-proving on the same account is allowed');
  assert.equal((await db.query(`select count(*)::int as n from public.profiles where phone = $1`, [phone]))[0].n, 1);
});

test('DB-V02 proof beats a claim: someone sitting on a number unproven is released', async () => {
  const phone = db.freshPhone();
  const squatter = await db.addUser();
  const owner = await db.addUser();
  await db.call('service_role', squatter, 'select public.set_my_phone($1)', [phone]);
  assert.equal((await db.query(`select phone from public.profiles where user_id = $1`, [squatter]))[0].phone, phone);
  await db.bindPhone(owner, phone);
  assert.equal((await db.query(`select phone from public.profiles where user_id = $1`, [squatter]))[0].phone, null);
  assert.equal((await db.query(`select phone from public.profiles where user_id = $1`, [owner]))[0].phone, phone);
});

test('DB-V03 a shared test number is held by many accounts; past the cap the OLDEST is released (FIFO)', async () => {
  const phone = '+8801700000002';
  const users: string[] = [];
  for (let i = 0; i < 3; i++) {
    const id = await db.addUser();
    await db.bindPhone(id, phone, true, 3);
    users.push(id);
    await sleep(5);
  }
  const holders = async () =>
    (await db.query(`select count(*)::int as n from public.profiles where phone = $1 and phone_verified_at is not null`, [phone]))[0].n;
  assert.equal(await holders(), 3);

  const fourth = await db.addUser();
  await db.bindPhone(fourth, phone, true, 3);
  assert.equal(await holders(), 3, 'the pool never exceeds its cap');
  const released = (await db.query(`select phone, phone_verified_at, phone_is_shared from public.profiles where user_id = $1`, [users[0]]))[0];
  assert.deepEqual(released, { phone: null, phone_verified_at: null, phone_is_shared: false }, 'the first holder lost the number');
  for (const id of [users[1], users[2], fourth]) {
    assert.equal((await db.query(`select phone from public.profiles where user_id = $1`, [id]))[0].phone, phone);
  }
});

test('DB-V04 an evicted holder can no longer send money until it verifies again', async () => {
  const phone = '+8801700000004';
  const first = await db.addUser();
  await db.bindPhone(first, phone, true, 1);
  await db.deposit(first, 100);
  const receiver = await db.verifiedUser();
  assert.equal((await send(first, receiver.phone, 1)).repeated, false);

  await sleep(5);
  const second = await db.addUser();
  await db.bindPhone(second, phone, true, 1);
  const refused = await failure(send(first, receiver.phone, 1));
  assert.equal(refused.code, '42501');
  assert.match(refused.message, /Verify your phone number/);
});

test('DB-V05 a holder who proves the number again goes to the back of the queue', async () => {
  const phone = '+8801700000005';
  const [a, b, c, d] = [await db.addUser(), await db.addUser(), await db.addUser(), await db.addUser()];
  for (const id of [a, b, c]) {
    await db.bindPhone(id, phone, true, 3);
    await sleep(5);
  }
  await db.bindPhone(a, phone, true, 3); // a re-verifies: b is now the oldest
  await sleep(5);
  await db.bindPhone(d, phone, true, 3);
  const phoneOf = async (id: string) => (await db.query(`select phone from public.profiles where user_id = $1`, [id]))[0].phone;
  assert.equal(await phoneOf(b), null, 'b was the oldest after a refreshed');
  assert.equal(await phoneOf(a), phone);
  assert.equal(await phoneOf(c), phone);
  assert.equal(await phoneOf(d), phone);
});

test('DB-V06 binding rejects malformed numbers, a missing account and a pool size under 1', async () => {
  const id = await db.addUser();
  for (const bad of ['', 'abc', '12345', '+1234567890123456', null]) {
    assert.equal((await failure(db.bindPhone(id, bad as any))).code, '22023', String(bad));
  }
  assert.equal((await failure(db.bindPhone(null as any, db.freshPhone()))).code, '22023');
  assert.equal((await failure(db.bindPhone(id, db.freshPhone(), true, 0))).code, '22023');
});

test('DB-V07 once a number is shared, a "real" bind of it is refused (what happens when production switches test numbers off)', async () => {
  const phone = '+8801700000006';
  const tester = await db.addUser();
  await db.bindPhone(tester, phone, true);
  const later = await db.addUser();
  assert.equal((await failure(db.bindPhone(later, phone, false))).code, '23505');
});

test('DB-V08 my_phone_status reports only the caller\'s own number', async () => {
  const { id, phone } = await db.verifiedUser();
  assert.deepEqual(await db.rpc('authenticated', id, 'select public.my_phone_status()'), { phone, verified: true });
  const fresh = await db.addUser();
  assert.deepEqual(await db.rpc('authenticated', fresh, 'select public.my_phone_status()'), { phone: null, verified: false });
  assert.equal(await sqlState(db.call('authenticated', null, 'select public.my_phone_status()')), '42501');
});

// ===========================================================================
// DB-L  Recipient lookup
// ===========================================================================

test('DB-L01 lookup returns a name for a proven, exclusive number, and nothing else about anyone', async () => {
  const alice = await db.verifiedUser();
  const bob = await db.verifiedUser({ name: 'Bob Hossain' });
  assert.deepEqual(await lookup(alice.id, bob.phone), { found: true, full_name: 'Bob Hossain' });
});

test('DB-L02 lookup finds nobody for: yourself, an unproven claim, a shared test number, an unknown number', async () => {
  const alice = await db.verifiedUser();
  const claimer = await db.addUser();
  const claimed = db.freshPhone();
  await db.call('service_role', claimer, 'select public.set_my_phone($1)', [claimed]);
  await db.verifiedUser({ shared: true, phone: '+8801700000007' });
  for (const phone of [alice.phone, claimed, '+8801700000007', '+8801000000009', '', 'not a number']) {
    assert.deepEqual(await lookup(alice.id, phone), { found: false }, phone);
  }
});

test('DB-L03 lookups are capped at 20 a minute per caller', async () => {
  const alice = await db.verifiedUser();
  const bob = await db.verifiedUser();
  // The limiter counts in clock-aligned minutes; do not straddle a boundary.
  const second = new Date().getSeconds();
  if (second >= 56) await sleep((61 - second) * 1000);
  for (let i = 0; i < 20; i++) await lookup(alice.id, bob.phone);
  const blocked = await failure(lookup(alice.id, bob.phone));
  assert.equal(blocked.code, '54000');
  assert.match(blocked.message, /Too many lookups/);
  assert.equal((await lookup(bob.id, alice.phone)).found, true, 'another caller is unaffected');
});

test('DB-L04 a caller with no session cannot look anyone up', async () => {
  assert.equal(await sqlState(db.call('authenticated', null, `select public.lookup_recipient('+8801900000044')`)), '42501');
});

test('DB-L05 todo: an anonymous session cannot use the lookup to enumerate names', { todo: 'SEC-09: lookup_recipient has no is_anonymous check, and anonymous sign-ins are still ON in the live project' }, async () => {
  const guest = await db.addUser({ anonymous: true });
  assert.equal(await sqlState(lookup(guest, '+8801900000044')), '42501');
});

// ===========================================================================
// DB-C  Carrying an anonymous install's data into the account it logs in to
// ===========================================================================

test('DB-C01 an anonymous device\'s documents and contacts move to the account it logs in to, once', async () => {
  const anon = await db.addUser({ anonymous: true });
  const real = await db.addUser();
  await db.query(`insert into public.saved_documents (user_id) values ($1), ($1)`, [anon]);
  await db.query(`insert into public.beneficiaries (user_id, name, phone_number) values ($1, 'Amma', '+8801811111111'), ($1, 'Bhai', '+8801822222222')`, [anon]);
  await db.query(`insert into public.beneficiaries (user_id, name, phone_number) values ($1, 'Amma (mine)', '+8801811111111')`, [real]);

  const token = (await db.call('authenticated', anon, 'select public.issue_anonymous_claim() as t'))[0].t;
  const moved = (await db.call('authenticated', real, 'select public.claim_anonymous_data($1::uuid) as n', [token]))[0].n;
  assert.equal(moved, 3, '2 documents + 1 contact (the duplicate number is dropped, not copied)');
  assert.equal((await db.query(`select count(*)::int as n from public.saved_documents where user_id = $1`, [real]))[0].n, 2);
  assert.equal((await db.query(`select count(*)::int as n from public.beneficiaries where user_id = $1`, [real]))[0].n, 2);
  assert.equal((await db.query(`select count(*)::int as n from public.beneficiaries where user_id = $1`, [anon]))[0].n, 0);

  const replay = (await db.call('authenticated', real, 'select public.claim_anonymous_data($1::uuid) as n', [token]))[0].n;
  assert.equal(replay, 0, 'a claim token is spent on first use');
});

test('DB-C02 only an anonymous session can mint a claim, only a real account can spend one', async () => {
  const anon = await db.addUser({ anonymous: true });
  const real = await db.addUser();
  assert.equal(await sqlState(db.call('authenticated', real, 'select public.issue_anonymous_claim()')), '42501');
  assert.equal(await sqlState(db.call('authenticated', null, 'select public.issue_anonymous_claim()')), '42501');
  const token = (await db.call('authenticated', anon, 'select public.issue_anonymous_claim() as t'))[0].t;
  assert.equal(await sqlState(db.call('authenticated', anon, 'select public.claim_anonymous_data($1::uuid)', [token])), '42501');
});

test('DB-C03 an unknown, expired or someone-else\'s token moves nothing', async () => {
  const anon = await db.addUser({ anonymous: true });
  const real = await db.addUser();
  await db.query(`insert into public.saved_documents (user_id) values ($1)`, [anon]);
  const n = async (token: string) => (await db.call('authenticated', real, 'select public.claim_anonymous_data($1::uuid) as n', [token]))[0].n;
  assert.equal(await n('00000000-0000-4000-8000-000000000000'), 0, 'unknown token');

  const token = (await db.call('authenticated', anon, 'select public.issue_anonymous_claim() as t'))[0].t;
  await db.query(`update public.anonymous_claims set created_at = now() - interval '2 days' where token = $1::uuid`, [token]);
  assert.equal(await n(token), 0, 'expired after a day');
  assert.equal((await db.query(`select count(*)::int as c from public.saved_documents where user_id = $1`, [anon]))[0].c, 1);
});

// ===========================================================================
// DB-X  Whole-ledger properties
// ===========================================================================

test('DB-X01 after 300 random operations, money is conserved and every ledger row adds up', async () => {
  // A fixed seed: the same sequence every run, so a failure is reproducible.
  let seed = 20261020;
  const rand = () => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;
  const pick = <T>(items: readonly T[]) => items[Math.floor(rand() * items.length)];
  const CARDS = ['card_wps', 'card_probashi', 'card_visa'] as const;

  const people = [];
  for (let i = 0; i < 4; i++) people.push(await db.verifiedUser({ funds: 3000 }));
  for (const p of people) {
    await db.deposit(p.id, 2000, 'card_probashi');
    await db.deposit(p.id, 1000, 'card_visa');
  }
  const startTotal = await db.totalMoney();
  let injected = 0;
  const tally: Record<string, number> = {};
  const expected = new Set(['22023', 'P0002', '42501']);

  for (let i = 0; i < 300; i++) {
    const who = pick(people);
    const amount = Math.round(rand() * (rand() < 0.2 ? 9000 : 400) * 1000) / 1000; // includes impossible and over-balance sends
    const kind = Math.floor(rand() * 5);
    let outcome = 'OK';
    try {
      if (kind === 0) await swap(who.id, pick(CARDS), pick(CARDS), amount);
      else if (kind === 1) await send(who.id, pick([...people.map((p) => p.phone), '+8801000000000']), amount);
      else if (kind === 2) {
        const dep = Math.round(rand() * 500 * 100) / 100 + 1;
        await db.deposit(who.id, dep, pick(CARDS));
        injected += Math.round(dep * 100) / 100;
      } else if (kind === 3) await settle(who.id, pick(CARDS), `cs_prop_${i}`, Math.round(rand() * 300 * 100) / 100 + 0.5);
      else await swap(who.id, 'card_gold', 'card_wps', amount);
    } catch (err: any) {
      outcome = err.code ?? 'NO-CODE';
      assert.ok(expected.has(outcome), `operation ${i} (kind ${kind}) failed with unexpected ${outcome}: ${err.message}`);
    }
    tally[`${kind}:${outcome}`] = (tally[`${kind}:${outcome}`] ?? 0) + 1;
  }

  assert.ok(Object.keys(tally).some((k) => k.endsWith(':OK')), 'some operations succeeded');
  assert.ok(Object.keys(tally).some((k) => !k.endsWith(':OK')), 'and some were refused');
  const endTotal = await db.totalMoney();
  assert.equal(Number(endTotal.toFixed(2)), Number((startTotal + injected).toFixed(2)), 'only deposits change the total');
  assert.deepEqual(await db.ledgerViolations(), []);
});

// ===========================================================================
// DB-M  The migrations themselves
// ===========================================================================

test('DB-M01 replaying the migrations that were applied by hand (verified_phone_gate onward) leaves the same working ledger', async () => {
  // `supabase db push` would replay exactly these, because the live project's
  // migration history does not list them. Each replay re-creates the OLDER
  // function bodies first, so the end state is only right if the later files
  // put everything back.
  const replay = MONEY_MIGRATIONS.slice(MONEY_MIGRATIONS.indexOf('20261019170000_verified_phone_gate.sql'));
  assert.ok(replay.length >= 3);
  const again = await LedgerDb.create();
  const alice = await again.verifiedUser({ funds: 123 });
  const bob = await again.verifiedUser();
  const tester = await again.verifiedUser({ shared: true, phone: '+8801700000009' });
  for (const file of replay) await again.pg.exec(migrationSql(file));

  assert.equal(await again.balance(alice.id), 123, 're-running changed no balance');
  assert.deepEqual(await again.ledgerViolations(), []);
  // Still behaves like the newest version: the shared-number rule and per-card wallets survived.
  const asAlice = (sql: string, params: unknown[]) => again.rpc('authenticated', alice.id, sql, params);
  const pay = 'select public.p2p_transfer($1, 5::numeric, $2, null)';
  assert.equal((await asAlice(pay, [bob.phone, ''])).repeated, false);
  const refused = await sqlState(asAlice(pay, ['+8801700000009', '']));
  assert.equal(refused, 'P0002', 'a shared test number still cannot receive after the replay');
  assert.equal(Object.keys(await again.balances(alice.id)).length, 3);
  const privileged = await again.query(
    `select has_function_privilege('authenticated', p.oid, 'EXECUTE') as authed from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.proname in ('deposit_to_wallet','settle_remittance','bind_verified_phone')`,
  );
  assert.ok(privileged.length >= 3 && privileged.every((r: any) => r.authed === false), 'and they are still backend-only');
  void tester;
});

test('DB-M03 todo: p2p_core.sql, which says "safe to run more than once", still runs on top of the later migrations', { todo: 'SEC-11: its backfill uses ON CONFLICT (user_id), a constraint sub_wallets.sql dropped (the bug shared_test_phones.sql fixed in bind_verified_phone)' }, async () => {
  const again = await LedgerDb.create();
  await again.pg.exec(migrationSql('20261019140000_p2p_core.sql'));
});

test('DB-M02 todo: the repo\'s migrations alone can build a database from scratch', { todo: 'SEC-11: harden_rls_security needs public.wallets and fix_rls_saved_documents_notices needs saved_documents; no migration creates either (nor beneficiaries)' }, async () => {
  const pg = await emptyDatabase();
  for (const file of allMigrationFiles()) {
    await pg.exec(migrationSql(file));
  }
});
