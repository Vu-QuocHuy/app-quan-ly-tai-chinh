-- TV3 – AI optimization platform (N2 token metrics, N4 feature flags,
-- N3 client telemetry sink, N5 quota refund on provider failure).

-- ---------------------------------------------------------------------------
-- N2: token / payload / provider columns on ai_request_metrics
-- ---------------------------------------------------------------------------
alter table public.ai_request_metrics
  add column if not exists request_id text
    check (request_id is null or char_length(request_id) between 1 and 128),
  add column if not exists provider text
    check (provider is null or provider in ('gemini', '9router', 'groq', 'local', 'none')),
  add column if not exists input_tokens integer check (input_tokens is null or input_tokens >= 0),
  add column if not exists output_tokens integer check (output_tokens is null or output_tokens >= 0),
  add column if not exists thinking_tokens integer check (thinking_tokens is null or thinking_tokens >= 0),
  add column if not exists cached_tokens integer check (cached_tokens is null or cached_tokens >= 0),
  add column if not exists total_tokens integer check (total_tokens is null or total_tokens >= 0),
  add column if not exists payload_bytes integer check (payload_bytes is null or payload_bytes >= 0),
  add column if not exists llm_calls smallint not null default 0 check (llm_calls between 0 and 20),
  add column if not exists failover boolean not null default false,
  add column if not exists quota_refunded boolean not null default false,
  add column if not exists flag_set text
    check (flag_set is null or char_length(flag_set) between 1 and 400);

create index if not exists ai_request_metrics_flag_set_idx
  on public.ai_request_metrics (action, flag_set, created_at desc);

-- Validates the optional JSON details payload and inserts one metric row.
create or replace function public._insert_ai_request_metric(
  p_user_id uuid,
  p_action text,
  p_status_code integer,
  p_duration_ms integer,
  p_model text,
  p_error_code text,
  p_details jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_details jsonb := case when jsonb_typeof(p_details) = 'object' then p_details else '{}'::jsonb end;
  v_provider text := v_details ->> 'provider';
  v_flag_set text := nullif(left(trim(coalesce(v_details ->> 'flagSet', '')), 400), '');
  v_request_id text := nullif(left(trim(coalesce(v_details ->> 'requestId', '')), 128), '');
begin
  if p_action is null or char_length(trim(p_action)) not between 1 and 32 then
    return;
  end if;
  if p_status_code is null or p_status_code not between 100 and 599 then
    return;
  end if;
  if p_duration_ms is null or p_duration_ms not between 0 and 600000 then
    return;
  end if;
  if v_provider is not null and v_provider not in ('gemini', '9router', 'groq', 'local', 'none') then
    v_provider := null;
  end if;

  insert into public.ai_request_metrics (
    user_id, action, status_code, duration_ms, model, error_code,
    request_id, provider, input_tokens, output_tokens, thinking_tokens,
    cached_tokens, total_tokens, payload_bytes, llm_calls, failover,
    quota_refunded, flag_set
  )
  values (
    p_user_id,
    left(trim(p_action), 32),
    p_status_code,
    p_duration_ms,
    nullif(left(trim(coalesce(p_model, '')), 128), ''),
    nullif(left(trim(coalesce(p_error_code, '')), 64), ''),
    v_request_id,
    v_provider,
    public._ai_metric_int(v_details -> 'inputTokens'),
    public._ai_metric_int(v_details -> 'outputTokens'),
    public._ai_metric_int(v_details -> 'thinkingTokens'),
    public._ai_metric_int(v_details -> 'cachedTokens'),
    public._ai_metric_int(v_details -> 'totalTokens'),
    public._ai_metric_int(v_details -> 'payloadBytes'),
    least(coalesce(public._ai_metric_int(v_details -> 'llmCalls'), 0), 20),
    coalesce((v_details ->> 'failover')::boolean, false),
    coalesce((v_details ->> 'quotaRefunded')::boolean, false),
    v_flag_set
  );
end;
$$;

create or replace function public._ai_metric_int(p_value jsonb)
returns integer
language sql
immutable
set search_path = public, pg_temp
as $$
  select case
    when jsonb_typeof(p_value) = 'number'
      and (p_value #>> '{}')::numeric between 0 and 2000000000
      then floor((p_value #>> '{}')::numeric)::integer
    else null
  end;
$$;

revoke all on function public._ai_metric_int(jsonb) from public, anon, authenticated;
revoke all on function public._insert_ai_request_metric(uuid, text, integer, integer, text, text, jsonb)
  from public, anon, authenticated;

-- Replace the 5-argument RPC with a 6-argument one. The new argument has a
-- default, so callers still sending the old named arguments keep working.
drop function if exists public.record_ai_request_metric(text, integer, integer, text, text);

create function public.record_ai_request_metric(
  p_action text,
  p_status_code integer,
  p_duration_ms integer,
  p_model text default null,
  p_error_code text default null,
  p_details jsonb default null
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
  perform public._insert_ai_request_metric(
    auth.uid(), p_action, p_status_code, p_duration_ms, p_model, p_error_code, p_details
  );
end;
$$;

revoke all on function public.record_ai_request_metric(text, integer, integer, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.record_ai_request_metric(text, integer, integer, text, text, jsonb)
  to authenticated;

-- ai-worker runs with the service role, so it records against the job owner.
create function public.record_ai_worker_metric(
  p_job_id uuid,
  p_status_code integer,
  p_duration_ms integer,
  p_model text default null,
  p_error_code text default null,
  p_details jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid;
  v_request_id text;
begin
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Worker role required' using errcode = '42501';
  end if;
  select user_id, request_id into v_user_id, v_request_id
  from public.ai_extraction_jobs
  where id = p_job_id;
  if v_user_id is null then
    return;
  end if;
  perform public._insert_ai_request_metric(
    v_user_id, 'extract_job', p_status_code, p_duration_ms, p_model, p_error_code,
    coalesce(p_details, '{}'::jsonb) || jsonb_build_object('requestId', v_request_id)
  );
end;
$$;

revoke all on function public.record_ai_worker_metric(uuid, integer, integer, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.record_ai_worker_metric(uuid, integer, integer, text, text, jsonb)
  to service_role;

-- SLO views: existing columns keep their order, new columns are appended.
create or replace view public.ai_request_metrics_hourly as
select
  date_trunc('hour', created_at) as bucket,
  action,
  count(*)::bigint as request_count,
  count(*) filter (where status_code >= 400)::bigint as error_count,
  round(avg(duration_ms)::numeric, 2) as average_duration_ms,
  percentile_cont(0.95) within group (order by duration_ms) as p95_duration_ms,
  count(*) filter (where status_code = 429)::bigint as rate_limited_count,
  percentile_cont(0.5) within group (order by duration_ms) as p50_duration_ms,
  round(avg(total_tokens)::numeric, 1) as average_total_tokens,
  count(*) filter (where failover)::bigint as failover_count
from public.ai_request_metrics
group by date_trunc('hour', created_at), action;

revoke all on public.ai_request_metrics_hourly from public, anon, authenticated;

create or replace view public.ai_request_slo_daily as
select
  (created_at at time zone 'UTC')::date as report_day,
  action,
  count(*) as request_count,
  count(*) filter (where status_code >= 500) as server_error_count,
  round(
    (100.0 * count(*) filter (where status_code >= 500) / nullif(count(*), 0))::numeric,
    2
  ) as server_error_rate_percent,
  percentile_cont(0.95) within group (order by duration_ms) as p95_duration_ms,
  count(*) filter (where status_code between 400 and 499) as client_error_count,
  count(*) filter (where status_code = 429) as rate_limited_count,
  round(
    (100.0 * count(*) filter (where status_code = 429) / nullif(count(*), 0))::numeric,
    2
  ) as rate_limited_rate_percent,
  round(
    (100.0 * count(*) filter (where status_code < 400) / nullif(count(*), 0))::numeric,
    2
  ) as success_rate_percent,
  percentile_cont(0.5) within group (order by duration_ms) as p50_duration_ms,
  count(*) filter (where failover) as failover_count,
  count(*) filter (where failover and status_code < 400) as failover_success_count,
  count(*) filter (where quota_refunded) as quota_refund_count,
  coalesce(sum(total_tokens), 0) as total_tokens
from public.ai_request_metrics
group by report_day, action;

revoke all on public.ai_request_slo_daily from public, anon, authenticated;
grant select on public.ai_request_slo_daily to service_role;

-- Benchmark view for TV4: compare B0 (flag_set = 'none') against B1 runs.
create or replace view public.ai_request_benchmark as
select
  action,
  coalesce(flag_set, 'none') as flag_set,
  coalesce(provider, 'unknown') as provider,
  count(*) as request_count,
  count(*) filter (where status_code < 400) as success_count,
  count(*) filter (where status_code = 429) as rate_limited_count,
  count(*) filter (where failover) as failover_count,
  percentile_cont(0.5) within group (order by duration_ms) as p50_duration_ms,
  percentile_cont(0.95) within group (order by duration_ms) as p95_duration_ms,
  round(avg(input_tokens)::numeric, 1) as avg_input_tokens,
  round(avg(output_tokens)::numeric, 1) as avg_output_tokens,
  round(avg(thinking_tokens)::numeric, 1) as avg_thinking_tokens,
  round(avg(total_tokens)::numeric, 1) as avg_total_tokens,
  round(avg(payload_bytes)::numeric / 1024, 1) as avg_payload_kb,
  round(avg(llm_calls)::numeric, 2) as avg_llm_calls,
  min(created_at) as first_seen_at,
  max(created_at) as last_seen_at
from public.ai_request_metrics
group by action, coalesce(flag_set, 'none'), coalesce(provider, 'unknown');

revoke all on public.ai_request_benchmark from public, anon, authenticated;
grant select on public.ai_request_benchmark to service_role;

-- ---------------------------------------------------------------------------
-- N4: AI optimization feature flags (all OFF = baseline B0)
-- ---------------------------------------------------------------------------
alter table public.app_feature_flags
  drop constraint if exists app_feature_flags_key_check;

alter table public.app_feature_flags
  add constraint app_feature_flags_key_check
  check (key in (
    'online_ai', 'cloud_sync', 'external_rates',
    'ai.extract.thinking_low', 'ai.extract.image_1600',
    'ai.extract.precheck_dedup', 'ai.extract.validator',
    'ai.chat.local_router', 'ai.chat.merge_calls', 'ai.chat.prompt_v2',
    'ai.classify.local', 'ai.router.failover', 'ai.telemetry.upload'
  ));

insert into public.app_feature_flags (environment, key, enabled, rollout_percentage)
select environment, key, false, 100
from unnest(array['dev', 'staging', 'production']) as environment
cross join unnest(array[
  'ai.extract.thinking_low', 'ai.extract.image_1600',
  'ai.extract.precheck_dedup', 'ai.extract.validator',
  'ai.chat.local_router', 'ai.chat.merge_calls', 'ai.chat.prompt_v2',
  'ai.classify.local', 'ai.router.failover', 'ai.telemetry.upload'
]) as key
on conflict (environment, key) do nothing;

-- ---------------------------------------------------------------------------
-- N3: client-side AI telemetry sink (local answers, dedup hits, chat latency)
-- ---------------------------------------------------------------------------
create table if not exists public.ai_client_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  event text not null check (event ~ '^[a-z0-9_.]{1,64}$'),
  feature text not null check (feature ~ '^[a-z0-9_.]{1,32}$'),
  route text check (route is null or route ~ '^[a-z0-9_.]{1,32}$'),
  llm_calls smallint not null default 0 check (llm_calls between 0 and 20),
  duration_ms integer check (duration_ms is null or duration_ms between 0 and 600000),
  payload_bytes integer check (payload_bytes is null or payload_bytes between 0 and 50000000),
  flag_set text check (flag_set is null or char_length(flag_set) between 1 and 400),
  occurred_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists ai_client_events_created_idx
  on public.ai_client_events (created_at desc);
create index if not exists ai_client_events_feature_idx
  on public.ai_client_events (feature, event, created_at desc);

alter table public.ai_client_events enable row level security;
revoke all on table public.ai_client_events from public, anon, authenticated;
grant select on table public.ai_client_events to service_role;

-- Batch insert (max 100 rows per call, max 2000 rows per user per day).
create or replace function public.record_ai_client_events(p_events jsonb)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_today_count integer;
  v_inserted integer;
begin
  if v_user_id is null then
    return 0;
  end if;
  if jsonb_typeof(p_events) <> 'array' or jsonb_array_length(p_events) > 100 then
    raise exception 'Invalid telemetry batch' using errcode = '22023';
  end if;
  select count(*) into v_today_count
  from public.ai_client_events
  where user_id = v_user_id
    and created_at >= date_trunc('day', now());
  if v_today_count >= 2000 then
    return 0;
  end if;

  insert into public.ai_client_events (
    user_id, event, feature, route, llm_calls, duration_ms, payload_bytes, flag_set, occurred_at
  )
  select
    v_user_id,
    item ->> 'event',
    item ->> 'feature',
    nullif(item ->> 'route', ''),
    least(coalesce(public._ai_metric_int(item -> 'llmCalls'), 0), 20),
    least(public._ai_metric_int(item -> 'durationMs'), 600000),
    least(public._ai_metric_int(item -> 'payloadBytes'), 50000000),
    nullif(left(trim(coalesce(item ->> 'flagSet', '')), 400), ''),
    least(greatest(coalesce((item ->> 'occurredAt')::timestamptz, now()), now() - interval '7 days'), now())
  from jsonb_array_elements(p_events) as item
  where jsonb_typeof(item) = 'object'
    and coalesce(item ->> 'event', '') ~ '^[a-z0-9_.]{1,64}$'
    and coalesce(item ->> 'feature', '') ~ '^[a-z0-9_.]{1,32}$'
    and (item ->> 'route' is null or item ->> 'route' = '' or item ->> 'route' ~ '^[a-z0-9_.]{1,32}$')
  limit greatest(2000 - v_today_count, 0);
  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$$;

revoke all on function public.record_ai_client_events(jsonb) from public, anon, authenticated;
grant execute on function public.record_ai_client_events(jsonb) to authenticated;

create or replace view public.ai_client_benchmark as
select
  feature,
  event,
  coalesce(route, 'unknown') as route,
  coalesce(flag_set, 'none') as flag_set,
  count(*) as event_count,
  round(avg(llm_calls)::numeric, 2) as avg_llm_calls,
  percentile_cont(0.5) within group (order by duration_ms) as p50_duration_ms,
  percentile_cont(0.95) within group (order by duration_ms) as p95_duration_ms
from public.ai_client_events
group by feature, event, coalesce(route, 'unknown'), coalesce(flag_set, 'none');

revoke all on public.ai_client_benchmark from public, anon, authenticated;
grant select on public.ai_client_benchmark to service_role;

create or replace function public.cleanup_ai_client_events(p_retention_days integer default 30)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_deleted bigint;
  v_days integer := least(greatest(coalesce(p_retention_days, 30), 7), 90);
begin
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Worker role required' using errcode = '42501';
  end if;
  delete from public.ai_client_events
  where id in (
    select id from public.ai_client_events
    where created_at < now() - make_interval(days => v_days)
    order by created_at
    limit 5000
  );
  get diagnostics v_deleted = row_count;
  return coalesce(v_deleted, 0);
end;
$$;

revoke all on function public.cleanup_ai_client_events(integer) from public, anon, authenticated;
grant execute on function public.cleanup_ai_client_events(integer) to service_role;

-- ---------------------------------------------------------------------------
-- N5: refund quota when the AI provider (not the user) caused the failure.
-- Service role only: a user must never be able to refund their own quota.
-- ---------------------------------------------------------------------------
create or replace function public.refund_ai_quota(
  p_user_id uuid,
  p_cost_units integer
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cost_units integer := least(greatest(coalesce(p_cost_units, 1), 1), 100);
  v_usage_day date := (now() at time zone 'utc')::date;
  v_usage_month date := date_trunc('month', now() at time zone 'utc')::date;
begin
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Service role required' using errcode = '42501';
  end if;
  if p_user_id is null then
    return false;
  end if;

  update public.ai_cost_usage
  set consumed_units = greatest(consumed_units - v_cost_units, 0),
      updated_at = now()
  where user_id = p_user_id
    and (
      (period_type = 'day' and period_start = v_usage_day)
      or (period_type = 'month' and period_start = v_usage_month)
    );

  update public.ai_usage_daily
  set request_count = greatest(request_count - 1, 0)
  where user_id = p_user_id
    and usage_day = v_usage_day;

  return true;
end;
$$;

revoke all on function public.refund_ai_quota(uuid, integer) from public, anon, authenticated;
grant execute on function public.refund_ai_quota(uuid, integer) to service_role;
