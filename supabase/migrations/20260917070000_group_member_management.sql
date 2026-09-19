alter table public.group_audit_events
  drop constraint if exists group_audit_events_event_type_check;

alter table public.group_audit_events
  add constraint group_audit_events_event_type_check check (
    event_type in (
      'group_created',
      'member_joined',
      'member_role_changed',
      'member_removed',
      'member_left',
      'expense_created',
      'expense_settled'
    )
  );

create or replace function public.set_expense_group_member_role(
  p_group_id uuid,
  p_user_id uuid,
  p_role text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_owner_id uuid;
  v_old_role text;
begin
  if v_actor_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_role is null or p_role not in ('owner', 'member') then
    raise exception 'Vai trò không hợp lệ' using errcode = '22023';
  end if;
  select owner_id into v_owner_id
    from public.expense_groups
    where id = p_group_id
    for update;
  if v_owner_id is null or v_owner_id <> v_actor_id then
    raise exception 'Chỉ chủ nhóm mới được quản lý vai trò' using errcode = '42501';
  end if;
  if p_user_id = v_actor_id then
    raise exception 'Không thể thay đổi vai trò của chủ nhóm hiện tại' using errcode = '22023';
  end if;
  select role into v_old_role
    from public.expense_group_members
    where group_id = p_group_id and user_id = p_user_id
    for update;
  if v_old_role is null then
    raise exception 'Thành viên không tồn tại trong nhóm' using errcode = '22023';
  end if;
  if v_old_role = p_role then
    return;
  end if;
  if p_role = 'owner' then
    update public.expense_group_members
      set role = 'member'
      where group_id = p_group_id and user_id = v_actor_id;
    update public.expense_group_members
      set role = 'owner'
      where group_id = p_group_id and user_id = p_user_id;
    update public.expense_groups
      set owner_id = p_user_id
      where id = p_group_id;
  else
    update public.expense_group_members
      set role = 'member'
      where group_id = p_group_id and user_id = p_user_id;
  end if;
  insert into public.group_audit_events (
    group_id, actor_id, target_user_id, event_type, metadata
  ) values (
    p_group_id,
    v_actor_id,
    p_user_id,
    'member_role_changed',
    jsonb_build_object('from', v_old_role, 'to', p_role)
  );
end;
$$;

create or replace function public.remove_expense_group_member(
  p_group_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_owner_id uuid;
  v_role text;
begin
  if v_actor_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  select owner_id into v_owner_id
    from public.expense_groups
    where id = p_group_id
    for update;
  if v_owner_id is null or v_owner_id <> v_actor_id then
    raise exception 'Chỉ chủ nhóm mới được xóa thành viên' using errcode = '42501';
  end if;
  select role into v_role
    from public.expense_group_members
    where group_id = p_group_id and user_id = p_user_id
    for update;
  if v_role is null then
    raise exception 'Thành viên không tồn tại trong nhóm' using errcode = '22023';
  end if;
  if v_role = 'owner' or p_user_id = v_actor_id then
    raise exception 'Không thể xóa chủ nhóm' using errcode = '22023';
  end if;
  insert into public.group_audit_events (
    group_id, actor_id, target_user_id, event_type
  ) values (
    p_group_id, v_actor_id, p_user_id, 'member_removed'
  );
  delete from public.expense_group_members
    where group_id = p_group_id and user_id = p_user_id;
end;
$$;

create or replace function public.leave_expense_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_owner_id uuid;
  v_is_owner boolean;
  v_other_members boolean;
begin
  if v_actor_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  select owner_id into v_owner_id
    from public.expense_groups
    where id = p_group_id
    for update;
  if v_owner_id is null then
    raise exception 'Nhóm không tồn tại' using errcode = '22023';
  end if;
  if not public.is_expense_group_member(p_group_id, v_actor_id) then
    raise exception 'Bạn không thuộc nhóm này' using errcode = '42501';
  end if;
  v_is_owner := v_owner_id = v_actor_id;
  if v_is_owner then
    select exists (
      select 1 from public.expense_group_members
      where group_id = p_group_id and user_id <> v_actor_id
    ) into v_other_members;
    if v_other_members then
      raise exception 'Hãy chuyển quyền chủ nhóm trước khi rời nhóm' using errcode = '22023';
    end if;
    delete from public.expense_groups where id = p_group_id;
    return;
  end if;
  insert into public.group_audit_events (
    group_id, actor_id, target_user_id, event_type
  ) values (
    p_group_id, v_actor_id, v_actor_id, 'member_left'
  );
  delete from public.expense_group_members
    where group_id = p_group_id and user_id = v_actor_id;
end;
$$;

revoke all on function public.set_expense_group_member_role(uuid, uuid, text)
  from public, anon;
revoke all on function public.remove_expense_group_member(uuid, uuid)
  from public, anon;
revoke all on function public.leave_expense_group(uuid)
  from public, anon;
grant execute on function public.set_expense_group_member_role(uuid, uuid, text)
  to authenticated;
grant execute on function public.remove_expense_group_member(uuid, uuid)
  to authenticated;
grant execute on function public.leave_expense_group(uuid)
  to authenticated;
