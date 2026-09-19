-- A group expense remains editable only while nobody has settled a split.
-- Every mutation is server-authorized and leaves an audit event.

alter table public.group_audit_events
  drop constraint if exists group_audit_events_event_type_check;

alter table public.group_audit_events
  add constraint group_audit_events_event_type_check check (
    event_type in (
      'group_created', 'member_joined', 'member_role_changed',
      'member_removed', 'member_left', 'expense_created', 'expense_settled',
      'expense_updated', 'expense_deleted'
    )
  );

create or replace function public.update_group_expense_custom(
  p_expense_id uuid,
  p_description text,
  p_total_minor bigint,
  p_splits jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_group_id uuid;
  v_payer_id uuid;
  v_split jsonb;
  v_member_id uuid;
  v_amount bigint;
  v_amount_numeric numeric;
  v_total bigint := 0;
  v_count integer := 0;
begin
  if v_actor_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  select group_id, payer_id into v_group_id, v_payer_id
    from public.group_expenses where id = p_expense_id for update;
  if v_group_id is null then
    raise exception 'Khoản chi không tồn tại' using errcode = '22023';
  end if;
  if v_actor_id <> v_payer_id and not exists (
    select 1 from public.expense_groups where id = v_group_id and owner_id = v_actor_id
  ) then
    raise exception 'Chỉ người trả hoặc chủ nhóm được sửa khoản chi' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.group_expense_splits
    where expense_id = p_expense_id and settled_at is not null
  ) then
    raise exception 'Khoản chi đã có thanh toán; hãy tạo khoản điều chỉnh mới' using errcode = '22023';
  end if;
  if p_total_minor is null or p_total_minor <= 0
     or char_length(trim(coalesce(p_description, ''))) not between 2 and 160
     or p_splits is null or jsonb_typeof(p_splits) <> 'array'
     or jsonb_array_length(p_splits) not between 1 and 100 then
    raise exception 'Dữ liệu khoản chi không hợp lệ' using errcode = '22023';
  end if;
  for v_split in select value from jsonb_array_elements(p_splits) loop
    if jsonb_typeof(v_split) <> 'object'
       or coalesce(v_split ->> 'user_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or coalesce(v_split ->> 'amount_minor', '') !~ '^[0-9]{1,19}$' then
      raise exception 'Phần chia tiền không hợp lệ' using errcode = '22023';
    end if;
    v_member_id := (v_split ->> 'user_id')::uuid;
    v_amount_numeric := (v_split ->> 'amount_minor')::numeric;
    if v_amount_numeric > p_total_minor - v_total
       or not public.is_expense_group_member(v_group_id, v_member_id) then
      raise exception 'Phần chia tiền không hợp lệ' using errcode = '22023';
    end if;
    v_amount := v_amount_numeric::bigint;
    v_total := v_total + v_amount;
    v_count := v_count + 1;
  end loop;
  if v_total <> p_total_minor or v_count <> (
    select count(distinct value ->> 'user_id') from jsonb_array_elements(p_splits)
  ) then
    raise exception 'Tổng hoặc danh sách phần chia không hợp lệ' using errcode = '22023';
  end if;
  update public.group_expenses
    set description = trim(p_description), total_minor = p_total_minor
    where id = p_expense_id;
  delete from public.group_expense_splits where expense_id = p_expense_id;
  for v_split in select value from jsonb_array_elements(p_splits) loop
    insert into public.group_expense_splits (expense_id, user_id, amount_minor)
      values (p_expense_id, (v_split ->> 'user_id')::uuid, (v_split ->> 'amount_minor')::bigint);
  end loop;
  insert into public.group_audit_events (group_id, actor_id, expense_id, event_type, metadata)
    values (v_group_id, v_actor_id, p_expense_id, 'expense_updated', jsonb_build_object('total_minor', p_total_minor));
end;
$$;

create or replace function public.delete_group_expense(p_expense_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_group_id uuid;
  v_payer_id uuid;
  v_description text;
  v_total_minor bigint;
begin
  if v_actor_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  select group_id, payer_id, description, total_minor into v_group_id, v_payer_id, v_description, v_total_minor
    from public.group_expenses where id = p_expense_id for update;
  if v_group_id is null then raise exception 'Khoản chi không tồn tại' using errcode = '22023'; end if;
  if v_actor_id <> v_payer_id and not exists (
    select 1 from public.expense_groups where id = v_group_id and owner_id = v_actor_id
  ) then raise exception 'Chỉ người trả hoặc chủ nhóm được xóa khoản chi' using errcode = '42501'; end if;
  if exists (select 1 from public.group_expense_splits where expense_id = p_expense_id and settled_at is not null) then
    raise exception 'Khoản chi đã có thanh toán; hãy tạo khoản điều chỉnh mới' using errcode = '22023';
  end if;
  insert into public.group_audit_events (group_id, actor_id, expense_id, event_type, metadata)
    values (v_group_id, v_actor_id, p_expense_id, 'expense_deleted', jsonb_build_object('description', v_description, 'total_minor', v_total_minor));
  delete from public.group_expenses where id = p_expense_id;
end;
$$;

revoke all on function public.update_group_expense_custom(uuid, text, bigint, jsonb) from public, anon;
revoke all on function public.delete_group_expense(uuid) from public, anon;
grant execute on function public.update_group_expense_custom(uuid, text, bigint, jsonb) to authenticated;
grant execute on function public.delete_group_expense(uuid) to authenticated;
