create view public.ai_request_metrics_hourly as
select
  date_trunc('hour', created_at) as bucket,
  action,
  count(*)::bigint as request_count,
  count(*) filter (where status_code >= 400)::bigint as error_count,
  round(avg(duration_ms)::numeric, 2) as average_duration_ms,
  percentile_cont(0.95) within group (order by duration_ms) as p95_duration_ms
from public.ai_request_metrics
group by date_trunc('hour', created_at), action;

revoke all on public.ai_request_metrics_hourly from public, anon, authenticated;
