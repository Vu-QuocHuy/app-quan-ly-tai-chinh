create table public.group_audit_events (
  id bigint generated always as identity primary key,
  group_id uuid not null references public.expense_groups(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  target_user_id uuid references auth.users(id) on delete set null,
  expense_id uuid references public.group_expenses(id) on delete set null,
  event_type text not null check (
    event_type in ('group_created', 'member_joined', 'expense_created', 'expense_settled')
  ),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index group_audit_events_group_created_idx
  on public.group_audit_events (group_id, created_at desc);

alter table public.group_audit_events enable row level security;

revoke all on table public.group_audit_events from anon;
grant select on table public.group_audit_events to authenticated;

create policy group_audit_events_member_select on public.group_audit_events
  for select to authenticated
  using (public.is_expense_group_member(group_id, (select auth.uid())));

create or replace function public.create_expense_group(p_name text)
returns table (id uuid, name text, invite_code text, owner_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_id uuid;
  v_code text;
  v_name text := trim(coalesce(p_name, ''));
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if char_length(v_name) < 2 or char_length(v_name) > 80 then
    raise exception 'Tên nhóm phải có từ 2 đến 80 ký tự' using errcode = '22023';
  end if;
  loop
    v_code := upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 8));
    exit when not exists (select 1 from public.expense_groups g where g.invite_code = v_code);
  end loop;
  insert into public.expense_groups (owner_id, name, invite_code)
    values (v_user_id, v_name, v_code)
    returning expense_groups.id into v_id;
  insert into public.expense_group_members (group_id, user_id, display_name, role)
    values (v_id, v_user_id, coalesce(nullif(trim((select display_name from public.profiles where user_id = v_user_id)), ''), 'Chủ nhóm'), 'owner');
  insert into public.group_audit_events (group_id, actor_id, target_user_id, event_type, metadata)
    values (v_id, v_user_id, v_user_id, 'group_created', jsonb_build_object('name', v_name));
  return query select v_id, v_name, v_code, v_user_id;
end;
$$;

create or replace function public.join_expense_group(p_invite_code text)
returns table (id uuid, name text, invite_code text, owner_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_group public.expense_groups%rowtype;
  v_display_name text;
  v_already_member boolean;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  select * into v_group from public.expense_groups
    where invite_code = upper(trim(coalesce(p_invite_code, '')));
  if not found then raise exception 'Mã tham gia nhóm không hợp lệ' using errcode = '22023'; end if;
  v_already_member := exists (
    select 1 from public.expense_group_members
    where group_id = v_group.id and user_id = v_user_id
  );
  v_display_name := coalesce(nullif(trim((select display_name from public.profiles where user_id = v_user_id)), ''), 'Thành viên');
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

create or replace function public.create_group_expense(
  p_group_id uuid,
  p_description text,
  p_total_minor bigint,
  p_split_user_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public
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
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if not exists (select 1 from public.expense_group_members where group_id = p_group_id and user_id = v_user_id) then
    raise exception 'Bạn không thuộc nhóm này' using errcode = '42501';
  end if;
  if p_total_minor is null or p_total_minor <= 0 then raise exception 'Tổng tiền phải lớn hơn 0' using errcode = '22023'; end if;
  if char_length(trim(coalesce(p_description, ''))) not between 2 and 160 then
    raise exception 'Mô tả khoản chi phải có từ 2 đến 160 ký tự' using errcode = '22023';
  end if;
  if p_split_user_ids is null or cardinality(p_split_user_ids) < 1 then raise exception 'Hãy chọn ít nhất một thành viên' using errcode = '22023'; end if;
  if cardinality(p_split_user_ids) > 100 then
    raise exception 'Không thể chia cho quá 100 thành viên' using errcode = '22023';
  end if;
  select count(*) into v_count from unnest(p_split_user_ids);
  if v_count <> (select count(distinct item) from unnest(p_split_user_ids) as item) then
    raise exception 'Danh sách thành viên bị trùng' using errcode = '22023';
  end if;
  if exists (
    select 1 from unnest(p_split_user_ids) as item
    where not exists (select 1 from public.expense_group_members m where m.group_id = p_group_id and m.user_id = item)
  ) then raise exception 'Có thành viên không thuộc nhóm' using errcode = '42501'; end if;
  insert into public.group_expenses (group_id, payer_id, description, total_minor)
    values (p_group_id, v_user_id, trim(p_description), p_total_minor)
    returning id into v_expense_id;
  v_base := p_total_minor / v_count;
  v_remainder := p_total_minor % v_count;
  foreach v_member in array p_split_user_ids loop
    v_position := v_position + 1;
    insert into public.group_expense_splits (expense_id, user_id, amount_minor)
      values (v_expense_id, v_member, v_base + case when v_position <= v_remainder then 1 else 0 end);
  end loop;
  insert into public.group_audit_events (group_id, actor_id, expense_id, event_type, metadata)
    values (p_group_id, v_user_id, v_expense_id, 'expense_created', jsonb_build_object('total_minor', p_total_minor));
  return v_expense_id;
end;
$$;

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
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  select e.group_id into v_group_id
  from public.group_expenses e
  join public.expense_group_members m on m.group_id = e.group_id and m.user_id = v_user_id
  where e.id = p_expense_id;
  if v_group_id is null then raise exception 'Không tìm thấy khoản chi trong nhóm của bạn' using errcode = '22023'; end if;
  update public.group_expense_splits
    set settled_at = coalesce(settled_at, now())
    where expense_id = p_expense_id and user_id = v_user_id;
  if not found then raise exception 'Không tìm thấy phần chia của bạn' using errcode = '22023'; end if;
  insert into public.group_audit_events (group_id, actor_id, expense_id, event_type)
    values (v_group_id, v_user_id, p_expense_id, 'expense_settled');
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
  if char_length(trim(coalesce(p_description, ''))) not between 2 and 160 then
    raise exception 'Mô tả khoản chi phải có từ 2 đến 160 ký tự' using errcode = '22023';
  end if;
  if jsonb_typeof(p_splits) <> 'array' then
    raise exception 'Danh sách chia tiền không hợp lệ' using errcode = '22023';
  end if;
  if jsonb_array_length(p_splits) < 1 then
    raise exception 'Danh sách chia tiền không hợp lệ' using errcode = '22023';
  end if;
  if jsonb_array_length(p_splits) > 100 then
    raise exception 'Không thể chia cho quá 100 thành viên' using errcode = '22023';
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
  insert into public.group_audit_events (group_id, actor_id, expense_id, event_type, metadata)
    values (p_group_id, v_user_id, v_expense_id, 'expense_created', jsonb_build_object('total_minor', p_total_minor));
  return v_expense_id;
end;
$$;
