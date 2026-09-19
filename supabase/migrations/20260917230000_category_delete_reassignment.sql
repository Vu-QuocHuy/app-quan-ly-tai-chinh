create or replace function public.reassign_deleted_category()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if old.is_system then
    return old;
  end if;

  update public.invoices
  set category_id = 'other'
  where user_id = old.user_id and category_id = old.id;

  update public.invoice_lines
  set category_id = 'other'
  where user_id = old.user_id and category_id = old.id;

  return old;
end;
$$;

revoke all on function public.reassign_deleted_category() from public, anon, authenticated;

drop trigger if exists categories_reassign_references on public.categories;
create trigger categories_reassign_references
  before delete on public.categories
  for each row execute procedure public.reassign_deleted_category();
