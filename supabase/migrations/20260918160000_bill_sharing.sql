-- Share a safe invoice snapshot without exposing the owner's private invoice.
-- Team shares reuse the existing group expense settlement/balance model.

alter table public.group_expenses
  add column if not exists source_invoice_id text,
  add column if not exists source_owner_id uuid references auth.users(id) on delete set null,
  add column if not exists source_snapshot jsonb;

create index if not exists group_expenses_source_invoice_idx
  on public.group_expenses (source_owner_id, source_invoice_id)
  where source_invoice_id is not null;

create or replace function public.create_group_expense_from_invoice(
  p_group_id uuid,
  p_description text,
  p_total_minor bigint,
  p_split_user_ids uuid[],
  p_source_invoice_id text,
  p_source_snapshot jsonb
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
  v_invoice_id text := trim(coalesce(p_source_invoice_id, ''));
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
  if char_length(v_invoice_id) < 1 or char_length(v_invoice_id) > 128 then
    raise exception 'Mã hóa đơn nguồn không hợp lệ' using errcode = '22023';
  end if;
  if p_source_snapshot is null or jsonb_typeof(p_source_snapshot) <> 'object'
     or pg_column_size(p_source_snapshot) > 65536 then
    raise exception 'Dữ liệu hóa đơn chia sẻ không hợp lệ' using errcode = '22023';
  end if;
  if p_split_user_ids is null or cardinality(p_split_user_ids) < 1
     or cardinality(p_split_user_ids) > 100 then
    raise exception 'Danh sách thành viên không hợp lệ' using errcode = '22023';
  end if;
  select count(*) into v_count from unnest(p_split_user_ids);
  if v_count <> (select count(distinct item) from unnest(p_split_user_ids) as item) then
    raise exception 'Danh sách thành viên bị trùng' using errcode = '22023';
  end if;
  if exists (
    select 1
    from unnest(p_split_user_ids) as item
    where not exists (
      select 1 from public.expense_group_members as members
      where members.group_id = p_group_id and members.user_id = item
    )
  ) then
    raise exception 'Có thành viên không thuộc nhóm' using errcode = '42501';
  end if;

  insert into public.group_expenses (
    group_id,
    payer_id,
    description,
    total_minor,
    source_invoice_id,
    source_owner_id,
    source_snapshot
  )
  values (
    p_group_id,
    v_user_id,
    trim(p_description),
    p_total_minor,
    v_invoice_id,
    v_user_id,
    p_source_snapshot
  )
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
  insert into public.group_audit_events (
    group_id,
    actor_id,
    expense_id,
    event_type,
    metadata
  )
  values (
    p_group_id,
    v_user_id,
    v_expense_id,
    'expense_created',
    jsonb_build_object('total_minor', p_total_minor, 'source', 'invoice_share')
  );
  return v_expense_id;
end;
$$;

create or replace function public.create_group_expense_custom_from_invoice(
  p_group_id uuid,
  p_description text,
  p_total_minor bigint,
  p_splits jsonb,
  p_source_invoice_id text,
  p_source_snapshot jsonb
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
  v_invoice_id text := trim(coalesce(p_source_invoice_id, ''));
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
  if char_length(v_invoice_id) < 1 or char_length(v_invoice_id) > 128 then
    raise exception 'Mã hóa đơn nguồn không hợp lệ' using errcode = '22023';
  end if;
  if p_source_snapshot is null or jsonb_typeof(p_source_snapshot) <> 'object'
     or pg_column_size(p_source_snapshot) > 65536 then
    raise exception 'Dữ liệu hóa đơn chia sẻ không hợp lệ' using errcode = '22023';
  end if;
  if p_splits is null or jsonb_typeof(p_splits) <> 'array'
     or jsonb_array_length(p_splits) < 1
     or jsonb_array_length(p_splits) > 100 then
    raise exception 'Danh sách chia tiền không hợp lệ' using errcode = '22023';
  end if;
  for v_split in select value from jsonb_array_elements(p_splits) loop
    if jsonb_typeof(v_split) <> 'object'
       or coalesce(v_split ->> 'user_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or coalesce(v_split ->> 'amount_minor', '') !~ '^[0-9]{1,19}$' then
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

  insert into public.group_expenses (
    group_id,
    payer_id,
    description,
    total_minor,
    source_invoice_id,
    source_owner_id,
    source_snapshot
  )
  values (
    p_group_id,
    v_user_id,
    trim(p_description),
    p_total_minor,
    v_invoice_id,
    v_user_id,
    p_source_snapshot
  )
  returning id into v_expense_id;
  for v_split in select value from jsonb_array_elements(p_splits) loop
    insert into public.group_expense_splits (expense_id, user_id, amount_minor)
      values (
        v_expense_id,
        (v_split ->> 'user_id')::uuid,
        (v_split ->> 'amount_minor')::bigint
      );
  end loop;
  insert into public.group_audit_events (
    group_id,
    actor_id,
    expense_id,
    event_type,
    metadata
  )
  values (
    p_group_id,
    v_user_id,
    v_expense_id,
    'expense_created',
    jsonb_build_object('total_minor', p_total_minor, 'source', 'invoice_share')
  );
  return v_expense_id;
end;
$$;

revoke all on function public.create_group_expense_from_invoice(
  uuid, text, bigint, uuid[], text, jsonb
) from public, anon;
revoke all on function public.create_group_expense_custom_from_invoice(
  uuid, text, bigint, jsonb, text, jsonb
) from public, anon;
grant execute on function public.create_group_expense_from_invoice(
  uuid, text, bigint, uuid[], text, jsonb
) to authenticated;
grant execute on function public.create_group_expense_custom_from_invoice(
  uuid, text, bigint, jsonb, text, jsonb
) to authenticated;

create table public.direct_bill_shares (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid references auth.users(id) on delete set null,
  recipient_email text not null check (
    char_length(recipient_email) between 3 and 320
    and recipient_email = lower(trim(recipient_email))
  ),
  source_invoice_id text not null check (char_length(trim(source_invoice_id)) between 1 and 128),
  source_snapshot jsonb not null check (jsonb_typeof(source_snapshot) = 'object'),
  total_minor bigint not null check (total_minor > 0),
  owner_amount_minor bigint not null check (owner_amount_minor >= 0),
  recipient_amount_minor bigint not null check (recipient_amount_minor >= 0),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'revoked')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  accepted_at timestamptz,
  check (owner_amount_minor + recipient_amount_minor = total_minor),
  check (pg_column_size(source_snapshot) <= 65536)
);

create index direct_bill_shares_owner_idx
  on public.direct_bill_shares (owner_id, created_at desc);
create index direct_bill_shares_recipient_idx
  on public.direct_bill_shares (recipient_id, status, created_at desc);
create index direct_bill_shares_email_idx
  on public.direct_bill_shares (recipient_email, status, created_at desc);

alter table public.direct_bill_shares enable row level security;
revoke all on table public.direct_bill_shares from public, anon, authenticated;

create or replace function public.create_direct_bill_share(
  p_recipient_email text,
  p_source_invoice_id text,
  p_total_minor bigint,
  p_recipient_amount_minor bigint,
  p_source_snapshot jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_email text := lower(trim(coalesce(p_recipient_email, '')));
  v_recipient_id uuid;
  v_share_id uuid;
  v_invoice_id text := trim(coalesce(p_source_invoice_id, ''));
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if v_email !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Email người nhận không hợp lệ' using errcode = '22023';
  end if;
  if lower(coalesce((select email from auth.users where id = v_user_id), '')) = v_email then
    raise exception 'Không thể chia sẻ hóa đơn cho chính mình' using errcode = '22023';
  end if;
  if char_length(v_invoice_id) < 1 or char_length(v_invoice_id) > 128 then
    raise exception 'Mã hóa đơn nguồn không hợp lệ' using errcode = '22023';
  end if;
  if p_total_minor is null or p_total_minor <= 0
     or p_recipient_amount_minor is null
     or p_recipient_amount_minor < 0
     or p_recipient_amount_minor > p_total_minor then
    raise exception 'Phần tiền người nhận không hợp lệ' using errcode = '22023';
  end if;
  if p_source_snapshot is null or jsonb_typeof(p_source_snapshot) <> 'object'
     or pg_column_size(p_source_snapshot) > 65536 then
    raise exception 'Dữ liệu hóa đơn chia sẻ không hợp lệ' using errcode = '22023';
  end if;
  select id into v_recipient_id
  from auth.users
  where lower(email) = v_email
  limit 1;

  insert into public.direct_bill_shares (
    owner_id,
    recipient_id,
    recipient_email,
    source_invoice_id,
    source_snapshot,
    total_minor,
    owner_amount_minor,
    recipient_amount_minor
  )
  values (
    v_user_id,
    v_recipient_id,
    v_email,
    v_invoice_id,
    p_source_snapshot,
    p_total_minor,
    p_total_minor - p_recipient_amount_minor,
    p_recipient_amount_minor
  )
  returning id into v_share_id;
  return v_share_id;
end;
$$;

create or replace function public.list_direct_bill_shares()
returns table (
  id uuid,
  owner_id uuid,
  recipient_id uuid,
  recipient_email text,
  source_invoice_id text,
  source_snapshot jsonb,
  total_minor bigint,
  owner_amount_minor bigint,
  recipient_amount_minor bigint,
  status text,
  created_at timestamptz,
  updated_at timestamptz,
  accepted_at timestamptz
)
language sql
security definer
set search_path = public, pg_temp
as $$
  select
    shares.id,
    shares.owner_id,
    shares.recipient_id,
    shares.recipient_email,
    shares.source_invoice_id,
    shares.source_snapshot,
    shares.total_minor,
    shares.owner_amount_minor,
    shares.recipient_amount_minor,
    shares.status,
    shares.created_at,
    shares.updated_at,
    shares.accepted_at
  from public.direct_bill_shares as shares
  where shares.owner_id = (select auth.uid())
     or shares.recipient_id = (select auth.uid())
     or (
       shares.recipient_id is null
       and shares.recipient_email = lower(coalesce(
         (select email from auth.users where id = (select auth.uid())),
         ''
       ))
     )
  order by shares.created_at desc;
$$;

create or replace function public.respond_direct_bill_share(
  p_share_id uuid,
  p_action text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_email text := lower(coalesce(
    (select email from auth.users where id = (select auth.uid())),
    ''
  ));
  v_share public.direct_bill_shares%rowtype;
  v_action text := lower(trim(coalesce(p_action, '')));
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  select * into v_share
  from public.direct_bill_shares
  where id = p_share_id;
  if not found then
    raise exception 'Không tìm thấy hóa đơn được chia sẻ' using errcode = 'P0002';
  end if;
  if v_action = 'revoke' then
    if v_share.owner_id <> v_user_id then
      raise exception 'Bạn không có quyền thu hồi chia sẻ này' using errcode = '42501';
    end if;
    update public.direct_bill_shares
    set status = 'revoked', updated_at = now()
    where id = p_share_id and status <> 'revoked';
    return;
  end if;
  if v_action not in ('accept', 'decline') then
    raise exception 'Hành động chia sẻ không hợp lệ' using errcode = '22023';
  end if;
  if v_share.owner_id = v_user_id
     or not (
       v_share.recipient_id = v_user_id
       or (v_share.recipient_id is null and v_share.recipient_email = v_email)
     ) then
    raise exception 'Bạn không phải người nhận hóa đơn này' using errcode = '42501';
  end if;
  if v_share.status <> 'pending' then
    raise exception 'Chia sẻ này đã được xử lý' using errcode = '22023';
  end if;
  update public.direct_bill_shares
  set
    recipient_id = v_user_id,
    status = case when v_action = 'accept' then 'accepted' else 'declined' end,
    accepted_at = case when v_action = 'accept' then now() else null end,
    updated_at = now()
  where id = p_share_id;
end;
$$;

revoke all on function public.create_direct_bill_share(text, text, bigint, bigint, jsonb)
  from public, anon;
revoke all on function public.list_direct_bill_shares()
  from public, anon;
revoke all on function public.respond_direct_bill_share(uuid, text)
  from public, anon;
grant execute on function public.create_direct_bill_share(text, text, bigint, bigint, jsonb)
  to authenticated;
grant execute on function public.list_direct_bill_shares()
  to authenticated;
grant execute on function public.respond_direct_bill_share(uuid, text)
  to authenticated;

