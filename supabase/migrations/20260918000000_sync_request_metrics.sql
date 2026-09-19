create table public.sync_request_metrics (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  direction text not null check (direction in ('push', 'pull')),
  aggregate_type text not null check (aggregate_type in ('invoice', 'category', 'budget', 'merchant_rule')),
  status_code integer not null check (status_code between 100 and 599),
  duration_ms integer not null check (duration_ms between 0 and 600000),
  batch_size integer not null check (batch_size between 0 and 200),
  error_code text check (error_code is null or error_code ~ '^[A-Z0-9_]{1,64}$'),
  created_at timestamptz not null default now()
);

create index sync_request_metrics_created_at_idx
  on public.sync_request_metrics (created_at desc);
create index sync_request_metrics_dimension_idx
  on public.sync_request_metrics (direction, aggregate_type, created_at desc);

alter table public.sync_request_metrics enable row level security;
revoke all on public.sync_request_metrics from public, anon, authenticated;

create function public.record_sync_request_metric(
  p_direction text,
  p_aggregate_type text,
  p_status_code integer,
  p_duration_ms integer,
  p_batch_size integer,
  p_error_code text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_error_code text := nullif(trim(coalesce(p_error_code, '')), '');
begin
  if v_user_id is null then
    return;
  end if;
  if p_direction not in ('push', 'pull') then
    return;
  end if;
  if p_aggregate_type not in ('invoice', 'category', 'budget', 'merchant_rule') then
    return;
  end if;
  if p_status_code is null or p_status_code not between 100 and 599 then
    return;
  end if;
  if p_duration_ms is null or p_duration_ms not between 0 and 600000 then
    return;
  end if;
  if p_batch_size is null or p_batch_size not between 0 and 200 then
    return;
  end if;
  if v_error_code is not null and v_error_code !~ '^[A-Z0-9_]{1,64}$' then
    v_error_code := null;
  end if;

  insert into public.sync_request_metrics (
    user_id,
    direction,
    aggregate_type,
    status_code,
    duration_ms,
    batch_size,
    error_code
  )
  values (
    v_user_id,
    p_direction,
    p_aggregate_type,
    p_status_code,
    p_duration_ms,
    p_batch_size,
    v_error_code
  );

  if mod(extract(epoch from clock_timestamp())::bigint, 100) = 0 then
    delete from public.sync_request_metrics
    where user_id = v_user_id
      and created_at < now() - interval '30 days';
  end if;
end;
$$;

revoke all on function public.record_sync_request_metric(text, text, integer, integer, integer, text)
  from public, anon;
grant execute on function public.record_sync_request_metric(text, text, integer, integer, integer, text)
  to authenticated;

create function public.cleanup_sync_request_metrics(
  p_retention_days integer default 30
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_retention_days integer := least(greatest(coalesce(p_retention_days, 30), 7), 90);
  v_deleted integer := 0;
begin
  with expired as (
    select id
    from public.sync_request_metrics
    where created_at < now() - make_interval(days => v_retention_days)
    order by created_at
    limit 5000
    for update skip locked
  )
  delete from public.sync_request_metrics as metrics
  using expired
  where metrics.id = expired.id;
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.cleanup_sync_request_metrics(integer)
  from public, anon, authenticated;
grant execute on function public.cleanup_sync_request_metrics(integer)
  to service_role;

create or replace view public.sync_request_slo_daily as
select
  (date_trunc('day', created_at) at time zone 'utc')::date as report_day,
  direction,
  aggregate_type,
  count(*) as request_count,
  count(*) filter (where status_code >= 500) as server_error_count,
  round(
    100.0 * count(*) filter (where status_code >= 500) / nullif(count(*), 0),
    2
  ) as server_error_rate_percent,
  percentile_cont(0.95) within group (order by duration_ms)::integer as p95_duration_ms
from public.sync_request_metrics
group by report_day, direction, aggregate_type;

revoke all on public.sync_request_slo_daily from public, anon, authenticated;
grant select on public.sync_request_slo_daily to service_role;
