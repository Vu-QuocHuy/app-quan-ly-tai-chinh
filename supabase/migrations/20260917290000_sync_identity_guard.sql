create or replace function public.apply_invoice_sync_checked(
  p_expected_user_id uuid,
  p_operation text,
  p_payload jsonb,
  p_revision integer
)
returns void
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if p_expected_user_id is null or p_expected_user_id is distinct from (select auth.uid()) then
    raise exception 'Authentication session changed' using errcode = '28000';
  end if;
  perform public.apply_invoice_sync(p_operation, p_payload, p_revision);
end;
$$;

create or replace function public.apply_reference_sync_checked(
  p_expected_user_id uuid,
  p_event_id text,
  p_aggregate_type text,
  p_operation text,
  p_payload jsonb
)
returns void
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if p_expected_user_id is null or p_expected_user_id is distinct from (select auth.uid()) then
    raise exception 'Authentication session changed' using errcode = '28000';
  end if;
  perform public.apply_reference_sync(
    p_event_id,
    p_aggregate_type,
    p_operation,
    p_payload
  );
end;
$$;

revoke all on function public.apply_invoice_sync_checked(uuid, text, jsonb, integer)
  from public, anon;
revoke all on function public.apply_reference_sync_checked(uuid, text, text, text, jsonb)
  from public, anon;
grant execute on function public.apply_invoice_sync_checked(uuid, text, jsonb, integer)
  to authenticated;
grant execute on function public.apply_reference_sync_checked(uuid, text, text, text, jsonb)
  to authenticated;
