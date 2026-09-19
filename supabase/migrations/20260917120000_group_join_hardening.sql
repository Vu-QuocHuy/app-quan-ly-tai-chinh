create table public.expense_group_join_rate_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null default now(),
  attempt_count integer not null default 0 check (attempt_count >= 0)
);

alter table public.expense_group_join_rate_limits enable row level security;
revoke all on table public.expense_group_join_rate_limits from public, anon, authenticated;

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
  select attempt_count, window_started_at
    into v_attempt_count, v_window_started_at
    from public.expense_group_join_rate_limits
    where user_id = v_user_id
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

  select * into v_group
    from public.expense_groups
    where invite_code = upper(trim(p_invite_code));
  if not found then
    raise exception 'Mã tham gia nhóm không hợp lệ' using errcode = '22023';
  end if;
  v_display_name := coalesce(
    nullif(trim((select display_name from public.profiles where user_id = v_user_id)), ''),
    'Thành viên'
  );
  insert into public.expense_group_members (group_id, user_id, display_name)
    values (v_group.id, v_user_id, v_display_name)
    on conflict (group_id, user_id) do nothing;
  update public.expense_group_join_rate_limits
    set attempt_count = 0, window_started_at = now()
    where user_id = v_user_id;
  return query select v_group.id, v_group.name, v_group.invite_code, v_group.owner_id;
end;
$$;

alter function public.is_expense_group_member(uuid, uuid)
  set search_path = public, pg_temp;
alter function public.create_expense_group(text)
  set search_path = public, pg_temp;
alter function public.create_group_expense(uuid, text, bigint, uuid[])
  set search_path = public, pg_temp;
alter function public.create_group_expense_custom(uuid, text, bigint, jsonb)
  set search_path = public, pg_temp;
alter function public.settle_group_split(uuid)
  set search_path = public, pg_temp;
alter function public.set_expense_group_member_role(uuid, uuid, text)
  set search_path = public, pg_temp;
alter function public.remove_expense_group_member(uuid, uuid)
  set search_path = public, pg_temp;
alter function public.leave_expense_group(uuid)
  set search_path = public, pg_temp;
