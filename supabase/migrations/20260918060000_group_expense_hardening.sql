create or replace function public.create_group_expense(
  p_group_id uuid,
  p_description text,
  p_total_minor bigint,
  p_split_user_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_expense_id uuid;
  v_count integer;
  v_base bigint;
  v_remainder bigint;
  v_member uuid;
  v_position integer := 0;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if not exists (
    select 1
    from public.expense_group_members
    where group_id = p_group_id and user_id = v_user_id
  ) then
    raise exception 'Bạn không thuộc nhóm này' using errcode = '42501';
  end if;
  if p_total_minor is null or p_total_minor <= 0 then
    raise exception 'Tổng tiền phải lớn hơn 0' using errcode = '22023';
  end if;
  if char_length(trim(coalesce(p_description, ''))) not between 2 and 160 then
    raise exception 'Mô tả khoản chi không hợp lệ' using errcode = '22023';
  end if;
  if p_split_user_ids is null or cardinality(p_split_user_ids) < 1 then
    raise exception 'Hãy chọn ít nhất một thành viên' using errcode = '22023';
  end if;
  if cardinality(p_split_user_ids) > 100 then
    raise exception 'Danh sách thành viên quá dài' using errcode = '22023';
  end if;
  select count(*) into v_count from unnest(p_split_user_ids);
  if v_count <> (select count(distinct item) from unnest(p_split_user_ids) as item) then
    raise exception 'Danh sách thành viên bị trùng' using errcode = '22023';
  end if;
  if exists (
    select 1
    from unnest(p_split_user_ids) as item
    where not exists (
      select 1
      from public.expense_group_members as members
      where members.group_id = p_group_id and members.user_id = item
    )
  ) then
    raise exception 'Có thành viên không thuộc nhóm' using errcode = '42501';
  end if;
  insert into public.group_expenses (group_id, payer_id, description, total_minor)
    values (p_group_id, v_user_id, trim(p_description), p_total_minor)
    returning id into v_expense_id;
  v_base := p_total_minor / v_count;
  v_remainder := p_total_minor % v_count;
  foreach v_member in array p_split_user_ids loop
    v_position := v_position + 1;
    insert into public.group_expense_splits (expense_id, user_id, amount_minor)
      values (
        v_expense_id,
        v_member,
        v_base + case when v_position <= v_remainder then 1 else 0 end
      );
  end loop;
  return v_expense_id;
end;
$$;

create or replace function public.create_group_expense_custom(
  p_group_id uuid,
  p_description text,
  p_total_minor bigint,
  p_splits jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_expense_id uuid;
  v_split jsonb;
  v_member_id uuid;
  v_amount bigint;
  v_amount_numeric numeric;
  v_total bigint := 0;
  v_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if not public.is_expense_group_member(p_group_id, v_user_id) then
    raise exception 'Bạn không thuộc nhóm này' using errcode = '42501';
  end if;
  if p_total_minor is null or p_total_minor <= 0 then
    raise exception 'Tổng tiền phải lớn hơn 0' using errcode = '22023';
  end if;
  if char_length(trim(coalesce(p_description, ''))) not between 2 and 160 then
    raise exception 'Mô tả khoản chi không hợp lệ' using errcode = '22023';
  end if;
  if p_splits is null or jsonb_typeof(p_splits) <> 'array' then
    raise exception 'Danh sách chia tiền không hợp lệ' using errcode = '22023';
  end if;
  if jsonb_array_length(p_splits) < 1 or jsonb_array_length(p_splits) > 100 then
    raise exception 'Danh sách chia tiền không hợp lệ' using errcode = '22023';
  end if;
  for v_split in select value from jsonb_array_elements(p_splits) loop
    if jsonb_typeof(v_split) <> 'object' or
       coalesce(v_split ->> 'user_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' or
       coalesce(v_split ->> 'amount_minor', '') !~ '^[0-9]{1,19}$' then
      raise exception 'Phần chia tiền không hợp lệ' using errcode = '22023';
    end if;
    v_member_id := (v_split ->> 'user_id')::uuid;
    v_amount_numeric := (v_split ->> 'amount_minor')::numeric;
    if v_amount_numeric > p_total_minor - v_total then
      raise exception 'Tổng phần chia vượt tổng khoản chi' using errcode = '22023';
    end if;
    v_amount := v_amount_numeric::bigint;
    if not public.is_expense_group_member(p_group_id, v_member_id) then
      raise exception 'Có thành viên không thuộc nhóm' using errcode = '42501';
    end if;
    v_total := v_total + v_amount;
    v_count := v_count + 1;
  end loop;
  if v_total <> p_total_minor then
    raise exception 'Tổng các phần chia phải bằng tổng khoản chi' using errcode = '22023';
  end if;
  if v_count <> (
    select count(distinct value ->> 'user_id')
    from jsonb_array_elements(p_splits)
  ) then
    raise exception 'Danh sách thành viên bị trùng' using errcode = '22023';
  end if;
  insert into public.group_expenses (group_id, payer_id, description, total_minor)
    values (p_group_id, v_user_id, trim(p_description), p_total_minor)
    returning id into v_expense_id;
  for v_split in select value from jsonb_array_elements(p_splits) loop
    insert into public.group_expense_splits (expense_id, user_id, amount_minor)
      values (
        v_expense_id,
        (v_split ->> 'user_id')::uuid,
        (v_split ->> 'amount_minor')::bigint
      );
  end loop;
  return v_expense_id;
end;
$$;

revoke all on function public.create_group_expense(uuid, text, bigint, uuid[])
  from public, anon;
revoke all on function public.create_group_expense_custom(uuid, text, bigint, jsonb)
  from public, anon;
grant execute on function public.create_group_expense(uuid, text, bigint, uuid[])
  to authenticated;
grant execute on function public.create_group_expense_custom(uuid, text, bigint, jsonb)
  to authenticated;
