create table if not exists public.app_feature_flags (
  environment text not null,
  key text not null,
  enabled boolean not null default false,
  rollout_percentage smallint not null default 100,
  updated_at timestamptz not null default now(),
  constraint app_feature_flags_pkey primary key (environment, key),
  constraint app_feature_flags_environment_check check (environment in ('dev', 'staging', 'production')),
  constraint app_feature_flags_key_check check (key in ('qr_scanner', 'online_ai', 'cloud_sync', 'external_rates')),
  constraint app_feature_flags_rollout_check check (rollout_percentage between 0 and 100)
);

alter table public.app_feature_flags enable row level security;

drop policy if exists "authenticated users can read feature flags" on public.app_feature_flags;
create policy "authenticated users can read feature flags"
  on public.app_feature_flags for select to authenticated
  using (true);

revoke all on table public.app_feature_flags from anon, authenticated;
grant select on table public.app_feature_flags to authenticated;
