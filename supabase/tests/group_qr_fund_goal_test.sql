begin;
create extension if not exists pgtap with schema extensions;
select plan(21);

create function pg_temp.act_as(p_user uuid) returns void
language sql as $$
  select set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text,
    true
  );
$$;

-- A: trưởng nhóm, B: thành viên, C: thành viên ghi quỹ và trả bill, D: người ngoài
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000a1', 'owner@test.local'),
  ('00000000-0000-4000-8000-0000000000b2', 'member@test.local'),
  ('00000000-0000-4000-8000-0000000000c3', 'payer@test.local'),
  ('00000000-0000-4000-8000-0000000000d4', 'joiner@test.local');

insert into public.expense_groups (id, owner_id, name, invite_code) values
  ('10000000-0000-4000-8000-000000000001',
   '00000000-0000-4000-8000-0000000000a1', 'Nhóm test', 'ABCD1234');
insert into public.expense_group_members (group_id, user_id, display_name, role) values
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'A', 'owner'),
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000b2', 'B', 'member'),
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000c3', 'C', 'member');

-- Mục tiêu quỹ
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select lives_ok(
  $$select public.set_group_fund_goal('10000000-0000-4000-8000-000000000001', 500000, current_date + 30)$$,
  'trưởng nhóm đặt được mục tiêu và hạn'
);
select results_eq(
  $$select fund_goal_minor, fund_deadline from public.expense_groups where id = '10000000-0000-4000-8000-000000000001'$$,
  $$values (500000::bigint, current_date + 30)$$,
  'mục tiêu và hạn được lưu'
);
select lives_ok(
  $$select public.set_group_fund_goal('10000000-0000-4000-8000-000000000001', null, null)$$,
  'truyền null để xóa mục tiêu'
);
select results_eq(
  $$select fund_goal_minor, fund_deadline from public.expense_groups where id = '10000000-0000-4000-8000-000000000001'$$,
  $$values (null::bigint, null::date)$$,
  'xóa mục tiêu xóa luôn hạn'
);
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b2');
select throws_ok(
  $$select public.set_group_fund_goal('10000000-0000-4000-8000-000000000001', 500000, null)$$,
  'UF001', 'Chỉ trưởng nhóm được đặt mục tiêu quỹ',
  'thành viên thường không đặt được mục tiêu'
);
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select throws_ok(
  $$select public.set_group_fund_goal('10000000-0000-4000-8000-000000000001', 500000, current_date - 1)$$,
  'UF001', 'Hạn quỹ phải từ hôm nay trở đi',
  'hạn trong quá khứ bị từ chối'
);
select throws_ok(
  $$select public.set_group_fund_goal('10000000-0000-4000-8000-000000000001', 0, null)$$,
  'UF001', 'Mục tiêu quỹ không hợp lệ',
  'mục tiêu bằng 0 bị từ chối'
);
select throws_ok(
  $$update public.expense_groups set fund_deadline = current_date where id = '10000000-0000-4000-8000-000000000001'$$,
  '23514',
  'new row for relation "expense_groups" violates check constraint "expense_groups_fund_deadline_needs_goal"',
  'có hạn mà không có mục tiêu vi phạm constraint'
);

-- Giới hạn số lần tham gia nhóm
select pg_temp.act_as('00000000-0000-4000-8000-0000000000d4');
select is(
  (select count(*) from public.join_expense_group('FFFFFFFF')),
  0::bigint,
  'mã không tồn tại trả về 0 dòng thay vì lỗi'
);
do $$ begin
  for i in 1..9 loop perform public.join_expense_group('FFFFFFFF'); end loop;
end $$;
select is(
  (select attempt_count from public.expense_group_join_rate_limits
     where user_id = '00000000-0000-4000-8000-0000000000d4'),
  10,
  'mỗi lần nhập sai đều được đếm'
);
select throws_ok(
  $$select * from public.join_expense_group('FFFFFFFF')$$,
  'UF001', 'Bạn đã thử quá nhiều mã. Hãy thử lại sau một phút.',
  'lần thứ 11 trong một phút bị chặn'
);
update public.expense_group_join_rate_limits
  set window_started_at = now() - interval '2 minutes'
  where user_id = '00000000-0000-4000-8000-0000000000d4';
select is(
  (select count(*) from public.join_expense_group('abcd1234')),
  1::bigint,
  'mã đúng (chữ thường) tham gia được sau khi hết cửa sổ'
);
select is(
  (select attempt_count from public.expense_group_join_rate_limits
     where user_id = '00000000-0000-4000-8000-0000000000d4'),
  0,
  'tham gia thành công đặt lại bộ đếm'
);

-- Quỹ không đủ tiền
select pg_temp.act_as('00000000-0000-4000-8000-0000000000c3');
do $$ begin
  perform public.add_group_fund_entry('10000000-0000-4000-8000-000000000001', 'deposit', 100000, '');
  perform public.create_group_expense(
    '10000000-0000-4000-8000-000000000001', 'Ăn tối', 30000,
    array['00000000-0000-4000-8000-0000000000a1',
          '00000000-0000-4000-8000-0000000000b2',
          '00000000-0000-4000-8000-0000000000c3']::uuid[]
  );
end $$;
select throws_ok(
  $$select public.add_group_fund_entry('10000000-0000-4000-8000-000000000001', 'expense', 200000, 'Quá tay')$$,
  'UF001', 'Quỹ không đủ tiền cho khoản chi này',
  'chi quỹ vượt số dư trả về UF001'
);

-- Bill có người trả đã xóa tài khoản
update public.group_expenses set payer_id = null where description = 'Ăn tối';
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b2');
select throws_ok(
  format(
    $$select public.update_group_expense_custom(%L, 'Ăn tối', 30000, %L::jsonb)$$,
    (select id from public.group_expenses where description = 'Ăn tối'),
    '[{"user_id":"00000000-0000-4000-8000-0000000000a1","amount_minor":15000},{"user_id":"00000000-0000-4000-8000-0000000000b2","amount_minor":15000}]'
  ),
  '42501', 'Chỉ người trả hoặc chủ nhóm được sửa khoản chi',
  'thành viên thường không sửa được bill của người đã xóa tài khoản'
);
select throws_ok(
  format(
    $$select public.delete_group_expense(%L)$$,
    (select id from public.group_expenses where description = 'Ăn tối')
  ),
  '42501', 'Chỉ người trả hoặc chủ nhóm được xóa khoản chi',
  'thành viên thường không xóa được bill của người đã xóa tài khoản'
);
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select lives_ok(
  format(
    $$select public.update_group_expense_custom(%L, 'Ăn tối', 30000, %L::jsonb)$$,
    (select id from public.group_expenses where description = 'Ăn tối'),
    '[{"user_id":"00000000-0000-4000-8000-0000000000a1","amount_minor":15000},{"user_id":"00000000-0000-4000-8000-0000000000b2","amount_minor":15000}]'
  ),
  'trưởng nhóm sửa được bill của người đã xóa tài khoản'
);

-- Xóa tài khoản đã từng ghi quỹ
select lives_ok(
  $$delete from auth.users where id = '00000000-0000-4000-8000-0000000000c3'$$,
  'xóa user có dòng quỹ không bị chặn'
);
select is(
  (select actor_id from public.group_fund_entries
     where group_id = '10000000-0000-4000-8000-000000000001' and kind = 'deposit'),
  null::uuid,
  'actor_id của dòng quỹ thành null'
);
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b2');
select throws_ok(
  format(
    $$select public.delete_group_fund_entry(%L)$$,
    (select id from public.group_fund_entries
       where group_id = '10000000-0000-4000-8000-000000000001' and kind = 'deposit')
  ),
  '28000', 'Only creator or group owner can delete',
  'thành viên thường không xóa được dòng quỹ của tài khoản đã xóa'
);
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select lives_ok(
  format(
    $$select public.delete_group_fund_entry(%L)$$,
    (select id from public.group_fund_entries
       where group_id = '10000000-0000-4000-8000-000000000001' and kind = 'deposit')
  ),
  'trưởng nhóm xóa được dòng quỹ của tài khoản đã xóa'
);

select * from finish();
rollback;
