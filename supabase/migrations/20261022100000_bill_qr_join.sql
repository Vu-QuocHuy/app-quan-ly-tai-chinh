-- Spec B: QR mời vào bill cho người ngoài nhóm.
-- Người tham gia bill là người có dòng trong group_expense_splits. Người ngoài nhóm
-- chỉ đọc bill qua list_my_external_bills; RLS các bảng nhóm không đổi.

alter table public.group_expenses
  add column join_code text unique check (join_code ~ '^[0-9A-F]{10}$'),
  add column join_open boolean not null default false,
  add column split_mode text not null default 'custom'
    check (split_mode in ('equal', 'custom'));

alter table public.group_expense_splits
  add column participant_name text check (char_length(participant_name) <= 80),
  add column joined_at timestamptz not null default now();

alter table public.group_audit_events
  drop constraint if exists group_audit_events_event_type_check;

alter table public.group_audit_events
  add constraint group_audit_events_event_type_check check (
    event_type in (
      'group_created', 'member_joined', 'member_role_changed',
      'member_removed', 'member_left', 'expense_created', 'expense_settled',
      'expense_updated', 'expense_deleted', 'bill_joined', 'bill_left'
    )
  );

-- Chia đều lại toàn bộ split của bill; phần dư 1 đơn vị cho các split xếp đầu theo
-- (joined_at, user_id). Chỉ gọi từ RPC đã khóa bill và đã kiểm tra chưa ai thanh toán.
create function public.rebalance_equal_bill(p_expense_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_total bigint;
  v_count bigint;
begin
  select total_minor into v_total
    from public.group_expenses where id = p_expense_id;
  select count(*) into v_count
    from public.group_expense_splits where expense_id = p_expense_id;
  if v_total is null or v_count = 0 then
    return;
  end if;
  update public.group_expense_splits as splits
    set amount_minor = v_total / v_count
      + case when ranked.position <= v_total % v_count then 1 else 0 end
    from (
      select ctid as row_id,
        row_number() over (order by joined_at, user_id) as position
      from public.group_expense_splits
      where expense_id = p_expense_id
    ) as ranked
    where splits.ctid = ranked.row_id;
end;
$$;

revoke all on function public.rebalance_equal_bill(uuid) from public, anon, authenticated;

create function public.open_group_bill_invite(p_expense_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_expense public.group_expenses%rowtype;
  v_code text;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  select * into v_expense
    from public.group_expenses where id = p_expense_id for update;
  if v_expense.id is null or (
    v_user_id is distinct from v_expense.payer_id and not exists (
      select 1 from public.expense_groups
      where id = v_expense.group_id and owner_id = v_user_id
    )
  ) then
    raise exception 'Chỉ người trả hoặc trưởng nhóm được mời vào bill' using errcode = 'UF001';
  end if;
  if exists (
    select 1 from public.group_expense_splits
    where expense_id = p_expense_id and settled_at is not null
  ) then
    raise exception 'Bill đã có người thanh toán, không mời thêm được' using errcode = 'UF001';
  end if;
  v_code := v_expense.join_code;
  if v_code is null then
    loop
      v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
      exit when not exists (
        select 1 from public.group_expenses where join_code = v_code
      );
    end loop;
  end if;
  update public.group_expenses
    set join_code = v_code, join_open = true
    where id = p_expense_id;
  return v_code;
end;
$$;

create function public.close_group_bill_invite(p_expense_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_expense public.group_expenses%rowtype;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  select * into v_expense
    from public.group_expenses where id = p_expense_id for update;
  if v_expense.id is null or (
    v_user_id is distinct from v_expense.payer_id and not exists (
      select 1 from public.expense_groups
      where id = v_expense.group_id and owner_id = v_user_id
    )
  ) then
    raise exception 'Chỉ người trả hoặc trưởng nhóm được mời vào bill' using errcode = 'UF001';
  end if;
  update public.group_expenses set join_open = false where id = p_expense_id;
end;
$$;

-- Mã không tồn tại trả null thay vì raise, để lượt tăng attempt_count được commit.
create function public.join_group_bill(p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_code text := upper(trim(coalesce(p_code, '')));
  v_attempt_count integer;
  v_window_started_at timestamptz;
  v_expense public.group_expenses%rowtype;
  v_is_member boolean;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if v_code !~ '^[0-9A-F]{10}$' then
    raise exception 'Mã mời bill không hợp lệ' using errcode = '22023';
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

  select * into v_expense
    from public.group_expenses where join_code = v_code for update;
  if v_expense.id is null then
    return null;
  end if;
  if exists (
    select 1 from public.group_expense_splits
    where expense_id = v_expense.id and user_id = v_user_id
  ) then
    return v_expense.id;
  end if;
  if not v_expense.join_open then
    raise exception 'Bill này đã đóng lời mời' using errcode = 'UF001';
  end if;
  if exists (
    select 1 from public.group_expense_splits
    where expense_id = v_expense.id and settled_at is not null
  ) then
    raise exception 'Bill đã có người thanh toán, không mời thêm được' using errcode = 'UF001';
  end if;
  if (
    select count(*) from public.group_expense_splits where expense_id = v_expense.id
  ) >= 100 then
    raise exception 'Bill đã đủ 100 người' using errcode = 'UF001';
  end if;

  v_is_member := exists (
    select 1 from public.expense_group_members
    where group_id = v_expense.group_id and user_id = v_user_id
  );
  insert into public.group_expense_splits (
    expense_id, user_id, amount_minor, participant_name, joined_at
  )
  values (
    v_expense.id,
    v_user_id,
    0,
    case when v_is_member then null else left(coalesce(
      nullif(trim((select display_name from public.profiles where user_id = v_user_id)), ''),
      'Khách'
    ), 80) end,
    now()
  );
  if v_expense.split_mode = 'equal' then
    perform public.rebalance_equal_bill(v_expense.id);
  end if;
  insert into public.group_audit_events (
    group_id, actor_id, target_user_id, expense_id, event_type
  )
  values (v_expense.group_id, v_user_id, v_user_id, v_expense.id, 'bill_joined');
  return v_expense.id;
end;
$$;

create function public.leave_group_bill(p_expense_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_expense public.group_expenses%rowtype;
  v_amount bigint;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  select * into v_expense
    from public.group_expenses where id = p_expense_id for update;
  if v_expense.id is null or not exists (
    select 1 from public.group_expense_splits
    where expense_id = p_expense_id and user_id = v_user_id
  ) then
    raise exception 'Bạn không ở trong bill này' using errcode = 'UF001';
  end if;
  if v_expense.payer_id = v_user_id then
    raise exception 'Người trả không rời bill được' using errcode = 'UF001';
  end if;
  if exists (
    select 1 from public.group_expense_splits
    where expense_id = p_expense_id and settled_at is not null
  ) then
    raise exception 'Bill đã có người thanh toán, không rời được' using errcode = 'UF001';
  end if;
  if not exists (
    select 1 from public.group_expense_splits
    where expense_id = p_expense_id and user_id is distinct from v_user_id
  ) then
    raise exception 'Bill phải còn ít nhất một người' using errcode = 'UF001';
  end if;

  delete from public.group_expense_splits
    where expense_id = p_expense_id and user_id = v_user_id
    returning amount_minor into v_amount;
  if v_expense.split_mode = 'equal' then
    perform public.rebalance_equal_bill(p_expense_id);
  else
    -- Bill thủ công: phần của người rời về người trả, không có thì về split xếp đầu.
    update public.group_expense_splits
      set amount_minor = amount_minor + v_amount
      where ctid = (
        select ctid from public.group_expense_splits
        where expense_id = p_expense_id
        order by coalesce(user_id = v_expense.payer_id, false) desc, joined_at, user_id
        limit 1
      );
  end if;
  insert into public.group_audit_events (
    group_id, actor_id, target_user_id, expense_id, event_type
  )
  values (v_expense.group_id, v_user_id, v_user_id, p_expense_id, 'bill_left');
end;
$$;

-- Chỉ trả bill mà caller tham gia nhưng không là thành viên nhóm của bill.
-- Không trả group_id, tên nhóm hay user_id của người khác.
create function public.list_my_external_bills()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(item.bill order by item.created_at desc, item.id), '[]'::jsonb)
  from (
    select
      expenses.id,
      expenses.created_at,
      jsonb_build_object(
        'id', expenses.id,
        'description', expenses.description,
        'total_minor', expenses.total_minor,
        'created_at', expenses.created_at,
        'payer_name', coalesce(payer.display_name, 'Tài khoản đã xóa'),
        'is_open', expenses.join_open,
        'my_amount_minor', mine.amount_minor,
        'my_settled_at', mine.settled_at,
        'participants', (
          select coalesce(jsonb_agg(
            jsonb_build_object(
              'name', coalesce(
                nullif(splits.participant_name, ''),
                members.display_name,
                'Thành viên'
              ),
              'amount_minor', splits.amount_minor,
              'settled', splits.settled_at is not null,
              'is_me', coalesce(splits.user_id = (select auth.uid()), false)
            )
            order by splits.joined_at, splits.user_id
          ), '[]'::jsonb)
          from public.group_expense_splits as splits
          left join public.expense_group_members as members
            on members.group_id = expenses.group_id and members.user_id = splits.user_id
          where splits.expense_id = expenses.id
        )
      ) as bill
    from public.group_expense_splits as mine
    join public.group_expenses as expenses on expenses.id = mine.expense_id
    left join public.expense_group_members as payer
      on payer.group_id = expenses.group_id and payer.user_id = expenses.payer_id
    where mine.user_id = (select auth.uid())
      and not exists (
        select 1 from public.expense_group_members as own
        where own.group_id = expenses.group_id and own.user_id = (select auth.uid())
      )
    order by expenses.created_at desc, expenses.id
    limit 100
  ) as item;
$$;

revoke all on function public.open_group_bill_invite(uuid) from public, anon;
revoke all on function public.close_group_bill_invite(uuid) from public, anon;
revoke all on function public.join_group_bill(text) from public, anon;
revoke all on function public.leave_group_bill(uuid) from public, anon;
revoke all on function public.list_my_external_bills() from public, anon;
grant execute on function public.open_group_bill_invite(uuid) to authenticated;
grant execute on function public.close_group_bill_invite(uuid) to authenticated;
grant execute on function public.join_group_bill(text) to authenticated;
grant execute on function public.leave_group_bill(uuid) to authenticated;
grant execute on function public.list_my_external_bills() to authenticated;

-- Người tham gia bill (kể cả người ngoài nhóm) tự đánh dấu đã trả; bill tự đóng lời mời.
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
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select e.group_id into v_group_id
  from public.group_expenses e
  join public.group_expense_splits s
    on s.expense_id = e.id and s.user_id = v_user_id
  where e.id = p_expense_id
  for update of e;

  if v_group_id is null then
    raise exception 'Không tìm thấy phần chia của bạn' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.group_expense_splits
    where expense_id = p_expense_id and user_id = v_user_id and amount_minor = 0
  ) then
    raise exception 'Phần của bạn đang là 0đ, chờ người trả chia lại' using errcode = 'UF001';
  end if;

  update public.group_expense_splits
  set settled_at = now()
  where expense_id = p_expense_id
    and user_id = v_user_id
    and settled_at is null;

  if found then
    update public.group_expenses set join_open = false where id = p_expense_id;
    insert into public.group_audit_events (group_id, actor_id, expense_id, event_type)
      values (v_group_id, v_user_id, p_expense_id, 'expense_settled');
  end if;
end;
$$;

-- Bản 5 tham số: p_split_mode bắt buộc (default sẽ làm lời gọi 4 tham số mơ hồ).
-- Cho phép giữ người đã tham gia bill dù không là thành viên nhóm; giữ participant_name
-- và joined_at của split có sẵn.
create function public.update_group_expense_custom(
  p_expense_id uuid,
  p_description text,
  p_total_minor bigint,
  p_splits jsonb,
  p_split_mode text
)
returns void
language plpgsql
security definer
set search_path = ''
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
  if p_split_mode is null or p_split_mode not in ('equal', 'custom') then
    raise exception 'Cách chia không hợp lệ' using errcode = '22023';
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
       or not (
         public.is_expense_group_member(v_group_id, v_member_id)
         or exists (
           select 1 from public.group_expense_splits
           where expense_id = p_expense_id and user_id = v_member_id
         )
       ) then
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
    set description = trim(p_description),
        total_minor = p_total_minor,
        split_mode = p_split_mode
    where id = p_expense_id;
  delete from public.group_expense_splits
    where expense_id = p_expense_id
      and (user_id is null or user_id not in (
        select (value ->> 'user_id')::uuid from jsonb_array_elements(p_splits)
      ));
  for v_split in select value from jsonb_array_elements(p_splits) loop
    insert into public.group_expense_splits (expense_id, user_id, amount_minor)
      values (p_expense_id, (v_split ->> 'user_id')::uuid, (v_split ->> 'amount_minor')::bigint)
      on conflict (expense_id, user_id)
      do update set amount_minor = excluded.amount_minor;
  end loop;
  insert into public.group_audit_events (group_id, actor_id, expense_id, event_type, metadata)
    values (v_group_id, v_actor_id, p_expense_id, 'expense_updated', jsonb_build_object('total_minor', p_total_minor));
end;
$$;

revoke all on function public.update_group_expense_custom(uuid, text, bigint, jsonb, text)
  from public, anon;
grant execute on function public.update_group_expense_custom(uuid, text, bigint, jsonb, text)
  to authenticated;

-- Bản 4 tham số giữ chữ ký, search_path và grant cho app cũ; luôn lưu 'custom'.
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
begin
  -- Legacy clients omit guest splits; reject to prevent silent deletion.
  if exists (
    select 1 from public.group_expense_splits
    where expense_id = p_expense_id and participant_name is not null
  ) then
    raise exception 'Bill có khách tham gia; hãy cập nhật ứng dụng để sửa bill này'
      using errcode = 'UF001';
  end if;
  perform public.update_group_expense_custom(
    p_expense_id, p_description, p_total_minor, p_splits, 'custom'
  );
end;
$$;

-- Chỉ thêm split_mode = 'equal' khi tạo bill chia đều.
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
  insert into public.group_expenses (group_id, payer_id, description, total_minor, split_mode)
    values (p_group_id, v_user_id, trim(p_description), p_total_minor, 'equal')
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
    source_snapshot,
    split_mode
  )
  values (
    p_group_id,
    v_user_id,
    trim(p_description),
    p_total_minor,
    v_invoice_id,
    v_user_id,
    p_source_snapshot,
    'equal'
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
