create table if not exists public.ai_usage_daily (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_day date not null,
  request_count integer not null default 0 check (request_count >= 0),
  primary key (user_id, usage_day)
);

alter table public.ai_usage_daily enable row level security;

revoke all on table public.ai_usage_daily from public, anon, authenticated;

drop function if exists public.consume_ai_quota(integer);

create or replace function public.consume_ai_quota(
  p_limit integer,
  p_daily_limit integer default 500
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_window_start timestamptz := date_trunc('minute', now());
  v_usage_day date := (now() at time zone 'utc')::date;
  v_limit integer := least(greatest(coalesce(p_limit, 30), 1), 120);
  v_daily_limit integer := least(greatest(coalesce(p_daily_limit, 500), 1), 5000);
  v_minute_count integer;
  v_daily_count integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  delete from public.ai_usage_buckets
    where user_id = v_user_id
      and window_start < v_window_start - interval '2 hours';
  delete from public.ai_usage_daily
    where user_id = v_user_id
      and usage_day < v_usage_day - 7;
  insert into public.ai_usage_buckets (user_id, window_start, request_count)
    values (v_user_id, v_window_start, 1)
    on conflict (user_id, window_start) do update
      set request_count = public.ai_usage_buckets.request_count + 1
    returning request_count into v_minute_count;
  insert into public.ai_usage_daily (user_id, usage_day, request_count)
    values (v_user_id, v_usage_day, 1)
    on conflict (user_id, usage_day) do update
      set request_count = public.ai_usage_daily.request_count + 1
    returning request_count into v_daily_count;
  return v_minute_count <= v_limit and v_daily_count <= v_daily_limit;
end;
$$;

revoke all on function public.consume_ai_quota(integer, integer) from public, anon;
grant execute on function public.consume_ai_quota(integer, integer) to authenticated;
