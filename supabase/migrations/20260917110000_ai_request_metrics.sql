create table public.ai_request_metrics (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users(id) on delete cascade,
  action text not null check (char_length(action) between 1 and 32),
  status_code integer not null check (status_code between 100 and 599),
  duration_ms integer not null check (duration_ms between 0 and 600000),
  model text check (model is null or char_length(model) between 1 and 128),
  error_code text check (error_code is null or char_length(error_code) between 1 and 64),
  created_at timestamptz not null default now()
);

create index ai_request_metrics_created_at_idx
  on public.ai_request_metrics (created_at desc);
create index ai_request_metrics_action_created_at_idx
  on public.ai_request_metrics (action, created_at desc);

alter table public.ai_request_metrics enable row level security;
revoke all on public.ai_request_metrics from public, anon, authenticated;

create or replace function public.record_ai_request_metric(
  p_action text,
  p_status_code integer,
  p_duration_ms integer,
  p_model text default null,
  p_error_code text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    return;
  end if;

  if p_action is null or char_length(trim(p_action)) not between 1 and 32 then
    return;
  end if;
  if p_status_code is null or p_status_code not between 100 and 599 then
    return;
  end if;
  if p_duration_ms is null or p_duration_ms not between 0 and 600000 then
    return;
  end if;

  insert into public.ai_request_metrics (
    user_id,
    action,
    status_code,
    duration_ms,
    model,
    error_code
  )
  values (
    auth.uid(),
    left(trim(p_action), 32),
    p_status_code,
    p_duration_ms,
    nullif(left(trim(coalesce(p_model, '')), 128), ''),
    nullif(left(trim(coalesce(p_error_code, '')), 64), '')
  );

  if mod(extract(epoch from clock_timestamp())::bigint, 100) = 0 then
    delete from public.ai_request_metrics
    where created_at < now() - interval '30 days';
  end if;
end;
$$;

revoke all on function public.record_ai_request_metric(text, integer, integer, text, text)
  from public, anon, authenticated;
grant execute on function public.record_ai_request_metric(text, integer, integer, text, text)
  to authenticated;
