-- =============================================================================
-- reset_demo_account.sql  -  DRAFT, NOT EXECUTED AGAINST ANY DATABASE.
--
-- Removes ONLY what a demo/benchmark run creates for ONE demo account
-- (email must start with "demo-"), and keeps the seed data:
--   * invoices / income_entries / planning_entries whose id does NOT start with
--     'demo-seed-'  (soft delete = tombstone + revision bump, so every device
--     that syncs drops them; hard delete would leave them on the devices)
--   * ai_extraction_jobs (OCR / extraction jobs)            [all rows of the user]
--   * ocr_request_replay                                    [if the table exists]
--   * ai_client_events                                      [if the table exists]
--   * chat_messages (chat history changes later answers)    [flag below]
--   * optionally the AI quota counters                      [flag below, default off]
--
-- MARKER CHOICE: the id prefix 'demo-seed-'. Seed rows have deterministic ids
-- with that prefix (seed_demo_account.sql); rows the app creates use UUIDs, so
-- "not like 'demo-seed-%'" = "created during a demo run". A created_at cut-off
-- was rejected: it breaks when the seed is re-run (all seed rows get new
-- timestamps) and under clock skew between the app and the database.
--
-- NOT TOUCHED: ai_request_metrics (that IS the benchmark data), group/fund
-- data (part of the seed), budgets (ids follow the app's '<yyyy-MM>-<category>'
-- convention, so they cannot be told apart; run seed_demo_account.sql again to
-- restore them), Storage objects (receipt images stay in the bucket; delete in
-- the dashboard if needed), device-local data (debts, local chat history,
-- unsynced outbox) - see README.
--
-- HOW TO RUN (Supabase SQL editor): put the user's UUID in the EDIT HERE line,
-- run the whole file in one go, read the result grid (rows removed per table).
-- Recommended order for a clean demo: RESET, then SEED (idempotent), then sync
-- the app (pull-to-refresh) on both instances.
-- =============================================================================

begin;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> EDIT HERE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
select set_config('demo_reset.user_id', '00000000-0000-0000-0000-000000000000', false);
-- true = also delete the account's chat history (recommended between benchmark runs)
select set_config('demo_reset.chat', 'true', false);
-- true = also zero the AI quota counters (use only if the demo account hit 429 by accident)
select set_config('demo_reset.quota', 'false', false);
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> END EDIT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

create temporary table _demo_reset_counts (
  ord serial,
  what text not null,
  n bigint not null
) on commit drop;

do $reset$
declare
  v_user uuid := nullif(current_setting('demo_reset.user_id', true), '')::uuid;
  v_chat boolean := coalesce(nullif(current_setting('demo_reset.chat', true), ''), 'true')::boolean;
  v_quota boolean := coalesce(nullif(current_setting('demo_reset.quota', true), ''), 'false')::boolean;
  v_email text;
  v_n bigint;
  v_table text;
begin
  if v_user is null or v_user = '00000000-0000-0000-0000-000000000000'::uuid then
    raise exception 'Set demo_reset.user_id in the EDIT HERE block first.';
  end if;
  select u.email into v_email from auth.users u where u.id = v_user;
  if v_email is null then
    raise exception 'No auth.users row for %', v_user;
  end if;
  if left(lower(v_email), 5) <> 'demo-' then
    raise exception 'Refusing to reset %: email must start with "demo-"', v_email;
  end if;

  -- Invoices created during the demo (OCR imports, quick entries, assistant).
  update public.invoices i
  set deleted_at = clock_timestamp(), revision = i.revision + 1
  where i.user_id = v_user
    and i.deleted_at is null
    and i.id not like 'demo-seed-%';
  get diagnostics v_n = row_count;
  insert into _demo_reset_counts (what, n) values ('invoices tombstoned', v_n);

  update public.income_entries e
  set deleted_at = clock_timestamp(), updated_at = clock_timestamp()
  where e.user_id = v_user
    and e.deleted_at is null
    and e.id not like 'demo-seed-%';
  get diagnostics v_n = row_count;
  insert into _demo_reset_counts (what, n) values ('income_entries tombstoned', v_n);

  update public.planning_entries p
  set deleted_at = clock_timestamp(), updated_at = clock_timestamp(),
      kind = null, payload = '{}'::jsonb
  where p.user_id = v_user
    and p.deleted_at is null
    and p.id not like 'demo-seed-%';
  get diagnostics v_n = row_count;
  insert into _demo_reset_counts (what, n) values ('planning_entries tombstoned', v_n);

  -- Everything the OCR / extraction pipeline stored for this user.
  if to_regclass('public.ai_extraction_jobs') is not null then
    delete from public.ai_extraction_jobs where user_id = v_user;
    get diagnostics v_n = row_count;
    insert into _demo_reset_counts (what, n) values ('ai_extraction_jobs deleted', v_n);
  end if;

  -- Tables that only exist once the TV1 / TV3 migrations are applied.
  if to_regclass('public.ocr_request_replay') is not null then
    delete from public.ocr_request_replay where user_id = v_user;
    get diagnostics v_n = row_count;
    insert into _demo_reset_counts (what, n) values ('ocr_request_replay deleted', v_n);
  else
    insert into _demo_reset_counts (what, n) values ('ocr_request_replay (table missing, skipped)', 0);
  end if;

  if to_regclass('public.ai_client_events') is not null then
    delete from public.ai_client_events where user_id = v_user;
    get diagnostics v_n = row_count;
    insert into _demo_reset_counts (what, n) values ('ai_client_events deleted', v_n);
  else
    insert into _demo_reset_counts (what, n) values ('ai_client_events (table missing, skipped)', 0);
  end if;

  if v_chat then
    delete from public.chat_messages where user_id = v_user;
    get diagnostics v_n = row_count;
    insert into _demo_reset_counts (what, n) values ('chat_messages deleted', v_n);
  end if;

  if v_quota then
    foreach v_table in array array['ai_usage_buckets', 'ai_cost_usage', 'ai_usage_daily'] loop
      if to_regclass('public.' || v_table) is not null then
        execute format('delete from public.%I where user_id = $1', v_table) using v_user;
        get diagnostics v_n = row_count;
        insert into _demo_reset_counts (what, n) values (v_table || ' deleted', v_n);
      end if;
    end loop;
  end if;

  -- Sanity check: the seed must still be there.
  select count(*) into v_n from public.invoices i
  where i.user_id = v_user and i.deleted_at is null and i.id like 'demo-seed-%';
  insert into _demo_reset_counts (what, n) values ('seed invoices still active (expect 46, or 60 when the fixed 2026-10 set exists)', v_n);

  raise notice 'Reset % (%) done.', v_email, v_user;
end;
$reset$;

select what, n from _demo_reset_counts order by ord;

commit;
