create function public.cleanup_ai_request_metrics(
  p_retention_days integer default 30
)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_deleted bigint;
  v_days integer := least(greatest(coalesce(p_retention_days, 30), 7), 90);
begin
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Worker role required' using errcode = '42501';
  end if;
  with expired as (
    select id
    from public.ai_request_metrics
    where created_at < now() - make_interval(days => v_days)
    order by created_at
    limit 5000
    for update skip locked
  )
  delete from public.ai_request_metrics as metrics
  using expired
  where metrics.id = expired.id;
  get diagnostics v_deleted = row_count;
  return coalesce(v_deleted, 0);
end;
$$;

revoke all on function public.cleanup_ai_request_metrics(integer) from public, anon, authenticated;
grant execute on function public.cleanup_ai_request_metrics(integer) to service_role;
