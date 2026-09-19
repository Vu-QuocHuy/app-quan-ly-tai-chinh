create or replace view public.client_error_events_daily as
select
  date_trunc('day', events.created_at) as day,
  events.source,
  events.error_type,
  events.fatal,
  count(*)::bigint as event_count,
  max(events.created_at) as last_seen_at
from public.client_error_events as events
group by
  date_trunc('day', events.created_at),
  events.source,
  events.error_type,
  events.fatal;

revoke all on public.client_error_events_daily from public, anon, authenticated;
grant select on public.client_error_events_daily to service_role;
