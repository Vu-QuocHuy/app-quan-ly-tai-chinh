create or replace function public.settle_group_split(p_expense_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_group_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select e.group_id into v_group_id
  from public.group_expenses e
  join public.expense_group_members m
    on m.group_id = e.group_id and m.user_id = v_user_id
  where e.id = p_expense_id;

  if v_group_id is null then
    raise exception 'Không tìm thấy khoản chi trong nhóm của bạn'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.group_expense_splits
    where expense_id = p_expense_id and user_id = v_user_id
  ) then
    raise exception 'Không tìm thấy phần chia của bạn' using errcode = '22023';
  end if;

  update public.group_expense_splits
  set settled_at = now()
  where expense_id = p_expense_id
    and user_id = v_user_id
    and settled_at is null;

  if found then
    insert into public.group_audit_events (group_id, actor_id, expense_id, event_type)
      values (v_group_id, v_user_id, p_expense_id, 'expense_settled');
  end if;
end;
$$;
