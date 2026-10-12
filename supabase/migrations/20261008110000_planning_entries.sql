create table public.planning_entries (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  kind text,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, id),
  constraint planning_entries_kind_check check (
    deleted_at is not null or kind in ('bill', 'goal')
  )
);

create index planning_entries_cursor_idx
  on public.planning_entries (user_id, updated_at, id);

alter table public.planning_entries enable row level security;
revoke all on public.planning_entries from public, anon, authenticated;

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
  v_kind text;
  v_amount bigint;
  v_saved bigint;
begin
  if v_user_id is null or p_expected_user_id is distinct from v_user_id then
    raise exception 'Authentication session changed' using errcode = '28000';
  end if;
  if p_operation is null or p_operation not in ('upsert', 'delete')
      or p_payload is null or jsonb_typeof(p_payload) <> 'object'
      or octet_length(p_payload::text) > 4096 then
    raise exception 'Plan payload is invalid' using errcode = '22023';
  end if;
  v_id := p_payload ->> 'id';
  if v_id is null or char_length(trim(v_id)) not between 1 and 128 then
    raise exception 'Plan id is invalid' using errcode = '22023';
  end if;

  if p_operation = 'delete' then
    insert into public.planning_entries (
      user_id, id, kind, payload, updated_at, deleted_at
    ) values (
      v_user_id, v_id, null, '{}'::jsonb, clock_timestamp(), clock_timestamp()
    ) on conflict (user_id, id) do update set
      payload = '{}'::jsonb,
      updated_at = clock_timestamp(),
      deleted_at = clock_timestamp();
    return;
  end if;

  v_kind := p_payload ->> 'kind';
  if v_kind is null or v_kind not in ('bill', 'goal')
      or jsonb_typeof(p_payload -> 'updatedAt') is distinct from 'string' then
    raise exception 'Plan kind or timestamp is invalid' using errcode = '22023';
  end if;
  perform (p_payload ->> 'updatedAt')::timestamptz;
  if v_kind = 'bill' then
    if jsonb_typeof(p_payload -> 'title') is distinct from 'string'
        or char_length(trim(p_payload ->> 'title')) not between 1 and 120
        or jsonb_typeof(p_payload -> 'amountMinor') is distinct from 'number'
        or (p_payload ->> 'amountMinor') !~ '^[0-9]+$'
        or (p_payload ->> 'frequency') is null
        or (p_payload ->> 'frequency') not in ('weekly', 'monthly', 'yearly')
        or jsonb_typeof(p_payload -> 'anchorDate') is distinct from 'string'
        or jsonb_typeof(p_payload -> 'nextDueDate') is distinct from 'string'
        or (p_payload ->> 'anchorDate') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        or (p_payload ->> 'nextDueDate') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        or ((p_payload -> 'categoryId') is not null
            and jsonb_typeof(p_payload -> 'categoryId') <> 'null'
            and (jsonb_typeof(p_payload -> 'categoryId') <> 'string'
                or char_length(p_payload ->> 'categoryId') not between 1 and 128)) then
      raise exception 'Recurring bill is invalid' using errcode = '22023';
    end if;
    v_amount := (p_payload ->> 'amountMinor')::bigint;
    if v_amount not between 1 and 9007199254740991
        or (p_payload ->> 'nextDueDate')::date < (p_payload ->> 'anchorDate')::date then
      raise exception 'Recurring bill amount or date is invalid' using errcode = '22023';
    end if;
  else
    if jsonb_typeof(p_payload -> 'name') is distinct from 'string'
        or char_length(trim(p_payload ->> 'name')) not between 1 and 120
        or jsonb_typeof(p_payload -> 'targetMinor') is distinct from 'number'
        or (p_payload ->> 'targetMinor') !~ '^[0-9]+$'
        or jsonb_typeof(p_payload -> 'savedMinor') is distinct from 'number'
        or (p_payload ->> 'savedMinor') !~ '^[0-9]+$'
        or jsonb_typeof(p_payload -> 'targetDate') is distinct from 'string'
        or (p_payload ->> 'targetDate') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      raise exception 'Savings goal is invalid' using errcode = '22023';
    end if;
    v_amount := (p_payload ->> 'targetMinor')::bigint;
    v_saved := (p_payload ->> 'savedMinor')::bigint;
    if v_amount not between 1 and 9007199254740991
        or v_saved not between 0 and 9007199254740991 then
      raise exception 'Savings goal amounts are invalid' using errcode = '22023';
    end if;
    perform (p_payload ->> 'targetDate')::date;
  end if;

  insert into public.planning_entries (
    user_id, id, kind, payload, updated_at, deleted_at
  ) values (
    v_user_id, v_id, v_kind, p_payload - 'updatedAt', clock_timestamp(), null
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

create function public.pull_plan_changes(
  p_since timestamptz default null,
  p_after_id text default null,
  p_limit integer default 50
)
returns table (
  id text,
  aggregate_type text,
  operation text,
  updated_at timestamptz,
  revision integer,
  payload jsonb
)
language sql
security definer
set search_path = ''
as $$
  select
    planning_entries.id,
    'plan'::text,
    case when deleted_at is null then 'upsert' else 'delete' end,
    planning_entries.updated_at,
    1,
    case when deleted_at is null then
      planning_entries.payload || jsonb_build_object(
        'id', planning_entries.id,
        'kind', planning_entries.kind,
        'updatedAt', planning_entries.updated_at
      )
    else jsonb_build_object('id', planning_entries.id) end
  from public.planning_entries
  where user_id = (select auth.uid())
    and (
      p_since is null
      or planning_entries.updated_at > p_since
      or (planning_entries.updated_at = p_since
          and planning_entries.id > coalesce(p_after_id, ''))
    )
  order by planning_entries.updated_at, planning_entries.id
  limit least(greatest(coalesce(p_limit, 50), 1), 200);
$$;

revoke all on function public.pull_plan_changes(timestamptz, text, integer)
  from public, anon;
grant execute on function public.pull_plan_changes(timestamptz, text, integer)
  to authenticated;
