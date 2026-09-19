create table public.ai_usage_buckets (
  user_id uuid not null references auth.users(id) on delete cascade,
  window_start timestamptz not null,
  request_count integer not null default 0 check (request_count >= 0),
  primary key (user_id, window_start)
);

alter table public.ai_usage_buckets enable row level security;

revoke all on table public.ai_usage_buckets from public, anon, authenticated;

create or replace function public.consume_ai_quota(p_limit integer)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_window_start timestamptz := date_trunc('minute', now());
  v_limit integer := least(greatest(coalesce(p_limit, 30), 1), 120);
  v_count integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  delete from public.ai_usage_buckets
    where user_id = v_user_id
      and window_start < v_window_start - interval '2 hours';
  insert into public.ai_usage_buckets (user_id, window_start, request_count)
    values (v_user_id, v_window_start, 1)
    on conflict (user_id, window_start) do update
      set request_count = public.ai_usage_buckets.request_count + 1
    returning request_count into v_count;
  return v_count <= v_limit;
end;
$$;

revoke all on function public.consume_ai_quota(integer) from public, anon;
grant execute on function public.consume_ai_quota(integer) to authenticated;
