begin;
create extension if not exists pgtap with schema extensions;
select plan(53);

create function pg_temp.act_as(p_user uuid) returns void
language sql as $$
  select set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text,
    true
  );
$$;

create function pg_temp.bill_id(p_description text) returns uuid
language sql as $$
  select id from public.group_expenses where description = p_description;
$$;

create function pg_temp.bill_code(p_description text) returns text
language sql as $$
  select join_code from public.group_expenses where description = p_description;
$$;

-- A: trưởng nhóm, B: thành viên trả bill, C: thành viên,
-- D: người ngoài có tên hồ sơ, E: người ngoài không có hồ sơ, F: người lạ
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000a1', 'owner@test.local'),
  ('00000000-0000-4000-8000-0000000000b2', 'payer@test.local'),
  ('00000000-0000-4000-8000-0000000000c3', 'member@test.local'),
  ('00000000-0000-4000-8000-0000000000d4', 'guest@test.local'),
  ('00000000-0000-4000-8000-0000000000e5', 'noname@test.local'),
  ('00000000-0000-4000-8000-0000000000f6', 'stranger@test.local');
-- Trigger handle_new_user đã tạo hồ sơ với tên rỗng.
update public.profiles set display_name = 'Dũng'
  where user_id = '00000000-0000-4000-8000-0000000000d4';

insert into public.expense_groups (id, owner_id, name, invite_code) values
  ('10000000-0000-4000-8000-000000000001',
   '00000000-0000-4000-8000-0000000000a1', 'Nhóm test', 'ABCD1234');
insert into public.expense_group_members (group_id, user_id, display_name, role) values
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'A', 'owner'),
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000b2', 'B', 'member'),
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000c3', 'C', 'member');

select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select public.add_group_fund_entry('10000000-0000-4000-8000-000000000001', 'deposit', 50000, '');

-- (12) Chế độ chia khi tạo bill
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b2');
select public.create_group_expense(
  '10000000-0000-4000-8000-000000000001', 'Ăn tối', 100001,
  array['00000000-0000-4000-8000-0000000000b2',
        '00000000-0000-4000-8000-0000000000c3']::uuid[]
);
select public.create_group_expense_custom(
  '10000000-0000-4000-8000-000000000001', 'Cà phê', 60000,
  '[{"user_id":"00000000-0000-4000-8000-0000000000b2","amount_minor":30000},
    {"user_id":"00000000-0000-4000-8000-0000000000c3","amount_minor":30000}]'::jsonb
);
select is(
  (select split_mode from public.group_expenses where id = pg_temp.bill_id('Ăn tối')),
  'equal',
  'create_group_expense đặt split_mode = equal'
);
select is(
  (select split_mode from public.group_expenses where id = pg_temp.bill_id('Cà phê')),
  'custom',
  'create_group_expense_custom giữ split_mode = custom'
);

-- (1) Ai mở được QR bill
select pg_temp.act_as('00000000-0000-4000-8000-0000000000c3');
select throws_ok(
  format($$select public.open_group_bill_invite(%L)$$, pg_temp.bill_id('Ăn tối')),
  'UF001', 'Chỉ người trả hoặc trưởng nhóm được mời vào bill',
  'thành viên thường không mở được QR bill'
);
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b2');
select matches(
  public.open_group_bill_invite(pg_temp.bill_id('Ăn tối')),
  '^[0-9A-F]{10}$',
  'người trả mở được QR bill, mã 10 ký tự hex in hoa'
);
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select matches(
  public.open_group_bill_invite(pg_temp.bill_id('Cà phê')),
  '^[0-9A-F]{10}$',
  'trưởng nhóm mở được QR bill của người khác'
);
select is(
  public.open_group_bill_invite(pg_temp.bill_id('Ăn tối')),
  pg_temp.bill_code('Ăn tối'),
  'mở lại giữ nguyên mã cũ'
);

-- (2) Người ngoài vào bill chia đều: chia lại, phần dư theo (joined_at, user_id)
update public.group_expense_splits
  set joined_at = now() + interval '1 minute'
  where expense_id = pg_temp.bill_id('Ăn tối')
    and user_id = '00000000-0000-4000-8000-0000000000b2';
select pg_temp.act_as('00000000-0000-4000-8000-0000000000d4');
select is(
  public.join_group_bill('  ' || lower(pg_temp.bill_code('Ăn tối')) || ' '),
  pg_temp.bill_id('Ăn tối'),
  'người ngoài vào bill bằng mã chữ thường có khoảng trắng'
);
select results_eq(
  format(
    $$select user_id, amount_minor from public.group_expense_splits
      where expense_id = %L order by user_id$$,
    pg_temp.bill_id('Ăn tối')
  ),
  $$values
    ('00000000-0000-4000-8000-0000000000b2'::uuid, 33333::bigint),
    ('00000000-0000-4000-8000-0000000000c3'::uuid, 33334::bigint),
    ('00000000-0000-4000-8000-0000000000d4'::uuid, 33334::bigint)$$,
  'bill chia đều chia lại cho 3 người, tổng 100001, B vào sau nên không nhận phần dư'
);
select results_eq(
  format(
    $$select user_id, participant_name from public.group_expense_splits
      where expense_id = %L order by user_id$$,
    pg_temp.bill_id('Ăn tối')
  ),
  $$values
    ('00000000-0000-4000-8000-0000000000b2'::uuid, null::text),
    ('00000000-0000-4000-8000-0000000000c3'::uuid, null::text),
    ('00000000-0000-4000-8000-0000000000d4'::uuid, 'Dũng'::text)$$,
  'participant_name là tên hồ sơ, chỉ điền cho người ngoài nhóm'
);

-- (3) Bill thủ công: người mới nhận 0đ
select pg_temp.act_as('00000000-0000-4000-8000-0000000000e5');
select is(
  public.join_group_bill(pg_temp.bill_code('Cà phê')),
  pg_temp.bill_id('Cà phê'),
  'người ngoài vào bill thủ công'
);
select results_eq(
  format(
    $$select user_id, amount_minor from public.group_expense_splits
      where expense_id = %L order by user_id$$,
    pg_temp.bill_id('Cà phê')
  ),
  $$values
    ('00000000-0000-4000-8000-0000000000b2'::uuid, 30000::bigint),
    ('00000000-0000-4000-8000-0000000000c3'::uuid, 30000::bigint),
    ('00000000-0000-4000-8000-0000000000e5'::uuid, 0::bigint)$$,
  'bill thủ công: người mới 0đ, split khác giữ nguyên'
);
select is(
  (select participant_name from public.group_expense_splits
     where expense_id = pg_temp.bill_id('Cà phê')
       and user_id = '00000000-0000-4000-8000-0000000000e5'),
  'Khách',
  'không có tên hồ sơ thì participant_name là Khách'
);

-- (4) Vào lần hai không đổi gì
select pg_temp.act_as('00000000-0000-4000-8000-0000000000d4');
select is(
  public.join_group_bill(pg_temp.bill_code('Ăn tối')),
  pg_temp.bill_id('Ăn tối'),
  'vào lần hai trả cùng expense_id'
);
select is(
  (select count(*) from public.group_expense_splits where expense_id = pg_temp.bill_id('Ăn tối')),
  3::bigint,
  'vào lần hai không thêm split'
);

-- (7) Mã sai và giới hạn số lần thử
select pg_temp.act_as('00000000-0000-4000-8000-0000000000f6');
select ok(
  public.join_group_bill('FFFFFFFFFF') is null,
  'mã không tồn tại trả null thay vì lỗi'
);
do $$ begin
  for i in 1..9 loop perform public.join_group_bill('FFFFFFFFFF'); end loop;
end $$;
select is(
  (select attempt_count from public.expense_group_join_rate_limits
     where user_id = '00000000-0000-4000-8000-0000000000f6'),
  10,
  'mỗi lần nhập mã bill sai đều được đếm'
);
select throws_ok(
  $$select public.join_group_bill('FFFFFFFFFF')$$,
  'UF001', 'Bạn đã thử quá nhiều mã. Hãy thử lại sau một phút.',
  'lần thứ 11 trong một phút bị chặn'
);
select throws_ok(
  $$select public.join_group_bill('ABC')$$,
  '22023', 'Mã mời bill không hợp lệ',
  'mã sai định dạng bị từ chối'
);
update public.expense_group_join_rate_limits
  set window_started_at = now() - interval '2 minutes'
  where user_id = '00000000-0000-4000-8000-0000000000f6';

-- (5) Đóng lời mời
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select lives_ok(
  format($$select public.close_group_bill_invite(%L)$$, pg_temp.bill_id('Cà phê')),
  'trưởng nhóm đóng được lời mời bill'
);
select pg_temp.act_as('00000000-0000-4000-8000-0000000000f6');
select throws_ok(
  format($$select public.join_group_bill(%L)$$, pg_temp.bill_code('Cà phê')),
  'UF001', 'Bill này đã đóng lời mời',
  'không vào được bill đã đóng lời mời'
);
select pg_temp.act_as('00000000-0000-4000-8000-0000000000c3');
select throws_ok(
  format($$select public.close_group_bill_invite(%L)$$, pg_temp.bill_id('Ăn tối')),
  'UF001', 'Chỉ người trả hoặc trưởng nhóm được mời vào bill',
  'thành viên thường không đóng được lời mời'
);

-- (8) Người ngoài không đọc được bảng của nhóm
select pg_temp.act_as('00000000-0000-4000-8000-0000000000d4');
set local role authenticated;
select is((select count(*) from public.group_expenses), 0::bigint,
  'người ngoài không đọc được group_expenses');
select is((select count(*) from public.group_expense_splits), 0::bigint,
  'người ngoài không đọc được group_expense_splits, kể cả split của mình');
select is((select count(*) from public.expense_group_members), 0::bigint,
  'người ngoài không đọc được expense_group_members');
select is((select count(*) from public.group_fund_entries), 0::bigint,
  'người ngoài không đọc được group_fund_entries');
reset role;

-- (9) list_my_external_bills
select pg_temp.act_as('00000000-0000-4000-8000-0000000000d4');
select is(
  jsonb_array_length(public.list_my_external_bills()),
  1,
  'người ngoài thấy đúng một bill đã vào'
);
select ok(
  (public.list_my_external_bills() -> 0 ->> 'id')::uuid = pg_temp.bill_id('Ăn tối')
    and not (public.list_my_external_bills() -> 0 ? 'group_id')
    and not exists (
      select 1
      from jsonb_array_elements(public.list_my_external_bills() -> 0 -> 'participants') as p
      where p ? 'user_id'
    ),
  'bill trả về đúng id, không có group_id hay user_id'
);
select is(
  (public.list_my_external_bills() -> 0 ->> 'my_amount_minor')::bigint,
  33334::bigint,
  'my_amount_minor là phần của người ngoài'
);
select is(
  (select string_agg(p ->> 'name', ',' order by p ->> 'name')
     from jsonb_array_elements(public.list_my_external_bills() -> 0 -> 'participants') as p),
  'B,C,Dũng',
  'tên người tham gia lấy từ tên thành viên và participant_name'
);
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b2');
select is(
  public.list_my_external_bills(),
  '[]'::jsonb,
  'thành viên nhóm không thấy bill của nhóm mình trong danh sách người ngoài'
);

-- (10) Rời bill chia đều: chia lại; người trả không rời được
select pg_temp.act_as('00000000-0000-4000-8000-0000000000e5');
select is(
  public.join_group_bill(pg_temp.bill_code('Ăn tối')),
  pg_temp.bill_id('Ăn tối'),
  'người ngoài thứ hai vào bill chia đều'
);
select lives_ok(
  format($$select public.leave_group_bill(%L)$$, pg_temp.bill_id('Ăn tối')),
  'người ngoài rời bill khi chưa ai thanh toán'
);
select results_eq(
  format(
    $$select user_id, amount_minor from public.group_expense_splits
      where expense_id = %L order by user_id$$,
    pg_temp.bill_id('Ăn tối')
  ),
  $$values
    ('00000000-0000-4000-8000-0000000000b2'::uuid, 33333::bigint),
    ('00000000-0000-4000-8000-0000000000c3'::uuid, 33334::bigint),
    ('00000000-0000-4000-8000-0000000000d4'::uuid, 33334::bigint)$$,
  'rời bill chia đều: split bị xóa, bill chia lại'
);
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b2');
select throws_ok(
  format($$select public.leave_group_bill(%L)$$, pg_temp.bill_id('Ăn tối')),
  'UF001', 'Người trả không rời bill được',
  'người trả không rời bill được'
);

-- (11) Sửa bill có người ngoài
select lives_ok(
  format(
    $$select public.update_group_expense_custom(%L, 'Cà phê', 60000, %L::jsonb, 'custom')$$,
    pg_temp.bill_id('Cà phê'),
    '[{"user_id":"00000000-0000-4000-8000-0000000000b2","amount_minor":20000},
      {"user_id":"00000000-0000-4000-8000-0000000000c3","amount_minor":20000},
      {"user_id":"00000000-0000-4000-8000-0000000000e5","amount_minor":20000}]'
  ),
  'sửa bill giữ người ngoài đã tham gia'
);
select is(
  (select participant_name from public.group_expense_splits
     where expense_id = pg_temp.bill_id('Cà phê')
       and user_id = '00000000-0000-4000-8000-0000000000e5'),
  'Khách',
  'sửa bill giữ participant_name của người ngoài'
);
select throws_ok(
  format(
    $$select public.update_group_expense_custom(%L, 'Cà phê', 60000, %L::jsonb, 'custom')$$,
    pg_temp.bill_id('Cà phê'),
    '[{"user_id":"00000000-0000-4000-8000-0000000000b2","amount_minor":30000},
      {"user_id":"00000000-0000-4000-8000-0000000000f6","amount_minor":30000}]'
  ),
  '22023', 'Phần chia tiền không hợp lệ',
  'không thêm được người lạ không thuộc nhóm và chưa vào bill'
);
select throws_ok(
  format(
    $$select public.update_group_expense_custom(%L, 'Cà phê', 60000, %L::jsonb, 'weird')$$,
    pg_temp.bill_id('Cà phê'),
    '[{"user_id":"00000000-0000-4000-8000-0000000000b2","amount_minor":60000}]'
  ),
  '22023', 'Cách chia không hợp lệ',
  'p_split_mode ngoài equal/custom bị từ chối'
);
select pg_temp.act_as('00000000-0000-4000-8000-0000000000e5');
select lives_ok(
  format($$select public.leave_group_bill(%L)$$, pg_temp.bill_id('Cà phê')),
  'người ngoài rời bill thủ công'
);
select results_eq(
  format(
    $$select user_id, amount_minor from public.group_expense_splits
      where expense_id = %L order by user_id$$,
    pg_temp.bill_id('Cà phê')
  ),
  $$values
    ('00000000-0000-4000-8000-0000000000b2'::uuid, 40000::bigint),
    ('00000000-0000-4000-8000-0000000000c3'::uuid, 20000::bigint)$$,
  'rời bill thủ công: phần tiền về người trả, tổng không đổi'
);
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b2');
select lives_ok(
  format(
    $$select public.update_group_expense_custom(%L, 'Cà phê', 60000, %L::jsonb, 'equal')$$,
    pg_temp.bill_id('Cà phê'),
    '[{"user_id":"00000000-0000-4000-8000-0000000000b2","amount_minor":30000},
      {"user_id":"00000000-0000-4000-8000-0000000000c3","amount_minor":30000}]'
  ),
  'sửa bill với p_split_mode = equal'
);
select is(
  (select split_mode from public.group_expenses where id = pg_temp.bill_id('Cà phê')),
  'equal',
  'p_split_mode = equal được lưu vào bill'
);
select lives_ok(
  format(
    $$select public.update_group_expense_custom(%L, 'Cà phê', 60000, %L::jsonb)$$,
    pg_temp.bill_id('Cà phê'),
    '[{"user_id":"00000000-0000-4000-8000-0000000000b2","amount_minor":30000},
      {"user_id":"00000000-0000-4000-8000-0000000000c3","amount_minor":30000}]'
  ),
  'bản 4 tham số của app cũ vẫn sửa được bill'
);
select is(
  (select split_mode from public.group_expenses where id = pg_temp.bill_id('Cà phê')),
  'custom',
  'bản 4 tham số lưu split_mode = custom'
);

-- Bill mà người trả không có split: không rời được khi chỉ còn một người
select public.create_group_expense_custom(
  '10000000-0000-4000-8000-000000000001', 'Taxi', 50000,
  '[{"user_id":"00000000-0000-4000-8000-0000000000c3","amount_minor":50000}]'::jsonb
);
select pg_temp.act_as('00000000-0000-4000-8000-0000000000c3');
select throws_ok(
  format($$select public.leave_group_bill(%L)$$, pg_temp.bill_id('Taxi')),
  'UF001', 'Bill phải còn ít nhất một người',
  'người cuối cùng không rời bill được'
);

-- (6) + (10) Người ngoài thanh toán: bill tự đóng lời mời
select pg_temp.act_as('00000000-0000-4000-8000-0000000000d4');
select lives_ok(
  format($$select public.settle_group_split(%L)$$, pg_temp.bill_id('Ăn tối')),
  'người ngoài nhóm đánh dấu đã thanh toán được'
);
select is(
  (select join_open from public.group_expenses where id = pg_temp.bill_id('Ăn tối')),
  false,
  'có người thanh toán thì bill tự đóng lời mời'
);
select pg_temp.act_as('00000000-0000-4000-8000-0000000000f6');
select throws_ok(
  format($$select public.join_group_bill(%L)$$, pg_temp.bill_code('Ăn tối')),
  'UF001', 'Bill này đã đóng lời mời',
  'không vào được bill đã có người thanh toán'
);
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b2');
select throws_ok(
  format($$select public.open_group_bill_invite(%L)$$, pg_temp.bill_id('Ăn tối')),
  'UF001', 'Bill đã có người thanh toán, không mời thêm được',
  'không mở lại lời mời khi đã có người thanh toán'
);
select pg_temp.act_as('00000000-0000-4000-8000-0000000000c3');
select throws_ok(
  format($$select public.leave_group_bill(%L)$$, pg_temp.bill_id('Ăn tối')),
  'UF001', 'Bill đã có người thanh toán, không rời được',
  'không rời bill khi đã có người thanh toán'
);

-- Khách vào bill custom có phần 0đ: không đánh dấu đã thanh toán được, bill không bị đóng
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b2');
select public.create_group_expense_custom(
  '10000000-0000-4000-8000-000000000001', 'Bánh', 40000,
  '[{"user_id":"00000000-0000-4000-8000-0000000000b2","amount_minor":40000}]'::jsonb
);
select public.open_group_bill_invite(pg_temp.bill_id('Bánh'));
select pg_temp.act_as('00000000-0000-4000-8000-0000000000e5');
select public.join_group_bill(pg_temp.bill_code('Bánh'));
select throws_ok(
  format($$select public.settle_group_split(%L)$$, pg_temp.bill_id('Bánh')),
  'UF001', 'Phần của bạn đang là 0đ, chờ người trả chia lại',
  'phần 0đ không đánh dấu đã thanh toán được'
);
select is(
  (select join_open from public.group_expenses where id = pg_temp.bill_id('Bánh')),
  true,
  'bill vẫn mở lời mời sau khi bị từ chối'
);

-- Nhật ký nhóm ghi lại người vào và rời bill
select results_eq(
  $$select event_type, count(*) from public.group_audit_events
    where event_type in ('bill_joined', 'bill_left')
      and actor_id = target_user_id
    group by event_type order by event_type$$,
  $$values ('bill_joined'::text, 4::bigint), ('bill_left'::text, 2::bigint)$$,
  'audit ghi bill_joined và bill_left với actor là người vào/rời'
);

select * from finish();
rollback;
