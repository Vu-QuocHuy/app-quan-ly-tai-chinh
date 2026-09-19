create or replace function public.cleanup_ai_extraction_jobs(
  p_retention_days integer default 30
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_retention_days integer;
  v_deleted integer;
begin
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Worker role required' using errcode = '42501';
  end if;
  v_retention_days := least(greatest(coalesce(p_retention_days, 30), 7), 90);
  with expired as (
    select jobs.id
    from public.ai_extraction_jobs as jobs
    where jobs.status in ('succeeded', 'failed', 'cancelled')
      and jobs.completed_at is not null
      and jobs.completed_at <= now() - make_interval(days => v_retention_days)
      and jobs.input_path is null
    order by jobs.completed_at, jobs.id
    for update skip locked
    limit 500
  )
  delete from public.ai_extraction_jobs as jobs
  using expired
  where jobs.id = expired.id;
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.cleanup_ai_extraction_jobs(integer)
  from public, anon, authenticated;
grant execute on function public.cleanup_ai_extraction_jobs(integer)
  to service_role;
