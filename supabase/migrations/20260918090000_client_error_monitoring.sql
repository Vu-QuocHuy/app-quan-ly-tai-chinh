create table public.client_error_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  source text not null,
  error_type text not null,
  message text not null,
  stack_trace text,
  fatal boolean not null default true,
  created_at timestamptz not null default now(),
  constraint client_error_events_source_check check (
    char_length(source) between 1 and 64 and source ~ '^[A-Za-z0-9_.-]+$'
  ),
  constraint client_error_events_type_check check (
    char_length(error_type) between 1 and 64 and error_type ~ '^[A-Za-z0-9_.-]+$'
  ),
  constraint client_error_events_message_check check (
    char_length(message) between 1 and 240 and message !~ '[[:cntrl:]]'
  ),
  constraint client_error_events_stack_check check (
    stack_trace is null or (char_length(stack_trace) between 1 and 4000 and stack_trace !~ '[[:cntrl:]]')
  )
);

create index client_error_events_created_idx
  on public.client_error_events (created_at desc);
create index client_error_events_user_created_idx
  on public.client_error_events (user_id, created_at desc);

create table public.client_error_rate_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null default now(),
  event_count integer not null default 0 check (event_count >= 0)
);

alter table public.client_error_events enable row level security;
alter table public.client_error_rate_limits enable row level security;
revoke all on table public.client_error_events from public, anon, authenticated;
revoke all on table public.client_error_rate_limits from public, anon, authenticated;
grant select on table public.client_error_events to service_role;

create or replace function public.record_client_error(
  p_source text,
  p_error_type text,
  p_message text,
  p_stack_trace text default null,
  p_fatal boolean default true
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_window_started_at timestamptz;
  v_event_count integer;
begin
  if v_user_id is null then
    return false;
  end if;
  if p_source is null or char_length(p_source) not between 1 and 64 or p_source !~ '^[A-Za-z0-9_.-]+$' then
    raise exception 'Invalid error source' using errcode = '22023';
  end if;
  if p_error_type is null or char_length(p_error_type) not between 1 and 64 or p_error_type !~ '^[A-Za-z0-9_.-]+$' then
    raise exception 'Invalid error type' using errcode = '22023';
  end if;
  if p_message is null or char_length(p_message) not between 1 and 240 or p_message ~ '[[:cntrl:]]' then
    raise exception 'Invalid error message' using errcode = '22023';
  end if;
  if p_stack_trace is not null and (char_length(p_stack_trace) not between 1 and 4000 or p_stack_trace ~ '[[:cntrl:]]') then
    raise exception 'Invalid error stack' using errcode = '22023';
  end if;

  insert into public.client_error_rate_limits (user_id)
    values (v_user_id)
    on conflict (user_id) do nothing;
  select limits.window_started_at, limits.event_count
    into v_window_started_at, v_event_count
    from public.client_error_rate_limits as limits
    where limits.user_id = v_user_id
    for update;
  if v_window_started_at <= now() - interval '1 minute' then
    update public.client_error_rate_limits
      set window_started_at = now(), event_count = 1
      where user_id = v_user_id;
  elsif v_event_count >= 20 then
    return false;
  else
    update public.client_error_rate_limits
      set event_count = event_count + 1
      where user_id = v_user_id;
  end if;

  insert into public.client_error_events (
    user_id, source, error_type, message, stack_trace, fatal
  ) values (
    v_user_id, p_source, p_error_type, p_message, p_stack_trace, coalesce(p_fatal, true)
  );
  return true;
end;
$$;

create or replace function public.cleanup_client_error_events(
  p_retention_days integer default 30
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_retention_days integer := least(greatest(coalesce(p_retention_days, 30), 7), 90);
  v_deleted integer;
begin
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Worker role required' using errcode = '42501';
  end if;
  with expired as (
    select events.id
    from public.client_error_events as events
    where events.created_at <= now() - make_interval(days => v_retention_days)
    order by events.created_at, events.id
    limit 5000
    for update skip locked
  )
  delete from public.client_error_events as events
  using expired
  where events.id = expired.id;
  get diagnostics v_deleted = row_count;
  delete from public.client_error_rate_limits
  where window_started_at <= now() - interval '2 days';
  return v_deleted;
end;
$$;

revoke all on function public.record_client_error(text, text, text, text, boolean)
  from public, anon;
revoke all on function public.cleanup_client_error_events(integer)
  from public, anon, authenticated;
grant execute on function public.record_client_error(text, text, text, text, boolean)
  to authenticated;
grant execute on function public.cleanup_client_error_events(integer)
  to service_role;
