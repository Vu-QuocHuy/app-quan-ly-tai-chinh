create table public.group_fund_entries (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.expense_groups(id) on delete cascade,
  actor_id uuid not null references auth.users(id) on delete restrict,
  kind text not null check (kind in ('deposit', 'expense')),
  amount_minor bigint not null check (amount_minor between 1 and 9007199254740991),
  note text not null default '' check (char_length(note) <= 160),
  created_at timestamptz not null default now()
);

create index group_fund_entries_group_created_idx
  on public.group_fund_entries (group_id, created_at desc);

alter table public.group_fund_entries enable row level security;
revoke all on public.group_fund_entries from public, anon, authenticated;
grant select on public.group_fund_entries to authenticated;

create policy group_fund_member_select on public.group_fund_entries
  for select to authenticated
  using (public.is_current_user_expense_group_member(group_id));

create function public.add_group_fund_entry(
  p_group_id uuid,
  p_kind text,
  p_amount_minor bigint,
  p_note text default ''
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_balance numeric;
  v_id uuid;
begin
  if v_user_id is null or not public.is_current_user_expense_group_member(p_group_id) then
    raise exception 'Group membership required' using errcode = '28000';
  end if;
  if p_kind is null or p_kind not in ('deposit', 'expense')
      or p_amount_minor is null or p_amount_minor not between 1 and 9007199254740991
      or p_note is null or char_length(p_note) > 160 then
    raise exception 'Fund entry is invalid' using errcode = '22023';
  end if;

  perform 1 from public.expense_groups where id = p_group_id for update;
  select coalesce(sum(case when kind = 'deposit' then amount_minor else -amount_minor end), 0)
    into v_balance
  from public.group_fund_entries where group_id = p_group_id;
  if p_kind = 'deposit' and v_balance + p_amount_minor > 9007199254740991 then
    raise exception 'Số dư quỹ vượt giới hạn' using errcode = '22023';
  end if;
  if p_kind = 'expense' then
    if v_balance < p_amount_minor then
      raise exception 'Quỹ không đủ tiền cho khoản chi này' using errcode = '22023';
    end if;
  end if;
  insert into public.group_fund_entries (group_id, actor_id, kind, amount_minor, note)
  values (p_group_id, v_user_id, p_kind, p_amount_minor, trim(p_note))
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.add_group_fund_entry(uuid, text, bigint, text)
  from public, anon;
grant execute on function public.add_group_fund_entry(uuid, text, bigint, text)
  to authenticated;

create function public.delete_group_fund_entry(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_entry public.group_fund_entries%rowtype;
  v_owner_id uuid;
  v_balance numeric;
begin
  select * into v_entry from public.group_fund_entries where id = p_id;
  if v_entry.id is null or v_user_id is null
      or not public.is_current_user_expense_group_member(v_entry.group_id) then
    raise exception 'Fund entry not accessible' using errcode = '28000';
  end if;
  select owner_id into v_owner_id from public.expense_groups
    where id = v_entry.group_id for update;
  if v_entry.actor_id <> v_user_id and v_owner_id <> v_user_id then
    raise exception 'Only creator or group owner can delete' using errcode = '28000';
  end if;
  if v_entry.kind = 'deposit' then
    select coalesce(sum(case when kind = 'deposit' then amount_minor else -amount_minor end), 0)
      into v_balance
    from public.group_fund_entries where group_id = v_entry.group_id;
    if v_balance < v_entry.amount_minor then
      raise exception 'Không thể xóa khoản thu khi quỹ đã sử dụng tiền này' using errcode = '22023';
    end if;
  else
    select coalesce(sum(case when kind = 'deposit' then amount_minor else -amount_minor end), 0)
      into v_balance
    from public.group_fund_entries where group_id = v_entry.group_id;
    if v_balance + v_entry.amount_minor > 9007199254740991 then
      raise exception 'Số dư quỹ vượt giới hạn' using errcode = '22023';
    end if;
  end if;
  delete from public.group_fund_entries where id = p_id;
end;
$$;

revoke all on function public.delete_group_fund_entry(uuid) from public, anon;
grant execute on function public.delete_group_fund_entry(uuid) to authenticated;
