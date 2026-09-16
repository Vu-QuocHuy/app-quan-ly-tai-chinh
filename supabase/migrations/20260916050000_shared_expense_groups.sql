create table public.expense_groups (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 2 and 80),
  invite_code text not null unique,
  created_at timestamptz not null default now()
);

create table public.expense_group_members (
  group_id uuid not null references public.expense_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null default 'Thành viên',
  role text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table public.group_expenses (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.expense_groups(id) on delete cascade,
  payer_id uuid not null references auth.users(id) on delete restrict,
  description text not null check (char_length(trim(description)) between 2 and 160),
  total_minor bigint not null check (total_minor > 0),
  currency_code text not null default 'VND',
  created_at timestamptz not null default now()
);

create table public.group_expense_splits (
  expense_id uuid not null references public.group_expenses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  amount_minor bigint not null check (amount_minor >= 0),
  settled_at timestamptz,
  primary key (expense_id, user_id)
);

create index expense_group_members_user_idx
  on public.expense_group_members (user_id, group_id);
create index group_expenses_group_created_idx
  on public.group_expenses (group_id, created_at desc);
create index group_expense_splits_user_idx
  on public.group_expense_splits (user_id, expense_id);

alter table public.expense_groups enable row level security;
alter table public.expense_group_members enable row level security;
alter table public.group_expenses enable row level security;
alter table public.group_expense_splits enable row level security;

revoke all on table public.expense_groups from anon;
revoke all on table public.expense_group_members from anon;
revoke all on table public.group_expenses from anon;
revoke all on table public.group_expense_splits from anon;
grant select on table public.expense_groups to authenticated;
grant select on table public.expense_group_members to authenticated;
grant select on table public.group_expenses to authenticated;
grant select on table public.group_expense_splits to authenticated;

create or replace function public.is_expense_group_member(
  p_group_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.expense_group_members m
    where m.group_id = p_group_id and m.user_id = p_user_id
  );
$$;

revoke all on function public.is_expense_group_member(uuid, uuid) from public, anon;
grant execute on function public.is_expense_group_member(uuid, uuid) to authenticated;

create policy expense_groups_member_select on public.expense_groups
  for select to authenticated
  using (public.is_expense_group_member(expense_groups.id, (select auth.uid())));

create policy expense_group_members_member_select on public.expense_group_members
  for select to authenticated
  using (public.is_expense_group_member(expense_group_members.group_id, (select auth.uid())));

create policy group_expenses_member_select on public.group_expenses
  for select to authenticated
  using (public.is_expense_group_member(group_expenses.group_id, (select auth.uid())));

create policy group_expense_splits_member_select on public.group_expense_splits
  for select to authenticated
  using (public.is_expense_group_member(
    (select e.group_id from public.group_expenses e where e.id = group_expense_splits.expense_id),
    (select auth.uid())
  ));

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
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  select * into v_group from public.expense_groups
    where invite_code = upper(trim(coalesce(p_invite_code, '')));
  if not found then raise exception 'Mã tham gia nhóm không hợp lệ' using errcode = '22023'; end if;
  v_display_name := coalesce(nullif(trim((select display_name from public.profiles where user_id = v_user_id)), ''), 'Thành viên');
  insert into public.expense_group_members (group_id, user_id, display_name)
    values (v_group.id, v_user_id, v_display_name)
    on conflict (group_id, user_id) do nothing;
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
  if char_length(trim(coalesce(p_description, ''))) < 2 then raise exception 'Mô tả khoản chi quá ngắn' using errcode = '22023'; end if;
  if p_split_user_ids is null or cardinality(p_split_user_ids) < 1 then raise exception 'Hãy chọn ít nhất một thành viên' using errcode = '22023'; end if;
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
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  update public.group_expense_splits
    set settled_at = coalesce(settled_at, now())
    where expense_id = p_expense_id and user_id = v_user_id;
  if not found then raise exception 'Không tìm thấy phần chia của bạn' using errcode = '22023'; end if;
end;
$$;

revoke all on function public.create_expense_group(text) from public, anon;
revoke all on function public.join_expense_group(text) from public, anon;
revoke all on function public.create_group_expense(uuid, text, bigint, uuid[]) from public, anon;
revoke all on function public.settle_group_split(uuid) from public, anon;
grant execute on function public.create_expense_group(text) to authenticated;
grant execute on function public.join_expense_group(text) to authenticated;
grant execute on function public.create_group_expense(uuid, text, bigint, uuid[]) to authenticated;
grant execute on function public.settle_group_split(uuid) to authenticated;
