alter table public.budgets
  drop constraint if exists budgets_month_key_check;

alter table public.budgets
  add constraint budgets_month_key_check
  check (month_key ~ '^[0-9]{4}-(0[1-9]|1[0-2])$');
