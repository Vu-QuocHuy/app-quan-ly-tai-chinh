-- Private encrypted backup artifacts. The first path segment is always auth.uid().
insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
) values (
  'invoice-backups',
  'invoice-backups',
  false,
  52428800,
  array['application/octet-stream']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy invoice_backups_owner_select
  on storage.objects for select to authenticated
  using (
    bucket_id = 'invoice-backups'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy invoice_backups_owner_insert
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'invoice-backups'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy invoice_backups_owner_delete
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'invoice-backups'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
