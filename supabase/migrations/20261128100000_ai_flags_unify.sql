-- Unify the AI optimisation flag catalogue after the TV2 (20261107100000) and
-- TV3 (20261112100000) migrations.
--
-- Problems this fixes:
--   1. TV2 inserted ai.chat.skip_command / prefetch_facts / compact_prompt;
--      TV3's catalogue replaced them with ai.chat.merge_calls / prompt_v2.
--   2. TV2 inserted ai.chat.local_router and ai.classify.local as ENABLED;
--      TV3 re-inserted them with `on conflict do nothing`, so they stayed ON
--      and the default configuration was no longer the B0 baseline.
--   3. A fixed key whitelist breaks whenever two members add flags in
--      parallel, so the pattern constraint is the single source of truth.
--
-- Idempotent: safe to run on a database that has applied any subset of the
-- earlier migrations. Final state: exactly 10 `ai.*` flags per environment,
-- all OFF (= B0).

alter table public.app_feature_flags
  drop constraint if exists app_feature_flags_key_check;

delete from public.app_feature_flags
where key in (
  'ai.chat.skip_command',
  'ai.chat.prefetch_facts',
  'ai.chat.compact_prompt'
);

alter table public.app_feature_flags
  add constraint app_feature_flags_key_check
  check (key ~ '^[a-z][a-z0-9_.]{1,63}$');

insert into public.app_feature_flags (environment, key, enabled, rollout_percentage)
select environment, key, false, 100
from unnest(array['dev', 'staging', 'production']) as environment
cross join unnest(array[
  'ai.extract.thinking_low',
  'ai.extract.image_1600',
  'ai.extract.precheck_dedup',
  'ai.extract.validator',
  'ai.chat.local_router',
  'ai.chat.merge_calls',
  'ai.chat.prompt_v2',
  'ai.classify.local',
  'ai.router.failover',
  'ai.telemetry.upload'
]) as key
on conflict (environment, key) do update
  set enabled = false,
      updated_at = now();
