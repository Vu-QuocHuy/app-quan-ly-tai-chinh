create or replace function public.create_group_expense_custom(
  p_group_id uuid,
  p_description text,
  p_total_minor bigint,
  p_splits jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_expense_id uuid;
  v_split jsonb;
  v_member_id uuid;
  v_amount bigint;
  v_total bigint := 0;
  v_count integer := 0;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if not public.is_expense_group_member(p_group_id, v_user_id) then
    raise exception 'Bạn không thuộc nhóm này' using errcode = '42501';
  end if;
  if p_total_minor is null or p_total_minor <= 0 then
    raise exception 'Tổng tiền phải lớn hơn 0' using errcode = '22023';
  end if;
  if jsonb_typeof(p_splits) <> 'array' or jsonb_array_length(p_splits) < 1 then
    raise exception 'Danh sách chia tiền không hợp lệ' using errcode = '22023';
  end if;
  for v_split in select value from jsonb_array_elements(p_splits) loop
    v_member_id := (v_split ->> 'user_id')::uuid;
    v_amount := (v_split ->> 'amount_minor')::bigint;
    if v_amount is null or v_amount < 0 then
      raise exception 'Số tiền chia không hợp lệ' using errcode = '22023';
    end if;
    if not public.is_expense_group_member(p_group_id, v_member_id) then
      raise exception 'Có thành viên không thuộc nhóm' using errcode = '42501';
    end if;
    v_total := v_total + v_amount;
    v_count := v_count + 1;
  end loop;
  if v_total <> p_total_minor then
    raise exception 'Tổng các phần chia phải bằng tổng khoản chi' using errcode = '22023';
  end if;
  if v_count <> (select count(distinct (value ->> 'user_id')) from jsonb_array_elements(p_splits)) then
    raise exception 'Danh sách thành viên bị trùng' using errcode = '22023';
  end if;
  insert into public.group_expenses (group_id, payer_id, description, total_minor)
    values (p_group_id, v_user_id, trim(p_description), p_total_minor)
    returning id into v_expense_id;
  for v_split in select value from jsonb_array_elements(p_splits) loop
    insert into public.group_expense_splits (expense_id, user_id, amount_minor)
      values (v_expense_id, (v_split ->> 'user_id')::uuid, (v_split ->> 'amount_minor')::bigint);
  end loop;
  return v_expense_id;
end;
$$;

revoke all on function public.create_group_expense_custom(uuid, text, bigint, jsonb) from public, anon;
grant execute on function public.create_group_expense_custom(uuid, text, bigint, jsonb) to authenticated;
