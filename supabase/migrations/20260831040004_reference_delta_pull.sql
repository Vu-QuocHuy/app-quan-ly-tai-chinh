-- Durable change log for reference data. It provides cursor-based pull,
-- including deletes, and deduplicates retried outbox events by event id.

create table public.reference_sync_events (
  sequence_id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  event_id text not null,
  aggregate_type text not null check (
    aggregate_type in ('category', 'budget', 'merchant_rule')
  ),
  operation text not null check (operation in ('upsert', 'delete')),
  revision integer not null default 1 check (revision > 0),
  payload jsonb not null,
  changed_at timestamptz not null default now(),
  unique (user_id, event_id)
);

create index reference_sync_events_cursor_idx
  on public.reference_sync_events (
    user_id,
    aggregate_type,
    changed_at,
    sequence_id
  );

alter table public.reference_sync_events enable row level security;
revoke all on table public.reference_sync_events from public, anon, authenticated;

drop function if exists public.apply_reference_sync(text, text, jsonb);

create or replace function public.apply_reference_sync(
  p_event_id text,
  p_aggregate_type text,
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
  v_id text := nullif(p_payload ->> 'id', '');
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if nullif(p_event_id, '') is null then
    raise exception 'Event id is required' using errcode = '22023';
  end if;
  if v_id is null then
    raise exception 'Reference id is required' using errcode = '22023';
  end if;
  if p_operation not in ('upsert', 'delete') then
    raise exception 'Unsupported operation: %', p_operation
      using errcode = '22023';
  end if;
  if p_aggregate_type not in ('category', 'budget', 'merchant_rule') then
    raise exception 'Unsupported aggregate type: %', p_aggregate_type
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.reference_sync_events
    where user_id = v_user_id and event_id = p_event_id
  ) then
    return;
  end if;

  if p_aggregate_type = 'category' then
    if p_operation = 'delete' then
      delete from public.categories
      where user_id = v_user_id and id = v_id and is_system = false;
    else
      insert into public.categories (
        user_id, id, name, icon_name, color_value, is_system, updated_at
      ) values (
        v_user_id,
        v_id,
        coalesce(p_payload ->> 'name', ''),
        coalesce(p_payload ->> 'iconName', 'category'),
        coalesce((p_payload ->> 'colorValue')::bigint, 0),
        coalesce((p_payload ->> 'isSystem')::boolean, false),
        now()
      )
      on conflict (user_id, id) do update set
        name = excluded.name,
        icon_name = excluded.icon_name,
        color_value = excluded.color_value,
        is_system = excluded.is_system,
        updated_at = now();
    end if;
  elsif p_aggregate_type = 'budget' then
    if p_operation = 'delete' then
      delete from public.budgets
      where user_id = v_user_id and id = v_id;
    else
      insert into public.budgets (
        user_id, id, month_key, category_id, limit_minor, updated_at
      ) values (
        v_user_id,
        v_id,
        p_payload ->> 'monthKey',
        p_payload ->> 'categoryId',
        coalesce((p_payload ->> 'limitMinor')::bigint, 0),
        now()
      )
      on conflict (user_id, id) do update set
        month_key = excluded.month_key,
        category_id = excluded.category_id,
        limit_minor = excluded.limit_minor,
        updated_at = now();
    end if;
  else
    if p_operation = 'delete' then
      delete from public.merchant_rules
      where user_id = v_user_id and id = v_id;
    else
      insert into public.merchant_rules (
        user_id, id, normalized_merchant, category_id, updated_at
      ) values (
        v_user_id,
        v_id,
        coalesce(p_payload ->> 'normalizedMerchant', v_id),
        p_payload ->> 'categoryId',
        now()
      )
      on conflict (user_id, id) do update set
        normalized_merchant = excluded.normalized_merchant,
        category_id = excluded.category_id,
        updated_at = now();
    end if;
  end if;

  insert into public.reference_sync_events (
    user_id, event_id, aggregate_type, operation, revision, payload
  ) values (
    v_user_id, p_event_id, p_aggregate_type, p_operation, 1, p_payload
  );
end;
$$;

revoke all on function public.apply_reference_sync(text, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.apply_reference_sync(text, text, text, jsonb)
  to authenticated;

create or replace function public.pull_reference_changes(
  p_aggregate_type text,
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
    sequence_id::text,
    reference_sync_events.aggregate_type,
    reference_sync_events.operation,
    changed_at,
    reference_sync_events.revision,
    reference_sync_events.payload
  from public.reference_sync_events
  where user_id = (select auth.uid())
    and reference_sync_events.aggregate_type = p_aggregate_type
    and (
      p_since is null
      or changed_at > p_since
      or (
        changed_at = p_since
        and sequence_id > coalesce(nullif(p_after_id, '')::bigint, 0)
      )
    )
  order by changed_at asc, sequence_id asc
  limit least(greatest(coalesce(p_limit, 50), 1), 200);
$$;

revoke all on function public.pull_reference_changes(text, timestamptz, text, integer)
  from public, anon, authenticated;
grant execute on function public.pull_reference_changes(text, timestamptz, text, integer)
  to authenticated;
