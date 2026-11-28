-- =============================================================================
-- seed_demo_account.sql  -  DRAFT, NOT EXECUTED AGAINST ANY DATABASE.
--
-- Seeds ONE demo account (email must start with "demo-") with the sample data
-- that tool/demo/seed_expectations.json was computed from. Run it once for
-- demo-b0 and once for demo-b1 with the SAME file: identical data is guaranteed
-- because every amount, merchant and day-of-month below is a literal and the
-- only per-account inputs are user_id-derived ids (group id / invite code).
--
-- HOW TO RUN (Supabase dashboard > SQL editor, role postgres):
--   1. Authentication > Users: create demo-b0@... and demo-b1@... (see README).
--   2. Copy each user's UUID.
--   3. Replace the zero UUID in the "EDIT HERE" line below, paste the WHOLE file
--      and click Run. Run the entire file in ONE go (the user id is kept in a
--      session setting that the later statements read back).
--   4. The last result grid lists the values the app should answer with today;
--      compare it with tool/demo/seed_expectations.json.
--   5. Edit the UUID and run again for the second account.
--
-- IDEMPOTENT: every row has a deterministic id ('demo-seed-...'); re-running
-- upserts them (revision + 1 so devices re-pull), and seed rows that no longer
-- belong to the current calendar window are soft-deleted. Nothing is duplicated.
--
-- DATES are relative to now() in Asia/Ho_Chi_Minh (12:00 local time, day <= 28):
--   role c = current month, p = previous month, q = two months ago,
--   f = fixed 2026-10 (copy of role p, only inserted when 2026-10 is not already
--       one of c/p/q). The app resolves "Tháng 10" with the CURRENT YEAR, so the
--   expectation for Q12 is only valid while the demo runs in calendar year 2026.
--   The expected values in seed_expectations.json were derived for a run in
--   2026-11. In 2026-12 Q06 and Q12 differ; in 2026-10 Q01/Q06/Q12 differ
--   (the script prints a NOTICE in those cases).
--
-- NOT SEEDED HERE (cannot be): debts live in the device (SharedPreferences,
-- key finmi.debts.<userId>.v1); see README "Khoản nợ".
-- =============================================================================

begin;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> EDIT HERE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
select set_config('demo_seed.user_id', '00000000-0000-0000-0000-000000000000', false);
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> END EDIT <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

do $seed$
declare
  c_tz constant text := 'Asia/Ho_Chi_Minh';
  v_user uuid := nullif(current_setting('demo_seed.user_id', true), '')::uuid;
  v_email text;
  v_cur timestamp := date_trunc('month', now() at time zone 'Asia/Ho_Chi_Minh');
  v_fixed constant timestamp := timestamp '2026-10-01 00:00:00';
  v_include_f boolean;
  v_rec record;
  v_id text;
  v_issued timestamptz;
  v_ids text[] := '{}';
  v_old bigint;
  v_n_invoices integer := 0;
  v_n_income integer := 0;
  v_n_stale integer := 0;
  v_group uuid;
  v_month_key text;
  v_next_month timestamp;
begin
  -- ---- guards -------------------------------------------------------------
  if v_user is null or v_user = '00000000-0000-0000-0000-000000000000'::uuid then
    raise exception 'Set demo_seed.user_id in the EDIT HERE block first.';
  end if;
  select u.email into v_email from auth.users u where u.id = v_user;
  if v_email is null then
    raise exception 'No auth.users row for %', v_user;
  end if;
  if left(lower(v_email), 5) <> 'demo-' then
    raise exception 'Refusing to seed %: email must start with "demo-"', v_email;
  end if;
  if not exists (select 1 from public.profiles p where p.user_id = v_user) then
    insert into public.profiles (user_id, display_name)
    values (v_user, 'Demo') on conflict (user_id) do nothing;
  end if;

  v_include_f := v_fixed not in (
    v_cur, v_cur - interval '1 month', v_cur - interval '2 months'
  );
  if v_cur <> timestamp '2026-11-01' then
    raise notice 'Run month is % but seed_expectations.json was derived for 2026-11; Q06 and Q12 (and Q01 in 2026-10) may differ, see README.',
      to_char(v_cur, 'YYYY-MM');
  end if;

  -- ---- default expense categories (budgets reference them) ----------------
  insert into public.categories (user_id, id, name, icon_name, color_value, is_system)
  select v_user, d.id, d.name, d.icon_name, d.color_value, true
  from (values
    ('food', 'Ăn uống', 'restaurant', 4293548044::bigint),
    ('transport', 'Di chuyển', 'directions_car', 4280640491::bigint),
    ('shopping', 'Mua sắm', 'shopping_bag', 4286331629::bigint),
    ('utilities', 'Tiện ích', 'bolt', 4291463684::bigint),
    ('health', 'Y tế', 'health_and_safety', 4292617766::bigint),
    ('education', 'Giáo dục', 'school', 4278751666::bigint),
    ('entertainment', 'Giải trí', 'movie', 4292552567::bigint),
    ('other', 'Khác', 'category', 4284773515::bigint)
  ) as d(id, name, icon_name, color_value)
  on conflict (user_id, id) do nothing;

  -- ---- invoices (expenses) ------------------------------------------------
  -- One row per line: (role, seq, day-of-month, merchant, category, amount VND).
  -- tool/demo/test_check_seed_expectations.py parses exactly this layout.
  -- Rows are inserted ordered by (role, day, seq); invoices.updated_at is set
  -- by a server trigger (clock_timestamp), so the LAST inserted row is the
  -- "most recent invoice" for the app: that is the c row with the highest day.
  for v_rec in
    with seed(grp, seq, day, merchant, category, amount) as (values
      -- SEED-INVOICES-BEGIN
      ('c', 1, 1, 'Thuê nhà', 'utilities', 3000000),
      ('c', 2, 2, 'Co.opmart', 'food', 1250000),
      ('c', 3, 3, 'Highlands Coffee', 'food', 60000),
      ('c', 4, 5, 'Netflix', 'entertainment', 260000),
      ('c', 5, 6, 'Grab', 'transport', 180000),
      ('c', 6, 7, 'Phở 24', 'food', 130000),
      ('c', 7, 9, 'Bánh mì Huỳnh Hoa', 'food', 90000),
      ('c', 8, 11, 'Uniqlo', 'shopping', 890000),
      ('c', 9, 12, 'FPT Internet', 'utilities', 220000),
      ('c', 10, 13, 'Petrolimex', 'transport', 420000),
      ('c', 11, 14, 'Nhà thuốc Long Châu', 'health', 215000),
      ('c', 12, 15, 'Highlands Coffee', 'food', 540000),
      ('c', 13, 16, 'Nhà sách Fahasa', 'education', 185000),
      ('c', 14, 18, 'Tiki', 'shopping', 610000),
      ('c', 15, 19, 'Be', 'transport', 300000),
      ('c', 16, 20, 'Siêu thị GO!', 'food', 1100000),
      ('c', 17, 22, 'KFC', 'food', 455000),
      ('c', 18, 24, 'The Pizza Company', 'food', 640000),
      ('p', 1, 1, 'Thuê nhà', 'utilities', 3000000),
      ('p', 2, 3, 'Highlands Coffee', 'food', 60000),
      ('p', 3, 4, 'WinMart', 'food', 1180000),
      ('p', 4, 5, 'Netflix', 'entertainment', 260000),
      ('p', 5, 7, 'Gojek', 'transport', 210000),
      ('p', 6, 8, 'Lẩu Phan', 'food', 720000),
      ('p', 7, 10, 'Shopee', 'shopping', 1350000),
      ('p', 8, 12, 'FPT Internet', 'utilities', 220000),
      ('p', 9, 14, 'Shell', 'transport', 380000),
      ('p', 10, 15, 'Bệnh viện Vinmec', 'health', 640000),
      ('p', 11, 17, 'Highlands Coffee', 'food', 60000),
      ('p', 12, 19, 'CGV Cinemas', 'entertainment', 240000),
      ('p', 13, 21, 'Bách Hóa Xanh', 'food', 910000),
      ('p', 14, 23, 'Circle K', 'food', 85000),
      ('q', 1, 1, 'Thuê nhà', 'utilities', 3000000),
      ('q', 2, 2, 'Highlands Coffee', 'food', 60000),
      ('q', 3, 5, 'Netflix', 'entertainment', 260000),
      ('q', 4, 6, 'Lotte Mart', 'food', 1320000),
      ('q', 5, 7, 'Xanh SM', 'transport', 250000),
      ('q', 6, 9, 'Highlands Coffee', 'food', 60000),
      ('q', 7, 10, 'Nhà hàng Ngon', 'food', 880000),
      ('q', 8, 12, 'FPT Internet', 'utilities', 220000),
      ('q', 9, 13, 'Zara', 'shopping', 1680000),
      ('q', 10, 15, 'Caltex', 'transport', 350000),
      ('q', 11, 17, 'Udemy', 'education', 1200000),
      ('q', 12, 19, 'Pharmacity', 'health', 160000),
      ('q', 13, 21, 'Mì Cay Seoul', 'food', 145000),
      ('q', 14, 23, 'Nhà hàng Hải Sản Biển Đông', 'food', 960000)
      -- SEED-INVOICES-END
    ),
    expanded as (
      select grp as out_grp, seq, day, merchant, category, amount,
             case grp
               when 'c' then v_cur
               when 'p' then v_cur - interval '1 month'
               else v_cur - interval '2 months'
             end as month_start
      from seed
      union all
      -- role f: the fixed 2026-10 month reuses the previous-month sample rows.
      select 'f', seq, day, merchant, category, amount, v_fixed
      from seed
      where grp = 'p' and v_include_f
    )
    select out_grp, seq, day, merchant, category, amount, month_start
    from expanded
    order by case out_grp when 'q' then 1 when 'f' then 2 when 'p' then 3 else 4 end,
             day, seq
  loop
    v_issued := (v_rec.month_start + make_interval(days => v_rec.day - 1)
                 + interval '12 hours') at time zone c_tz;
    v_id := format('demo-seed-%s-%s', v_rec.out_grp, lpad(v_rec.seq::text, 2, '0'));
    v_ids := v_ids || v_id;

    insert into public.invoices (
      user_id, id, seller_name, issued_at, currency_code,
      subtotal_minor, tax_minor, discount_minor, total_minor,
      source_type, source_hash, status, category_id, notes, tags,
      revision, confirmed_at, deleted_at, created_at
    ) values (
      v_user, v_id, v_rec.merchant, v_issued, 'VND',
      v_rec.amount, 0, 0, v_rec.amount,
      'manual', null, 'confirmed', v_rec.category, 'Dữ liệu mẫu demo', '{}',
      1, v_issued, null, v_issued
    )
    on conflict (user_id, id) do update set
      seller_name = excluded.seller_name,
      issued_at = excluded.issued_at,
      currency_code = excluded.currency_code,
      subtotal_minor = excluded.subtotal_minor,
      tax_minor = excluded.tax_minor,
      discount_minor = excluded.discount_minor,
      total_minor = excluded.total_minor,
      source_type = excluded.source_type,
      source_hash = excluded.source_hash,
      status = excluded.status,
      category_id = excluded.category_id,
      notes = excluded.notes,
      confirmed_at = excluded.confirmed_at,
      deleted_at = null,
      created_at = excluded.created_at,
      revision = public.invoices.revision + 1;
    -- updated_at is overwritten by trigger invoices_server_updated_at.
    v_n_invoices := v_n_invoices + 1;
    perform pg_sleep(0.002); -- keep updated_at strictly increasing in row order
  end loop;

  -- Seed rows that are no longer part of the current window (e.g. role f once
  -- the run month moves) become tombstones so devices drop them on next pull.
  update public.invoices i
  set deleted_at = clock_timestamp(), revision = i.revision + 1
  where i.user_id = v_user
    and i.id like 'demo-seed-%'
    and i.deleted_at is null
    and not (i.id = any (v_ids));
  get diagnostics v_n_stale = row_count;

  -- ---- income entries -----------------------------------------------------
  -- (role, seq, day, amount VND, source, category, note)
  for v_rec in
    with seed(grp, seq, day, amount, source, category, note) as (values
      -- SEED-INCOME-BEGIN
      ('c', 1, 5, 15000000, 'fixed', 'income_salary', 'Lương tháng'),
      ('c', 2, 12, 3500000, 'manual', 'income_bonus', 'Thưởng dự án'),
      ('p', 1, 5, 15000000, 'fixed', 'income_salary', 'Lương tháng'),
      ('p', 2, 20, 2000000, 'manual', 'income_business', 'Làm thêm freelance'),
      ('q', 1, 5, 15000000, 'fixed', 'income_salary', 'Lương tháng')
      -- SEED-INCOME-END
    ),
    expanded as (
      select grp as out_grp, seq, day, amount, source, category, note,
             case grp
               when 'c' then v_cur
               when 'p' then v_cur - interval '1 month'
               else v_cur - interval '2 months'
             end as month_start
      from seed
      union all
      select 'f', seq, day, amount, source, category, note, v_fixed
      from seed
      where grp = 'p' and v_include_f
    )
    select out_grp, seq, day, amount, source, category, note, month_start
    from expanded
    order by out_grp, seq
  loop
    v_issued := (v_rec.month_start + make_interval(days => v_rec.day - 1)
                 + interval '12 hours') at time zone c_tz;
    v_id := format('demo-seed-inc-%s-%s', v_rec.out_grp, lpad(v_rec.seq::text, 2, '0'));
    v_ids := v_ids || v_id;

    insert into public.income_entries (
      user_id, id, amount_minor, source, category_id, note,
      received_at, updated_at, deleted_at
    ) values (
      v_user, v_id, v_rec.amount, v_rec.source, v_rec.category, v_rec.note,
      v_issued, clock_timestamp(), null
    )
    on conflict (user_id, id) do update set
      amount_minor = excluded.amount_minor,
      source = excluded.source,
      category_id = excluded.category_id,
      note = excluded.note,
      received_at = excluded.received_at,
      updated_at = clock_timestamp(),
      deleted_at = null;
    v_n_income := v_n_income + 1;
  end loop;

  update public.income_entries e
  set deleted_at = clock_timestamp(), updated_at = clock_timestamp()
  where e.user_id = v_user
    and e.id like 'demo-seed-inc-%'
    and e.deleted_at is null
    and not (e.id = any (v_ids));

  -- ---- recurring bills (planning_entries, kind = 'bill') -------------------
  -- Deliberately NO recurring income plan: the app auto-posts due recurring
  -- incomes (AppShell._processDueRecurringIncomes) and would change totals.
  v_next_month := v_cur + interval '1 month';
  insert into public.planning_entries (user_id, id, kind, payload, updated_at, deleted_at)
  values
    (v_user, 'demo-seed-plan-01', 'bill',
     jsonb_build_object(
       'title', 'Thuê nhà', 'amountMinor', 3000000, 'frequency', 'monthly',
       'categoryId', 'utilities',
       'anchorDate', to_char(v_cur - interval '2 months', 'YYYY-MM-DD'),
       'nextDueDate', to_char(v_next_month, 'YYYY-MM-DD')),
     clock_timestamp(), null),
    (v_user, 'demo-seed-plan-02', 'bill',
     jsonb_build_object(
       'title', 'Netflix', 'amountMinor', 260000, 'frequency', 'monthly',
       'categoryId', 'entertainment',
       'anchorDate', to_char(v_cur - interval '2 months' + interval '4 days', 'YYYY-MM-DD'),
       'nextDueDate', to_char(v_next_month + interval '4 days', 'YYYY-MM-DD')),
     clock_timestamp(), null)
  on conflict (user_id, id) do update set
    kind = excluded.kind,
    payload = excluded.payload,
    updated_at = clock_timestamp(),
    deleted_at = null;

  -- ---- budgets (current month) --------------------------------------------
  -- Budgets/categories are pulled from public.reference_sync_events (a change
  -- log), NOT from the tables, so a changed budget also needs an event row.
  -- Budget id convention of the app (budget_screen.dart): '<yyyy-MM>-<category>'.
  v_month_key := to_char(v_cur, 'YYYY-MM');
  for v_rec in
    select * from (values
      -- SEED-BUDGET-BEGIN
      ('food', 5000000),
      ('transport', 1000000),
      ('shopping', 2000000),
      ('utilities', 3500000),
      ('entertainment', 500000)
      -- SEED-BUDGET-END
    ) as b(category, limit_minor)
  loop
    v_id := v_month_key || '-' || v_rec.category;
    select b.limit_minor into v_old
    from public.budgets b where b.user_id = v_user and b.id = v_id;

    insert into public.budgets (user_id, id, month_key, category_id, limit_minor, updated_at)
    values (v_user, v_id, v_month_key, v_rec.category, v_rec.limit_minor, now())
    on conflict (user_id, id) do update set
      month_key = excluded.month_key,
      category_id = excluded.category_id,
      limit_minor = excluded.limit_minor,
      updated_at = now();

    if v_old is distinct from v_rec.limit_minor then
      insert into public.reference_sync_events (
        user_id, event_id, aggregate_type, operation, revision, payload
      ) values (
        v_user,
        'demo-seed:budget:' || v_id || ':' || v_rec.limit_minor || ':'
          || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS'),
        'budget', 'upsert', 1,
        jsonb_build_object(
          'id', v_id, 'monthKey', v_month_key,
          'categoryId', v_rec.category, 'limitMinor', v_rec.limit_minor
        )
      );
    end if;
  end loop;

  -- ---- group "Du lịch Đà Lạt" with a shared fund ---------------------------
  -- Fund balance = 3.000.000 + 2.000.000 - 1.250.000 = 3.750.000 VND.
  -- Ids derive from the user id so two demo accounts never collide on the
  -- unique invite_code / primary keys while holding identical amounts.
  v_group := md5('demo-seed-group:' || v_user::text)::uuid;
  insert into public.expense_groups (id, owner_id, name, invite_code)
  values (v_group, v_user, 'Du lịch Đà Lạt',
          upper(substr(md5('demo-seed-invite:' || v_user::text), 1, 8)))
  on conflict (id) do update set name = excluded.name;

  insert into public.expense_group_members (group_id, user_id, display_name, role)
  values (v_group, v_user, 'Demo', 'owner')
  on conflict (group_id, user_id) do nothing;

  insert into public.group_fund_entries (id, group_id, actor_id, kind, amount_minor, note, created_at)
  values
    (md5('demo-seed-fund:' || v_user::text || ':1')::uuid, v_group, v_user,
     'deposit', 3000000, 'Đóng quỹ đợt 1', now() - interval '20 days'),
    (md5('demo-seed-fund:' || v_user::text || ':2')::uuid, v_group, v_user,
     'deposit', 2000000, 'Đóng quỹ đợt 2', now() - interval '12 days'),
    (md5('demo-seed-fund:' || v_user::text || ':3')::uuid, v_group, v_user,
     'expense', 1250000, 'Đặt homestay', now() - interval '5 days')
  on conflict (id) do update set
    kind = excluded.kind,
    amount_minor = excluded.amount_minor,
    note = excluded.note;

  raise notice 'Seeded % (%): % invoices upserted, % stale seed invoices tombstoned, % income rows.',
    v_email, v_user, v_n_invoices, v_n_stale, v_n_income;
end;
$seed$;

-- ---- what the app should answer today (compare with seed_expectations.json) --
-- forecast / scenario depend on today's day-of-month, hence MANUAL keys.
with p as (
  select current_setting('demo_seed.user_id')::uuid as uid,
         date_trunc('month', now() at time zone 'Asia/Ho_Chi_Minh') as cur,
         extract(day from now() at time zone 'Asia/Ho_Chi_Minh')::int as today
),
months(k, ms) as (
  select 'expense_total_current', cur from p
  union all select 'expense_total_previous', cur - interval '1 month' from p
  union all select 'expense_total_prev_prev (Q06 shows this as "tháng trước")', cur - interval '2 months' from p
  union all select 'expense_total_2026_10', timestamp '2026-10-01'
),
sums as (
  select m.k, m.ms,
         coalesce((
           select sum(i.total_minor)
           from public.invoices i
           where i.user_id = (select uid from p)
             and i.deleted_at is null
             and i.status = 'confirmed'
             and i.issued_at >= (m.ms at time zone 'Asia/Ho_Chi_Minh')
             and i.issued_at < ((m.ms + interval '1 month') at time zone 'Asia/Ho_Chi_Minh')
         ), 0) as total
  from months m
),
cur_income as (
  select coalesce(sum(e.amount_minor), 0) as total
  from public.income_entries e, p
  where e.user_id = p.uid and e.deleted_at is null
    and e.received_at >= (p.cur at time zone 'Asia/Ho_Chi_Minh')
    and e.received_at < ((p.cur + interval '1 month') at time zone 'Asia/Ho_Chi_Minh')
),
cur_expense as (select total from sums where k = 'expense_total_current'),
forecast as (
  select round(
           (select total from cur_expense)::numeric
           / p.today
           * extract(day from (p.cur + interval '1 month') - interval '1 day')
         )::bigint as v
  from p
),
budget as (
  select coalesce(sum(b.limit_minor), 0) as total
  from public.budgets b, p
  where b.user_id = p.uid and b.month_key = to_char(p.cur, 'YYYY-MM')
),
lines(k, v) as (
  select k, total from sums
  union all select 'income_total_current', total from cur_income
  union all select 'budget_limit_current (budget_remaining_current uses this)', total from budget
  union all select 'forecast_month_end (today)', v from forecast
  union all select 'scenario_saving_500k (today, 1 month)',
                   (select total from cur_income) - v + 500000 from forecast
)
select k as key,
       replace(to_char(v, 'FM999,999,999,999'), ',', '.') as vnd_digits
from lines
order by 1;

commit;
