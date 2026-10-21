-- Spec A: mục tiêu quỹ nhóm, mã lỗi UF001 cho thông báo người dùng, và sửa lỗi có sẵn:
-- giới hạn tham gia nhóm không đếm lần nhập sai, kiểm tra quyền so sánh với null,
-- và actor_id của dòng quỹ chặn xóa tài khoản.

alter table public.expense_groups
  add column fund_goal_minor bigint
    check (fund_goal_minor between 1 and 9007199254740991),
  add column fund_deadline date,
  add constraint expense_groups_fund_deadline_needs_goal
    check (fund_deadline is null or fund_goal_minor is not null);

alter table public.group_fund_entries
  alter column actor_id drop not null,
  drop constraint group_fund_entries_actor_id_fkey,
  add constraint group_fund_entries_actor_id_fkey
    foreign key (actor_id) references auth.users(id) on delete set null;

create function public.set_group_fund_goal(
  p_group_id uuid,
  p_goal_minor bigint,
  p_deadline date
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_owner_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  select owner_id into v_owner_id
    from public.expense_groups where id = p_group_id for update;
  if v_owner_id is null or v_owner_id <> v_user_id then
    raise exception 'Chỉ trưởng nhóm được đặt mục tiêu quỹ' using errcode = 'UF001';
  end if;
  if p_goal_minor is null then
    update public.expense_groups
      set fund_goal_minor = null, fund_deadline = null
      where id = p_group_id;
    return;
  end if;
  if p_goal_minor not between 1 and 9007199254740991 then
    raise exception 'Mục tiêu quỹ không hợp lệ' using errcode = 'UF001';
  end if;
  if p_deadline is not null and p_deadline < current_date then
    raise exception 'Hạn quỹ phải từ hôm nay trở đi' using errcode = 'UF001';
  end if;
  update public.expense_groups
    set fund_goal_minor = p_goal_minor, fund_deadline = p_deadline
    where id = p_group_id;
end;
$$;

revoke all on function public.set_group_fund_goal(uuid, bigint, date) from public, anon;
grant execute on function public.set_group_fund_goal(uuid, bigint, date) to authenticated;

-- Mã sai trả 0 dòng thay vì raise, để lượt tăng attempt_count được commit.
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
      using errcode = 'UF001';
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
    return;
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
  return query select v_group.id, v_group.name, v_group.invite_code, v_group.owner_id;
end;
$$;

-- Chỉ đổi mã lỗi số dư không đủ sang UF001.
create or replace function public.add_group_fund_entry(
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
      raise exception 'Quỹ không đủ tiền cho khoản chi này' using errcode = 'UF001';
    end if;
  end if;
  insert into public.group_fund_entries (group_id, actor_id, kind, amount_minor, note)
  values (p_group_id, v_user_id, p_kind, p_amount_minor, trim(p_note))
  returning id into v_id;
  return v_id;
end;
$$;

-- actor_id có thể null (tài khoản đã xóa): chỉ trưởng nhóm được xóa dòng đó.
create or replace function public.delete_group_fund_entry(p_id uuid)
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
  if v_entry.actor_id is distinct from v_user_id and v_owner_id <> v_user_id then
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

-- payer_id có thể null (tài khoản đã xóa): dùng is distinct from để không bỏ qua kiểm tra quyền.
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
  if v_actor_id is distinct from v_payer_id and not exists (
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
  if v_actor_id is distinct from v_payer_id and not exists (
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
