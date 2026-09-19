create or replace function public.set_invoice_sync_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

revoke all on function public.set_invoice_sync_updated_at() from public, anon, authenticated;

drop trigger if exists invoices_server_updated_at on public.invoices;
create trigger invoices_server_updated_at
  before insert or update on public.invoices
  for each row execute procedure public.set_invoice_sync_updated_at();
