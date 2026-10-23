// Isolated PostgreSQL fixture: never connects to a Supabase project.
import { PGlite } from 'npm:@electric-sql/pglite@0.3.14';
const db = new PGlite();
const actor = '00000000-0000-4000-8000-000000000001';
const other = '00000000-0000-4000-8000-000000000002';
const group = '00000000-0000-4000-8000-000000000003';
const entry = '00000000-0000-4000-8000-000000000004';
const assert = (ok, message) => { if (!ok) throw new Error(message); };
async function rejected(sql, code) {
  try { await db.exec(sql); } catch (error) { assert(error.code === code, `Expected ${code}, got ${error.code}`); return; }
  throw new Error(`Expected rejection ${code}`);
}
try {
  await db.exec(`
    create role anon; create role authenticated;
    create schema auth;
    create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create table public.expense_groups(id uuid primary key);
    create table public.expense_group_members(group_id uuid, user_id uuid);
    create table public.group_fund_entries(id uuid primary key, group_id uuid, actor_id uuid, kind text, amount_minor bigint, note text);
    create function public.is_current_user_expense_group_member(g uuid) returns boolean language sql as $$ select exists(select 1 from public.expense_group_members where group_id=g and user_id=auth.uid()) $$;
    insert into expense_groups values ('${group}');
    insert into expense_group_members values ('${group}', '${actor}'), ('${group}', '${other}');
    insert into group_fund_entries values ('${entry}', '${group}', '${actor}', 'deposit', 100000, 'Initial deposit');
    select set_config('request.jwt.claim.sub', '${actor}', false);
  `);
  await db.exec(await Deno.readTextFile('supabase/migrations/20261023140000_update_own_group_fund_entry.sql'));
  const call = (amount, expected = 100000, note = 'Initial deposit') => `select public.update_own_group_fund_entry('${entry}', ${amount}, 'Corrected', ${expected}, '${note}')`;
  await rejected(call(-1), '22023');
  await rejected(call(150000, 99999), '40001');
  await db.exec(`select set_config('request.jwt.claim.sub', '${other}', false)`);
  await rejected(call(150000), '28000');
  await db.exec(`select set_config('request.jwt.claim.sub', '', false)`);
  await rejected(call(150000), '28000');
  await db.exec(`select set_config('request.jwt.claim.sub', '${actor}', false)`);
  await db.exec(call(150000));
  assert((await db.query(`select amount_minor::text as amount, note from group_fund_entries where id='${entry}'`)).rows[0].amount === '150000', 'Correction failed');
  await rejected(call(140000), '40001');
  await db.exec(`insert into group_fund_entries values ('00000000-0000-4000-8000-000000000005', '${group}', '${actor}', 'expense', 100000, 'Used funds')`);
  await rejected(call(50000, 150000, 'Corrected'), 'UF001');
  await db.exec(call(100000, 150000, 'Corrected'));
  const balance = (await db.query(`select sum(case when kind='deposit' then amount_minor else -amount_minor end)::text as balance from group_fund_entries`)).rows[0].balance;
  assert(balance === '0', 'Balance invariant violated');
  console.log('PASS: migration syntax, actor/member/auth checks, compare-and-swap, balance protection and valid correction');
} finally { await db.close(); }
