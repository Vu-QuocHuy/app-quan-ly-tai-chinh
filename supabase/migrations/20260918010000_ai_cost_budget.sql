create table public.ai_cost_budgets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  daily_limit_units integer not null default 1000
    check (daily_limit_units between 1 and 10000000),
  monthly_limit_units integer not null default 10000
    check (monthly_limit_units between 1 and 100000000),
  updated_at timestamptz not null default now()
);

create table public.ai_cost_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  period_type text not null check (period_type in ('day', 'month')),
  period_start date not null,
  consumed_units bigint not null default 0 check (consumed_units >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, period_type, period_start)
);

alter table public.ai_cost_budgets enable row level security;
alter table public.ai_cost_usage enable row level security;
revoke all on public.ai_cost_budgets from public, anon, authenticated;
revoke all on public.ai_cost_usage from public, anon, authenticated;

create function public.consume_ai_cost_budget(
  p_cost_units integer
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_cost_units integer := least(greatest(coalesce(p_cost_units, 1), 1), 100);
  v_default_daily integer := 1000;
  v_default_monthly integer := 10000;
  v_usage_day date := (now() at time zone 'utc')::date;
  v_usage_month date := date_trunc('month', now() at time zone 'utc')::date;
  v_daily_limit integer;
  v_monthly_limit integer;
  v_daily_used bigint;
  v_monthly_used bigint;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  delete from public.ai_cost_usage
  where user_id = v_user_id
    and (
      (period_type = 'day' and period_start < v_usage_day - 90)
      or (period_type = 'month' and period_start < v_usage_month - 400)
    );

  insert into public.ai_cost_budgets (
    user_id,
    daily_limit_units,
    monthly_limit_units
  )
  values (v_user_id, v_default_daily, v_default_monthly)
  on conflict (user_id) do nothing;

  select daily_limit_units, monthly_limit_units
    into v_daily_limit, v_monthly_limit
  from public.ai_cost_budgets
  where user_id = v_user_id
  for update;

  insert into public.ai_cost_usage (user_id, period_type, period_start)
    values
      (v_user_id, 'day', v_usage_day),
      (v_user_id, 'month', v_usage_month)
  on conflict (user_id, period_type, period_start) do nothing;

  select consumed_units into v_daily_used
  from public.ai_cost_usage
  where user_id = v_user_id
    and period_type = 'day'
    and period_start = v_usage_day
  for update;

  select consumed_units into v_monthly_used
  from public.ai_cost_usage
  where user_id = v_user_id
    and period_type = 'month'
    and period_start = v_usage_month
  for update;

  if v_daily_used + v_cost_units > v_daily_limit
     or v_monthly_used + v_cost_units > v_monthly_limit then
    return false;
  end if;

  update public.ai_cost_usage
  set consumed_units = consumed_units + v_cost_units,
      updated_at = now()
  where user_id = v_user_id
    and period_type = 'day'
    and period_start = v_usage_day;

  update public.ai_cost_usage
  set consumed_units = consumed_units + v_cost_units,
      updated_at = now()
  where user_id = v_user_id
    and period_type = 'month'
    and period_start = v_usage_month;
  return true;
end;
$$;

revoke all on function public.consume_ai_cost_budget(integer)
  from public, anon;
grant execute on function public.consume_ai_cost_budget(integer)
  to authenticated;

create function public.cleanup_ai_cost_usage(
  p_retention_days integer default 400
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_retention_days integer := least(greatest(coalesce(p_retention_days, 400), 90), 730);
  v_deleted integer := 0;
begin
  with expired as (
    select user_id, period_type, period_start
    from public.ai_cost_usage
    where period_start < (now() at time zone 'utc')::date - v_retention_days
    order by period_start
    limit 5000
    for update skip locked
  )
  delete from public.ai_cost_usage as usage
  using expired
  where usage.user_id = expired.user_id
    and usage.period_type = expired.period_type
    and usage.period_start = expired.period_start;
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.cleanup_ai_cost_usage(integer)
  from public, anon, authenticated;
grant execute on function public.cleanup_ai_cost_usage(integer)
  to service_role;
