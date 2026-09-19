create or replace function public.cleanup_ai_extraction_inputs()
returns table (id uuid, input_path text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Worker role required' using errcode = '42501';
  end if;
  return query
  select jobs.id, jobs.input_path
  from public.ai_extraction_jobs as jobs
  where jobs.input_path is not null
    and jobs.input_expires_at is not null
    and jobs.input_expires_at <= now()
  order by jobs.input_expires_at, jobs.id
  limit 20
  for update skip locked;
end;
$$;

revoke all on function public.cleanup_ai_extraction_inputs()
  from public, anon, authenticated;
grant execute on function public.cleanup_ai_extraction_inputs()
  to service_role;

create index if not exists ai_cost_usage_period_start_idx
  on public.ai_cost_usage (period_start);

create or replace function public.cleanup_sync_request_metrics(
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
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Worker role required' using errcode = '42501';
  end if;
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

create or replace function public.cleanup_ai_cost_usage(
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
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Worker role required' using errcode = '42501';
  end if;
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

revoke all on function public.cleanup_sync_request_metrics(integer)
  from public, anon, authenticated;
grant execute on function public.cleanup_sync_request_metrics(integer)
  to service_role;

revoke all on function public.cleanup_ai_cost_usage(integer)
  from public, anon, authenticated;
grant execute on function public.cleanup_ai_cost_usage(integer)
  to service_role;
