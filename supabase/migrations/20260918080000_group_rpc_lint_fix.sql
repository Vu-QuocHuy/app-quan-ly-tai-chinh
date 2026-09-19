create or replace function public.create_expense_group(p_name text)
returns table (id uuid, name text, invite_code text, owner_id uuid)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_id uuid;
  v_code text;
  v_name text := trim(coalesce(p_name, ''));
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if char_length(v_name) < 2 or char_length(v_name) > 80 then
    raise exception 'Tên nhóm phải có từ 2 đến 80 ký tự' using errcode = '22023';
  end if;
  loop
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    exit when not exists (
      select 1
      from public.expense_groups as groups
      where groups.invite_code = v_code
    );
  end loop;
  insert into public.expense_groups (owner_id, name, invite_code)
    values (v_user_id, v_name, v_code)
    returning expense_groups.id into v_id;
  insert into public.expense_group_members (group_id, user_id, display_name, role)
    values (
      v_id,
      v_user_id,
      coalesce(
        nullif(trim((select display_name from public.profiles where user_id = v_user_id)), ''),
        'Chủ nhóm'
      ),
      'owner'
    );
  insert into public.group_audit_events (
    group_id,
    actor_id,
    target_user_id,
    event_type,
    metadata
  ) values (
    v_id,
    v_user_id,
    v_user_id,
    'group_created',
    jsonb_build_object('name', v_name)
  );
  return query select v_id, v_name, v_code, v_user_id;
end;
$$;

create or replace function public.join_expense_group(p_invite_code text)
returns table (id uuid, name text, invite_code text, owner_id uuid)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_group public.expense_groups%rowtype;
  v_display_name text;
  v_already_member boolean;
  v_attempt_count integer;
  v_window_started_at timestamptz;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_invite_code is null or char_length(trim(p_invite_code)) not between 1 and 32 then
    raise exception 'Mã tham gia nhóm không hợp lệ' using errcode = '22023';
  end if;

  insert into public.expense_group_join_rate_limits (user_id)
    values (v_user_id)
    on conflict (user_id) do nothing;
  select limits.attempt_count, limits.window_started_at
    into v_attempt_count, v_window_started_at
    from public.expense_group_join_rate_limits as limits
    where limits.user_id = v_user_id
    for update;
  if v_window_started_at <= now() - interval '1 minute' then
    update public.expense_group_join_rate_limits
      set window_started_at = now(), attempt_count = 1
      where user_id = v_user_id;
  elsif v_attempt_count >= 10 then
    raise exception 'Bạn đã thử quá nhiều mã. Hãy thử lại sau một phút.'
      using errcode = 'P0001';
  else
    update public.expense_group_join_rate_limits
      set attempt_count = attempt_count + 1
      where user_id = v_user_id;
  end if;

  select groups.*
    into v_group
    from public.expense_groups as groups
    where groups.invite_code = upper(trim(p_invite_code));
  if not found then
    raise exception 'Mã tham gia nhóm không hợp lệ' using errcode = '22023';
  end if;
  v_already_member := exists (
    select 1
    from public.expense_group_members as members
    where members.group_id = v_group.id and members.user_id = v_user_id
  );
  v_display_name := coalesce(
    nullif(trim((select display_name from public.profiles where user_id = v_user_id)), ''),
    'Thành viên'
  );
  insert into public.expense_group_members (group_id, user_id, display_name)
    values (v_group.id, v_user_id, v_display_name)
    on conflict (group_id, user_id) do nothing;
  if not v_already_member then
    insert into public.group_audit_events (group_id, actor_id, target_user_id, event_type)
      values (v_group.id, v_user_id, v_user_id, 'member_joined');
  end if;
  update public.expense_group_join_rate_limits
    set attempt_count = 0, window_started_at = now()
    where user_id = v_user_id;
  return query select v_group.id, v_group.name, v_group.invite_code, v_group.owner_id;
end;
$$;
