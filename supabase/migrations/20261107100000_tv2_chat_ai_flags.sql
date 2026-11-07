-- TV2 (chatbot / classify) optimisation flags used for the B0/B1 benchmark.
-- B0 baseline: set enabled = false for the five ai.chat.* / ai.classify.* rows.
-- B1 optimised: set enabled = true.
--
-- The fixed key whitelist forced every new flag to rewrite the constraint,
-- which collides when several members add flags in parallel. Allow any
-- lower-case dotted/underscored key instead; the client ignores unknown keys.
alter table public.app_feature_flags
  drop constraint if exists app_feature_flags_key_check;

alter table public.app_feature_flags
  add constraint app_feature_flags_key_check
  check (key ~ '^[a-z][a-z0-9_.]{1,63}$');

insert into public.app_feature_flags (environment, key, enabled, rollout_percentage)
select environment, key, true, 100
from (values ('dev'), ('staging'), ('production')) as environments(environment)
cross join (values
  ('ai.chat.local_router'),
  ('ai.chat.skip_command'),
  ('ai.chat.prefetch_facts'),
  ('ai.chat.compact_prompt'),
  ('ai.classify.local')
) as flags(key)
on conflict (environment, key) do nothing;
