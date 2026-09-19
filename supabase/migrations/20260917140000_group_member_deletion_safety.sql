alter table public.group_expense_splits
  drop constraint group_expense_splits_pkey;
alter table public.group_expense_splits
  alter column user_id drop not null;
alter table public.group_expense_splits
  drop constraint group_expense_splits_user_id_fkey;
alter table public.group_expense_splits
  add constraint group_expense_splits_user_id_fkey
    foreign key (user_id) references auth.users(id) on delete set null;

create unique index group_expense_splits_expense_user_unique_idx
  on public.group_expense_splits (expense_id, user_id);
