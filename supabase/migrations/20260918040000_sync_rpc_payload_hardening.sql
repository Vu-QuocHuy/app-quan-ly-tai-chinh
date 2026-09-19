create or replace function public.apply_invoice_sync_checked(
  p_expected_user_id uuid,
  p_operation text,
  p_payload jsonb,
  p_revision integer
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_invoice_id text;
  v_lines jsonb;
  v_evidence jsonb;
  v_tags jsonb;
begin
  if p_expected_user_id is null or p_expected_user_id is distinct from (select auth.uid()) then
    raise exception 'Authentication session changed' using errcode = '28000';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Sync payload must be an object' using errcode = '22023';
  end if;
  if octet_length(p_payload::text) > 1048576 then
    raise exception 'Sync payload is too large' using errcode = '22023';
  end if;
  if p_operation is null or p_operation not in ('upsert', 'delete') then
    raise exception 'Unsupported operation' using errcode = '22023';
  end if;
  if p_revision is null or p_revision < 1 then
    raise exception 'Revision must be positive' using errcode = '22023';
  end if;

  v_invoice_id := nullif(p_payload ->> 'id', '');
  if v_invoice_id is null or char_length(v_invoice_id) > 128 then
    raise exception 'Invoice id is invalid' using errcode = '22023';
  end if;
  if p_operation = 'delete' then
    perform public.apply_invoice_sync(p_operation, p_payload, p_revision);
    return;
  end if;

  v_lines := coalesce(p_payload -> 'lines', '[]'::jsonb);
  v_evidence := coalesce(p_payload -> 'evidence', '[]'::jsonb);
  v_tags := coalesce(p_payload -> 'tags', '[]'::jsonb);
  if jsonb_typeof(v_lines) <> 'array' then
    raise exception 'Invoice lines are invalid' using errcode = '22023';
  end if;
  if jsonb_array_length(v_lines) > 200 then
    raise exception 'Invoice lines are invalid' using errcode = '22023';
  end if;
  if jsonb_typeof(v_evidence) <> 'array' then
    raise exception 'Invoice evidence is invalid' using errcode = '22023';
  end if;
  if jsonb_array_length(v_evidence) > 200 then
    raise exception 'Invoice evidence is invalid' using errcode = '22023';
  end if;
  if jsonb_typeof(v_tags) <> 'array' then
    raise exception 'Invoice tags are invalid' using errcode = '22023';
  end if;
  if jsonb_array_length(v_tags) > 100 then
    raise exception 'Invoice tags are invalid' using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(v_lines) as entries(value)
    where jsonb_typeof(entries.value) <> 'object'
      or nullif(entries.value ->> 'id', '') is null
      or char_length(entries.value ->> 'id') > 128
  ) then
    raise exception 'Invoice line entry is invalid' using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(v_evidence) as entries(value)
    where jsonb_typeof(entries.value) <> 'object'
      or nullif(entries.value ->> 'id', '') is null
      or char_length(entries.value ->> 'id') > 128
  ) then
    raise exception 'Invoice evidence entry is invalid' using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(v_tags) as entries(value)
    where jsonb_typeof(entries.value) <> 'string'
      or char_length(entries.value #>> '{}') > 128
  ) then
    raise exception 'Invoice tag entry is invalid' using errcode = '22023';
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
security definer
set search_path = public, pg_temp
as $$
declare
  v_id text;
begin
  if p_expected_user_id is null or p_expected_user_id is distinct from (select auth.uid()) then
    raise exception 'Authentication session changed' using errcode = '28000';
  end if;
  if p_event_id is null or char_length(trim(p_event_id)) not between 1 and 128 then
    raise exception 'Event id is invalid' using errcode = '22023';
  end if;
  if p_aggregate_type is null or p_aggregate_type not in ('category', 'budget', 'merchant_rule') then
    raise exception 'Unsupported aggregate type' using errcode = '22023';
  end if;
  if p_operation is null or p_operation not in ('upsert', 'delete') then
    raise exception 'Unsupported operation' using errcode = '22023';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Reference payload must be an object' using errcode = '22023';
  end if;
  if octet_length(p_payload::text) > 262144 then
    raise exception 'Reference payload is too large' using errcode = '22023';
  end if;
  v_id := nullif(p_payload ->> 'id', '');
  if v_id is null or char_length(v_id) > 128 then
    raise exception 'Reference id is invalid' using errcode = '22023';
  end if;

  perform public.apply_reference_sync(
    trim(p_event_id),
    p_aggregate_type,
    p_operation,
    p_payload
  );
end;
$$;

revoke all on function public.apply_invoice_sync(text, jsonb, integer)
  from public, anon, authenticated;
revoke all on function public.apply_reference_sync(text, text, text, jsonb)
  from public, anon, authenticated;
revoke all on function public.apply_invoice_sync_checked(uuid, text, jsonb, integer)
  from public, anon;
revoke all on function public.apply_reference_sync_checked(uuid, text, text, text, jsonb)
  from public, anon;
grant execute on function public.apply_invoice_sync_checked(uuid, text, jsonb, integer)
  to authenticated;
grant execute on function public.apply_reference_sync_checked(uuid, text, text, text, jsonb)
  to authenticated;
