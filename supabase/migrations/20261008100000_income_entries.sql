create table public.income_entries (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  amount_minor bigint not null default 0,
  received_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, id),
  constraint income_entries_amount_check check (
    (deleted_at is null and amount_minor between 1 and 9007199254740991)
    or deleted_at is not null
  )
);

create index income_entries_cursor_idx
  on public.income_entries (user_id, updated_at, id);

alter table public.income_entries enable row level security;
revoke all on public.income_entries from public, anon, authenticated;

create function public.apply_income_sync_checked(
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
  v_received_at timestamptz;
begin
  if v_user_id is null or p_expected_user_id is distinct from v_user_id then
    raise exception 'Authentication session changed' using errcode = '28000';
  end if;
  if p_operation is null or p_operation not in ('upsert', 'delete') or p_payload is null
      or jsonb_typeof(p_payload) <> 'object'
      or octet_length(p_payload::text) > 4096 then
    raise exception 'Income payload is invalid' using errcode = '22023';
  end if;
  v_id := p_payload ->> 'id';
  if v_id is null or char_length(trim(v_id)) not between 1 and 128 then
    raise exception 'Income id is invalid' using errcode = '22023';
  end if;

  if p_operation = 'delete' then
    insert into public.income_entries (
      user_id, id, amount_minor, received_at, updated_at, deleted_at
    ) values (
      v_user_id, v_id, 0, now(), clock_timestamp(), clock_timestamp()
    ) on conflict (user_id, id) do update set
      updated_at = clock_timestamp(),
      deleted_at = clock_timestamp();
    return;
  end if;

  if jsonb_typeof(p_payload -> 'amountMinor') <> 'number'
      or (p_payload ->> 'amountMinor') !~ '^[0-9]+$'
      or jsonb_typeof(p_payload -> 'receivedAt') <> 'string' then
    raise exception 'Income amount or date is invalid' using errcode = '22023';
  end if;
  v_amount := (p_payload ->> 'amountMinor')::bigint;
  v_received_at := (p_payload ->> 'receivedAt')::timestamptz;
  if v_amount not between 1 and 9007199254740991 then
    raise exception 'Income amount is invalid' using errcode = '22023';
  end if;
  insert into public.income_entries (
    user_id, id, amount_minor, received_at, updated_at, deleted_at
  ) values (
    v_user_id, v_id, v_amount, v_received_at, clock_timestamp(), null
  ) on conflict (user_id, id) do update set
    amount_minor = excluded.amount_minor,
    received_at = excluded.received_at,
    updated_at = clock_timestamp(),
    deleted_at = null;
end;
$$;

revoke all on function public.apply_income_sync_checked(uuid, text, jsonb)
  from public, anon;
grant execute on function public.apply_income_sync_checked(uuid, text, jsonb)
  to authenticated;

create function public.pull_income_changes(
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
    income_entries.id,
    'income'::text,
    case when deleted_at is null then 'upsert' else 'delete' end,
    income_entries.updated_at,
    1,
    case when deleted_at is null then jsonb_build_object(
      'id', income_entries.id,
      'amountMinor', amount_minor,
      'receivedAt', received_at,
      'updatedAt', income_entries.updated_at
    ) else jsonb_build_object('id', income_entries.id) end
  from public.income_entries
  where user_id = (select auth.uid())
    and (
      p_since is null
      or income_entries.updated_at > p_since
      or (income_entries.updated_at = p_since
          and income_entries.id > coalesce(p_after_id, ''))
    )
  order by income_entries.updated_at, income_entries.id
  limit least(greatest(coalesce(p_limit, 50), 1), 200);
$$;

revoke all on function public.pull_income_changes(timestamptz, text, integer)
  from public, anon;
grant execute on function public.pull_income_changes(timestamptz, text, integer)
  to authenticated;
