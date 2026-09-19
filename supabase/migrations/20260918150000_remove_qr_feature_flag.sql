-- QR is no longer part of the product scope. Keep the historical migration
-- immutable and remove the flag from the live schema in a follow-up migration.
delete from public.app_feature_flags where key = 'qr_scanner';

alter table public.app_feature_flags
  drop constraint if exists app_feature_flags_key_check;

alter table public.app_feature_flags
  add constraint app_feature_flags_key_check
  check (key in ('online_ai', 'cloud_sync', 'external_rates'));
