-- Atomic correction of an entry created by the current user. Lock the group
-- before re-reading the entry, matching add/delete lock order for fund balance.
create function public.update_own_group_fund_entry(
  p_id uuid, p_amount_minor bigint, p_note text,
  p_expected_amount_minor bigint, p_expected_note text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_entry public.group_fund_entries%rowtype;
  v_group_id uuid;
  v_balance numeric;
begin
  select group_id into v_group_id from public.group_fund_entries where id = p_id;
  if v_user_id is null or v_group_id is null
      or not public.is_current_user_expense_group_member(v_group_id) then
    raise exception 'Fund entry not accessible' using errcode = '28000';
  end if;
  if p_amount_minor is null or p_amount_minor not between 1 and 9007199254740991
      or p_note is null or char_length(p_note) > 160 then
    raise exception 'Invalid fund entry' using errcode = '22023';
  end if;
  perform 1 from public.expense_groups where id = v_group_id for update;
  select * into v_entry from public.group_fund_entries where id = p_id for update;
  if v_entry.id is null or v_entry.actor_id is distinct from v_user_id then
    raise exception 'Only the entry creator can correct it' using errcode = '28000';
  end if;
  if v_entry.amount_minor is distinct from p_expected_amount_minor
      or v_entry.note is distinct from p_expected_note then
    raise exception 'Fund entry changed; reload before editing' using errcode = '40001';
  end if;
  select coalesce(sum(case when kind = 'deposit' then amount_minor else -amount_minor end), 0)
    into v_balance from public.group_fund_entries where group_id = v_group_id;
  v_balance := v_balance + case when v_entry.kind = 'deposit'
    then p_amount_minor - v_entry.amount_minor else v_entry.amount_minor - p_amount_minor end;
  if v_balance < 0 then
    raise exception 'Quỹ không đủ tiền cho thay đổi này' using errcode = 'UF001';
  end if;
  if v_balance > 9007199254740991 then
    raise exception 'Fund balance exceeds limit' using errcode = '22023';
  end if;
  update public.group_fund_entries set amount_minor = p_amount_minor, note = trim(p_note) where id = p_id;
end;
$$;
revoke all on function public.update_own_group_fund_entry(uuid, bigint, text, bigint, text) from public, anon;
grant execute on function public.update_own_group_fund_entry(uuid, bigint, text, bigint, text) to authenticated;
