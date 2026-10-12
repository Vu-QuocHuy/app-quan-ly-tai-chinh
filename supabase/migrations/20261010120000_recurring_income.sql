alter table public.planning_entries
  drop constraint planning_entries_kind_check;

alter table public.planning_entries
  add constraint planning_entries_kind_check check (
    deleted_at is not null or kind in ('bill', 'goal', 'income')
  );

alter function public.apply_plan_sync_checked(uuid, text, jsonb)
  rename to apply_plan_sync_checked_legacy;

revoke all on function public.apply_plan_sync_checked_legacy(uuid, text, jsonb)
  from public, anon, authenticated;

create function public.apply_plan_sync_checked(
  p_expected_user_id uuid,
  p_operation text,
  p_payload jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_id text;
  v_amount bigint;
  v_anchor date;
  v_next date;
begin
  if p_operation is distinct from 'upsert'
      or p_payload is null
      or p_payload ->> 'kind' is distinct from 'income' then
    perform public.apply_plan_sync_checked_legacy(
      p_expected_user_id,
      p_operation,
      p_payload
    );
    return;
  end if;

  if v_user_id is null or p_expected_user_id is distinct from v_user_id then
    raise exception 'Authentication session changed' using errcode = '28000';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
      or octet_length(p_payload::text) > 4096
      or jsonb_typeof(p_payload -> 'updatedAt') is distinct from 'string' then
    raise exception 'Income plan payload is invalid' using errcode = '22023';
  end if;

  v_id := p_payload ->> 'id';
  if v_id is null or char_length(trim(v_id)) not between 1 and 128
      or jsonb_typeof(p_payload -> 'title') is distinct from 'string'
      or char_length(trim(p_payload ->> 'title')) not between 1 and 120
      or jsonb_typeof(p_payload -> 'amountMinor') is distinct from 'number'
      or (p_payload ->> 'amountMinor') !~ '^[0-9]+$'
      or jsonb_typeof(p_payload -> 'categoryId') is distinct from 'string'
      or char_length(trim(p_payload ->> 'categoryId')) not between 1 and 128
      or jsonb_typeof(p_payload -> 'anchorDate') is distinct from 'string'
      or jsonb_typeof(p_payload -> 'nextDueDate') is distinct from 'string'
      or (p_payload ->> 'anchorDate') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      or (p_payload ->> 'nextDueDate') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    raise exception 'Recurring income is invalid' using errcode = '22023';
  end if;

  perform (p_payload ->> 'updatedAt')::timestamptz;
  v_amount := (p_payload ->> 'amountMinor')::bigint;
  v_anchor := (p_payload ->> 'anchorDate')::date;
  v_next := (p_payload ->> 'nextDueDate')::date;
  if v_amount not between 1 and 9007199254740991 or v_next < v_anchor then
    raise exception 'Recurring income amount or date is invalid' using errcode = '22023';
  end if;

  insert into public.planning_entries (
    user_id, id, kind, payload, updated_at, deleted_at
  ) values (
    v_user_id, v_id, 'income', p_payload - 'updatedAt', clock_timestamp(), null
  ) on conflict (user_id, id) do update set
    kind = excluded.kind,
    payload = excluded.payload,
    updated_at = clock_timestamp(),
    deleted_at = null;
end;
$$;

revoke all on function public.apply_plan_sync_checked(uuid, text, jsonb)
  from public, anon;
grant execute on function public.apply_plan_sync_checked(uuid, text, jsonb)
  to authenticated;
