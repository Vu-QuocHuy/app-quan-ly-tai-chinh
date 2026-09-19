do $$
declare
  v_constraint text;
begin
  select conname into v_constraint
  from pg_constraint
  where conrelid = 'public.group_expenses'::regclass
    and contype = 'f'
    and conkey = array[
      (select attnum from pg_attribute
       where attrelid = 'public.group_expenses'::regclass
         and attname = 'payer_id')
    ]::smallint[];
  if v_constraint is not null then
    execute format(
      'alter table public.group_expenses drop constraint %I',
      v_constraint
    );
  end if;
end;
$$;

alter table public.group_expenses
  alter column payer_id drop not null;

alter table public.group_expenses
  add constraint group_expenses_payer_id_fkey
  foreign key (payer_id) references auth.users(id) on delete set null;
