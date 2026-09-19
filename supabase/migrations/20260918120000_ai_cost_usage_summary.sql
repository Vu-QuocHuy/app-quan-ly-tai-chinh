create or replace view public.ai_cost_usage_summary as
select
  period_type,
  period_start,
  count(*)::bigint as active_user_count,
  sum(consumed_units)::bigint as consumed_units
from public.ai_cost_usage
group by period_type, period_start;

revoke all on public.ai_cost_usage_summary from public, anon, authenticated;
grant select on public.ai_cost_usage_summary to service_role;
