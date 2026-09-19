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
  percentile_cont(0.95) within group (order by duration_ms) as p95_duration_ms
from public.ai_request_metrics
group by report_day, action;

revoke all on public.ai_request_slo_daily from public, anon, authenticated;
grant select on public.ai_request_slo_daily to service_role;
