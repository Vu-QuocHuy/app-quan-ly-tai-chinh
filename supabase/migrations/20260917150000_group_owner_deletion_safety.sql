create or replace function public.reassign_groups_before_user_delete()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_group_id uuid;
  v_new_owner_id uuid;
begin
  for v_group_id in
    select id from public.expense_groups where owner_id = old.id
  loop
    v_new_owner_id := null;
    select user_id into v_new_owner_id
      from public.expense_group_members
      where group_id = v_group_id and user_id <> old.id
      order by joined_at asc, user_id asc
      limit 1
      for update;

    if v_new_owner_id is null then
      delete from public.expense_groups where id = v_group_id;
      continue;
    end if;

    update public.expense_group_members
      set role = 'member'
      where group_id = v_group_id;
    update public.expense_group_members
      set role = 'owner'
      where group_id = v_group_id and user_id = v_new_owner_id;
    update public.expense_groups
      set owner_id = v_new_owner_id
      where id = v_group_id;
    insert into public.group_audit_events (
      group_id, actor_id, target_user_id, event_type, metadata
    ) values (
      v_group_id,
      old.id,
      v_new_owner_id,
      'member_role_changed',
      jsonb_build_object('from', 'owner', 'to', 'owner', 'reason', 'account_deleted')
    );
  end loop;
  return old;
end;
$$;

revoke all on function public.reassign_groups_before_user_delete() from public, anon, authenticated;

drop trigger if exists before_auth_user_delete_reassign_groups on auth.users;
create trigger before_auth_user_delete_reassign_groups
  before delete on auth.users
  for each row execute procedure public.reassign_groups_before_user_delete();
