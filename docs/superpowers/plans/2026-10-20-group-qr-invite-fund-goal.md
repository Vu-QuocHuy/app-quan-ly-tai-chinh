# QR mời nhóm, mục tiêu quỹ, nút "Chia tiền" hai tab — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thêm QR mời vào nhóm, mục tiêu/hạn cho quỹ nhóm, một nút "Chia tiền" mở dialog hai tab "Nhập thủ công" / "Quét hóa đơn" (quét chỉ điền sẵn nội dung và tổng tiền, tách khỏi thu chi của quỹ), và sửa bốn lỗi có sẵn ở RPC nhóm/quỹ.

**Architecture:** Một migration Supabase thêm cột mục tiêu quỹ, RPC `set_group_fund_goal`, mã lỗi `UF001` cho thông báo người dùng, và `create or replace` năm RPC có sẵn. Phía Flutter thêm hai hàm thuần (`InviteLink`, `GroupFundProgress`), mở rộng `ExpenseGroupService`, tách biểu mẫu chia tiền ra file riêng và thêm dialog "Chia tiền" hai tab, thêm màn quét QR dùng chung, bottom sheet QR mời và thẻ tiến độ quỹ.

**Tech Stack:** Flutter 3.47.1 / Dart ^3.12, Riverpod, `supabase_flutter`, `mobile_scanner` 7.4.2 (đã có), `qr_flutter` ^4.1.0 (mới), PostgreSQL / Supabase, pgTAP qua `supabase test db`.

**Spec:** `docs/superpowers/specs/2026-10-20-group-qr-invite-fund-goal-design.md`

## Global Constraints

- Flutter `3.47.1` (file `.fvmrc`), Dart `^3.12.0`. Máy hiện tại chưa cài Flutter: cài trước khi chạy task Flutter (`fvm install 3.47.1` hoặc clone `flutter` tag `3.47.1`).
- Chỉ thêm một dependency: `qr_flutter: ^4.1.0`.
- Tiền luôn là `int` đơn vị nhỏ nhất; giới hạn trên `9007199254740991`.
- Mọi chữ hiển thị bằng tiếng Việt; dùng "trưởng nhóm" trong thông điệp mới.
- Lỗi người dùng đọc được dùng SQLSTATE `UF001` với thông điệp tiếng Việt; lỗi kỹ thuật giữ mã cũ.
- Migration duy nhất: `supabase/migrations/20261021100000_group_qr_fund_goal.sql`. Không sửa migration cũ.
- Hàm SQL mới: `security definer`, `set search_path = ''`, `revoke all ... from public, anon`, `grant execute ... to authenticated`. Hàm `create or replace` giữ nguyên chữ ký và `search_path` của bản gốc.
- QR mời chứa đúng `hoadoninsight://join-group?code=<CODE>`; mã hợp lệ khớp `^[0-9A-F]{8}$` sau khi uppercase.
- Trước mỗi commit Flutter: `dart format lib test` không đổi file, `flutter analyze` sạch (CI fail khi có cảnh báo).
- Commit message kết thúc bằng dòng `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. OCR không đọc được tổng tiền (`totalMinor == 0`) → ô "Tổng tiền" để trống, không điền "0" (Task 6).
2. Tên người bán dài khiến mô tả vượt 160 ký tự → mô tả điền sẵn bị cắt còn 160 ký tự, không bị server từ chối (Task 6).
6. Đọc hóa đơn lỗi (mất mạng, AI chưa cấu hình) hoặc người dùng huỷ chọn ảnh → dialog "Chia tiền" không đóng, chữ đã nhập ở tab "Nhập thủ công" còn nguyên; lỗi hiện trong tab Quét (Task 7).
3. QR chứa mã chữ thường, có khoảng trắng hoặc là mã trơn không phải URI → vẫn tham gia được; QR của VietQR hoặc URL lạ → báo "không phải mã mời", không gọi server (Task 3).
4. Số dư quỹ vượt mục tiêu → thẻ hiện "150%" và thanh tiến độ đầy, không lỗi giá trị ngoài 0..1 (Task 9).
5. Thành viên không phải trưởng nhóm → không thấy nút đặt/sửa mục tiêu; server vẫn chặn nếu gọi thẳng (Task 9, Task 1).

## File Structure

| File | Trách nhiệm |
|---|---|
| `supabase/migrations/20261021100000_group_qr_fund_goal.sql` (mới) | Cột mục tiêu quỹ, sửa FK `actor_id`, `set_group_fund_goal`, sửa 5 RPC |
| `supabase/tests/group_qr_fund_goal_test.sql` (mới) | pgTAP cho migration |
| `lib/shared/errors/error_presenter.dart` | Hiện nguyên câu `UF001` |
| `lib/features/groups/domain/invite_link.dart` (mới) | Parse/sinh link mời |
| `lib/features/groups/domain/group_fund_progress.dart` (mới) | Tính trạng thái tiến độ quỹ |
| `lib/features/groups/domain/group_models.dart` | `ExpenseGroup` thêm mục tiêu; `GroupFundEntry.actorId` nullable |
| `lib/features/groups/data/group_service.dart` | Đọc cột mới, `setFundGoal`, câu lỗi join |
| `lib/features/groups/presentation/group_expense_dialog.dart` (mới) | Biểu mẫu chia tiền dùng chung `GroupExpenseForm` (tách từ `group_screen.dart`) + điền sẵn; dialog sửa |
| `lib/features/groups/presentation/group_split_dialog.dart` (mới) | Dialog "Chia tiền" hai tab Nhập thủ công / Quét hóa đơn |
| `lib/features/groups/presentation/group_invite_qr_sheet.dart` (mới) | Bottom sheet QR mời |
| `lib/features/groups/presentation/fund_progress_card.dart` (mới) | Thẻ tiến độ quỹ |
| `lib/shared/widgets/qr_scan_screen.dart` (mới) | Màn quét QR dùng chung |
| `lib/features/groups/presentation/group_screen.dart` | Nối các phần trên; một nút "Chia tiền"; xóa dialog gán dòng hóa đơn |
| `lib/features/groups/presentation/group_fund_screen.dart` | Thẻ tiến độ, dialog mục tiêu, nhãn tài khoản đã xóa |

---

### Task 1: Migration và pgTAP

**Files:**
- Create: `supabase/migrations/20261021100000_group_qr_fund_goal.sql`
- Create: `supabase/tests/group_qr_fund_goal_test.sql`

**Interfaces:**
- Consumes: bảng/RPC có sẵn `expense_groups`, `expense_group_members`, `group_expenses`, `group_expense_splits`, `group_fund_entries`, `expense_group_join_rate_limits`, `is_current_user_expense_group_member(uuid)`, `is_expense_group_member(uuid, uuid)`, `create_group_expense(uuid, text, bigint, uuid[])`.
- Produces: cột `expense_groups.fund_goal_minor bigint null`, `expense_groups.fund_deadline date null`; `group_fund_entries.actor_id` nullable; RPC `set_group_fund_goal(p_group_id uuid, p_goal_minor bigint, p_deadline date) returns void`; SQLSTATE `UF001` cho các thông điệp ở spec mục 4.1.

Cần Docker đang chạy. Lần đầu: `npx supabase start` (tải image, vài phút).

- [ ] **Step 1: Viết test pgTAP (sẽ fail vì chưa có migration)**

Tạo `supabase/tests/group_qr_fund_goal_test.sql`:

```sql
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
```

- [ ] **Step 2: Chạy test để thấy fail**

Run: `npx supabase db reset && npx supabase test db`
Expected: FAIL — `function public.set_group_fund_goal(...) does not exist` ở test 1, kéo theo các test sau.

- [ ] **Step 3: Viết migration**

Tạo `supabase/migrations/20261021100000_group_qr_fund_goal.sql`:

```sql
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
  update public.expense_group_join_rate_limits
    set attempt_count = 0, window_started_at = now()
    where user_id = v_user_id;
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
```

Nếu `drop constraint group_fund_entries_actor_id_fkey` báo không tồn tại, tra tên thật bằng
`npx supabase db reset` rồi
`psql "$(npx supabase status -o env | grep DB_URL | cut -d= -f2- | tr -d '"')" -c "\d public.group_fund_entries"`
và thay tên trong migration.

- [ ] **Step 4: Chạy test để thấy pass**

Run: `npx supabase db reset && npx supabase test db`
Expected: `group_qr_fund_goal_test.sql .. ok`, `All tests successful.`

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20261021100000_group_qr_fund_goal.sql supabase/tests/group_qr_fund_goal_test.sql
git commit -m "feat(db): add fund goal RPC and fix group join, permission and fund FK bugs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Hiện nguyên thông điệp `UF001`

**Files:**
- Modify: `lib/shared/errors/error_presenter.dart:35-39`
- Test: `test/shared/errors/error_presenter_test.dart`

**Interfaces:**
- Consumes: SQLSTATE `UF001` (Task 1).
- Produces: `friendlyMessage(PostgrestException(code: 'UF001', message: m)) == m`.

- [ ] **Step 1: Viết test fail**

Trong `test/shared/errors/error_presenter_test.dart`, thêm vào trong `group('friendlyMessage', () { ... })`, trước test `'không bao giờ để lộ chuỗi kỹ thuật ra UI'`:

```dart
    test('hiện nguyên câu tiếng Việt của lỗi UF001 từ RPC', () {
      expect(
        friendlyMessage(
          PostgrestException(
            message: 'Quỹ không đủ tiền cho khoản chi này',
            code: 'UF001',
          ),
        ),
        'Quỹ không đủ tiền cho khoản chi này',
      );
    });

    test('lỗi 22023 và P0001 vẫn hiện câu chung', () {
      for (final code in ['22023', 'P0001']) {
        expect(
          friendlyMessage(
            PostgrestException(message: 'Fund entry is invalid', code: code),
          ),
          'Máy chủ từ chối yêu cầu. Dữ liệu trên máy không bị ảnh hưởng.',
        );
      }
    });
```

- [ ] **Step 2: Chạy test để thấy fail**

Run: `flutter test test/shared/errors/error_presenter_test.dart`
Expected: FAIL ở test UF001 — `Expected: 'Quỹ không đủ tiền cho khoản chi này' Actual: 'Máy chủ từ chối yêu cầu. ...'`

- [ ] **Step 3: Sửa `error_presenter.dart`**

```dart
    final PostgrestException e => switch (e.code) {
      'PGRST301' => 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.',
      // UF001: RPC chủ động gửi câu tiếng Việt cho người dùng.
      'UF001' => e.message,
      '23505' => 'Dữ liệu này đã tồn tại trên máy chủ.',
      _ => 'Máy chủ từ chối yêu cầu. Dữ liệu trên máy không bị ảnh hưởng.',
    },
```

- [ ] **Step 4: Chạy test để thấy pass**

Run: `flutter test test/shared/errors/error_presenter_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

Nếu `flutter analyze` gợi ý `prefer_const_constructors` cho `PostgrestException(...)` trong test, thêm `const` rồi chạy lại.

```bash
dart format lib test && flutter analyze
git add lib/shared/errors/error_presenter.dart test/shared/errors/error_presenter_test.dart
git commit -m "feat: show user-facing UF001 messages from Supabase RPCs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `InviteLink`

**Files:**
- Create: `lib/features/groups/domain/invite_link.dart`
- Test: `test/features/groups/invite_link_test.dart`

**Interfaces:**
- Produces:
  - `sealed class InviteLink` với `static InviteLink? parse(String raw)` và `static String groupUri(String code)`.
  - `final class GroupInviteLink extends InviteLink { final String code; }` — `code` luôn uppercase, khớp `^[0-9A-F]{8}$`.

- [ ] **Step 1: Viết test fail**

`test/features/groups/invite_link_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/groups/domain/invite_link.dart';

String? _groupCode(String raw) => switch (InviteLink.parse(raw)) {
  GroupInviteLink(:final code) => code,
  null => null,
};

void main() {
  test('đọc mã từ URI mời nhóm', () {
    expect(_groupCode('hoadoninsight://join-group?code=ABCD1234'), 'ABCD1234');
  });

  test('chấp nhận mã trơn, chữ thường và khoảng trắng', () {
    expect(_groupCode('  abcd1234 \n'), 'ABCD1234');
    expect(_groupCode('hoadoninsight://join-group?code=abcd1234'), 'ABCD1234');
  });

  test('từ chối scheme hoặc host lạ', () {
    expect(_groupCode('https://join-group?code=ABCD1234'), isNull);
    expect(_groupCode('hoadoninsight://payment-return?code=ABCD1234'), isNull);
    expect(_groupCode('hoadoninsight://join-group'), isNull);
  });

  test('từ chối mã sai độ dài hoặc ký tự', () {
    expect(_groupCode('ABCD123'), isNull);
    expect(_groupCode('ABCD12345'), isNull);
    expect(_groupCode('ABCD123G'), isNull);
    expect(_groupCode(''), isNull);
  });

  test('từ chối payload VietQR', () {
    expect(
      _groupCode(
        '00020101021138570010A000000727012700069704220113VQRQ00000000020208QRIBFTTA53037045802VN6304ABCD',
      ),
      isNull,
    );
  });

  test('groupUri rồi parse cho lại đúng mã', () {
    final uri = InviteLink.groupUri('ABCD1234');
    expect(uri, 'hoadoninsight://join-group?code=ABCD1234');
    expect(_groupCode(uri), 'ABCD1234');
  });
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run: `flutter test test/features/groups/invite_link_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:hoadon_insight/features/groups/domain/invite_link.dart'`

- [ ] **Step 3: Viết `invite_link.dart`**

```dart
/// Nội dung QR mời. Spec B sẽ thêm biến thể cho bill.
sealed class InviteLink {
  const InviteLink();

  static const _scheme = 'hoadoninsight';
  static const _groupHost = 'join-group';
  static final _codePattern = RegExp(r'^[0-9A-F]{8}$');

  /// Nhận URI `hoadoninsight://join-group?code=...` hoặc mã trơn.
  /// Trả `null` khi không phải mã mời hợp lệ.
  static InviteLink? parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri != null && uri.hasScheme) {
      if (uri.scheme != _scheme || uri.host != _groupHost) return null;
      return _group(uri.queryParameters['code']);
    }
    return _group(text);
  }

  static String groupUri(String code) => Uri(
    scheme: _scheme,
    host: _groupHost,
    queryParameters: {'code': code},
  ).toString();

  static GroupInviteLink? _group(String? code) {
    final normalized = code?.trim().toUpperCase();
    if (normalized == null || !_codePattern.hasMatch(normalized)) return null;
    return GroupInviteLink(normalized);
  }
}

final class GroupInviteLink extends InviteLink {
  const GroupInviteLink(this.code);

  final String code;
}
```

- [ ] **Step 4: Chạy test để thấy pass**

Run: `flutter test test/features/groups/invite_link_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
dart format lib test && flutter analyze
git add lib/features/groups/domain/invite_link.dart test/features/groups/invite_link_test.dart
git commit -m "feat: parse and build group invite links for QR codes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `GroupFundProgress`

**Files:**
- Create: `lib/features/groups/domain/group_fund_progress.dart`
- Test: `test/features/groups/group_fund_progress_test.dart`

**Interfaces:**
- Produces:
  - `enum GroupFundStatus { noGoal, inProgress, reached, overdue }`
  - `class GroupFundProgress { final GroupFundStatus status; final double? ratio; final int? daysLeft; static GroupFundProgress compute({required int balanceMinor, int? goalMinor, DateTime? deadline, required DateTime today}); }`

- [ ] **Step 1: Viết test fail**

`test/features/groups/group_fund_progress_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/groups/domain/group_fund_progress.dart';

void main() {
  final today = DateTime(2026, 10, 20, 15, 30);

  test('không có mục tiêu', () {
    final progress = GroupFundProgress.compute(
      balanceMinor: 500000,
      goalMinor: null,
      deadline: null,
      today: today,
    );
    expect(progress.status, GroupFundStatus.noGoal);
    expect(progress.ratio, isNull);
    expect(progress.daysLeft, isNull);
  });

  test('đang góp, còn ngày', () {
    final progress = GroupFundProgress.compute(
      balanceMinor: 6400000,
      goalMinor: 10000000,
      deadline: DateTime(2026, 12, 15),
      today: today,
    );
    expect(progress.status, GroupFundStatus.inProgress);
    expect(progress.ratio, closeTo(0.64, 1e-9));
    expect(progress.daysLeft, 56);
  });

  test('hạn đúng hôm nay vẫn đang góp, còn 0 ngày', () {
    final progress = GroupFundProgress.compute(
      balanceMinor: 100,
      goalMinor: 1000,
      deadline: DateTime(2026, 10, 20),
      today: today,
    );
    expect(progress.status, GroupFundStatus.inProgress);
    expect(progress.daysLeft, 0);
  });

  test('quá hạn chưa đạt', () {
    final progress = GroupFundProgress.compute(
      balanceMinor: 100,
      goalMinor: 1000,
      deadline: DateTime(2026, 10, 17),
      today: today,
    );
    expect(progress.status, GroupFundStatus.overdue);
    expect(progress.daysLeft, -3);
  });

  test('đạt mục tiêu sau hạn vẫn là đạt, tỷ lệ có thể vượt 1', () {
    final progress = GroupFundProgress.compute(
      balanceMinor: 1500,
      goalMinor: 1000,
      deadline: DateTime(2026, 10, 1),
      today: today,
    );
    expect(progress.status, GroupFundStatus.reached);
    expect(progress.ratio, closeTo(1.5, 1e-9));
  });

  test('có mục tiêu, không có hạn', () {
    final progress = GroupFundProgress.compute(
      balanceMinor: 0,
      goalMinor: 1000,
      deadline: null,
      today: today,
    );
    expect(progress.status, GroupFundStatus.inProgress);
    expect(progress.ratio, 0);
    expect(progress.daysLeft, isNull);
  });
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run: `flutter test test/features/groups/group_fund_progress_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Viết `group_fund_progress.dart`**

```dart
enum GroupFundStatus { noGoal, inProgress, reached, overdue }

class GroupFundProgress {
  const GroupFundProgress({required this.status, this.ratio, this.daysLeft});

  final GroupFundStatus status;

  /// Số dư / mục tiêu; không chặn ở 1.0. `null` khi chưa có mục tiêu.
  final double? ratio;

  /// Số ngày tới hạn; âm khi quá hạn; `null` khi không có hạn hoặc mục tiêu.
  final int? daysLeft;

  static GroupFundProgress compute({
    required int balanceMinor,
    int? goalMinor,
    DateTime? deadline,
    required DateTime today,
  }) {
    if (goalMinor == null || goalMinor <= 0) {
      return const GroupFundProgress(status: GroupFundStatus.noGoal);
    }
    final daysLeft = deadline == null
        ? null
        : _dateOnly(deadline).difference(_dateOnly(today)).inDays;
    final status = balanceMinor >= goalMinor
        ? GroupFundStatus.reached
        : daysLeft != null && daysLeft < 0
        ? GroupFundStatus.overdue
        : GroupFundStatus.inProgress;
    return GroupFundProgress(
      status: status,
      ratio: balanceMinor / goalMinor,
      daysLeft: daysLeft,
    );
  }

  // UTC để phép trừ ngày không lệch vì giờ mùa hè.
  static DateTime _dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
}
```

- [ ] **Step 4: Chạy test để thấy pass**

Run: `flutter test test/features/groups/group_fund_progress_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
dart format lib test && flutter analyze
git add lib/features/groups/domain/group_fund_progress.dart test/features/groups/group_fund_progress_test.dart
git commit -m "feat: compute group fund goal progress

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Model và service

**Files:**
- Modify: `lib/features/groups/domain/group_models.dart:1-33`
- Modify: `lib/features/groups/data/group_service.dart` (`listFundEntries`, `listGroups`, `joinGroup`, `_groupFromMap`, thêm `setFundGoal`)

**Interfaces:**
- Consumes: cột `fund_goal_minor`, `fund_deadline`, RPC `set_group_fund_goal` (Task 1).
- Produces:
  - `ExpenseGroup({..., int? fundGoalMinor, DateTime? fundDeadline})`.
  - `GroupFundEntry.actorId` kiểu `String?`.
  - `Future<void> ExpenseGroupService.setFundGoal({required String groupId, int? goalMinor, DateTime? deadline})`.
  - `joinGroup` ném `StateError('Mã mời không hợp lệ.')` khi RPC trả 0 dòng.

Không có test đơn vị cho `ExpenseGroupService` trong repo (gọi Supabase thật); kiểm tra bằng `flutter analyze`, toàn bộ `flutter test`, và pgTAP ở Task 1.

- [ ] **Step 1: Sửa `ExpenseGroup` và `GroupFundEntry`**

Trong `group_models.dart`:

```dart
class ExpenseGroup {
  const ExpenseGroup({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.ownerId,
    this.fundGoalMinor,
    this.fundDeadline,
  });

  final String id;
  final String name;
  final String inviteCode;
  final String ownerId;
  final int? fundGoalMinor;
  final DateTime? fundDeadline;
}

class GroupFundEntry {
  const GroupFundEntry({
    required this.id,
    required this.groupId,
    required this.actorId,
    required this.kind,
    required this.amountMinor,
    required this.note,
    required this.createdAt,
  });

  final String id;
  final String groupId;

  /// `null` khi người ghi đã xóa tài khoản.
  final String? actorId;
  final String kind;
  final int amountMinor;
  final String note;
  final DateTime createdAt;
}
```

- [ ] **Step 2: Sửa `group_service.dart`**

Trong `listFundEntries`, đổi dòng `actorId`:

```dart
            actorId: _optionalUuid(row['actor_id'], 'fund.actor_id'),
```

Trong `listGroups`, đổi select:

```dart
          .select('id, name, invite_code, owner_id, fund_goal_minor, fund_deadline')
```

Trong `joinGroup`, đổi câu lỗi:

```dart
    if (list.isEmpty) throw StateError('Mã mời không hợp lệ.');
```

Trong `_groupFromMap`, thêm hai field vào `ExpenseGroup(...)`:

```dart
      fundGoalMinor: map['fund_goal_minor'] == null
          ? null
          : _positiveInteger(map['fund_goal_minor'], 'group.fundGoalMinor'),
      fundDeadline: _optionalDate(map['fund_deadline'], 'group.fundDeadline'),
```

Thêm sau `deleteFundEntry`:

```dart
  Future<void> setFundGoal({
    required String groupId,
    int? goalMinor,
    DateTime? deadline,
  }) async {
    _requiredUuid(groupId, 'group.id');
    if (goalMinor != null && (goalMinor < 1 || goalMinor > _maxSafeInteger)) {
      throw const FormatException('Mục tiêu quỹ không hợp lệ.');
    }
    if (goalMinor == null && deadline != null) {
      throw const FormatException('Hãy nhập mục tiêu trước khi đặt hạn.');
    }
    await _client.rpc(
      'set_group_fund_goal',
      params: {
        'p_group_id': groupId,
        'p_goal_minor': goalMinor,
        'p_deadline': deadline == null ? null : _isoDate(deadline),
      },
    );
  }

  static String _isoDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
```

- [ ] **Step 3: Sửa chỗ dùng `actorId` trong màn quỹ cho kiểu nullable**

Trong `group_fund_screen.dart`, dòng subtitle của dòng quỹ:

```dart
                  subtitle: Text(
                    '${names[entry.actorId] ?? (entry.actorId == null ? 'Tài khoản đã xóa' : 'Thành viên')} · ${entry.createdAt.day}/${entry.createdAt.month}/${entry.createdAt.year}',
                  ),
```

(Điều kiện hiện nút "Xóa" `entry.actorId == currentUserId || ownerId == currentUserId` đã đúng: dòng có `actorId` null chỉ trưởng nhóm thấy nút.)

- [ ] **Step 4: Chạy analyze và toàn bộ test**

Run: `dart format lib test && flutter analyze && flutter test`
Expected: `No issues found!`, mọi test PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/groups/domain/group_models.dart lib/features/groups/data/group_service.dart lib/features/groups/presentation/group_fund_screen.dart
git commit -m "feat: load fund goal and support deleted fund entry authors

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Tách biểu mẫu chia tiền dùng chung và thêm giá trị điền sẵn

**Files:**
- Create: `lib/features/groups/presentation/group_expense_dialog.dart`
- Modify: `lib/features/groups/presentation/group_screen.dart` (xóa `_NewExpenseDraft` dòng 1307-1319 và `_NewExpenseDialog`/`_NewExpenseDialogState` dòng 1507-1770; đổi chỗ gọi trong `_addExpense`, `_editExpense`)
- Test: `test/features/groups/group_expense_dialog_test.dart`

**Interfaces:**
- Produces:
  - `class GroupExpenseDraft { final String description; final int totalMinor; final List<String> memberIds; final Map<String, int>? splitAmounts; }`
  - `class GroupExpenseForm extends StatefulWidget { const GroupExpenseForm({required List<GroupMember> members, GroupExpense? initialExpense, String? initialDescription, int? initialTotalMinor, bool autofocus = true, Key? key}); }` với state công khai `GroupExpenseFormState` có `GroupExpenseDraft? submit()` (sai thì hiện lỗi trong form, trả `null`) và `bool get hasChanges`. Task 7 dùng qua `GlobalKey<GroupExpenseFormState>`.
  - `class GroupExpenseDialog extends StatefulWidget { const GroupExpenseDialog({required List<GroupMember> members, GroupExpense? initialExpense, String? initialDescription, int? initialTotalMinor}); }` — `showDialog<GroupExpenseDraft>`; tiêu đề "Chia tiền" (tạo) / "Sửa lần chia tiền" (sửa).
  - `String receiptExpenseDescription(String sellerName)` — `'Hóa đơn <tên>'`, `'Hóa đơn'` khi tên rỗng, tối đa 160 ký tự.

- [ ] **Step 1: Viết test fail**

`test/features/groups/group_expense_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/groups/domain/group_models.dart';
import 'package:hoadon_insight/features/groups/presentation/group_expense_dialog.dart';

const _members = [
  GroupMember(userId: 'u1', displayName: 'Huy', role: 'owner'),
  GroupMember(userId: 'u2', displayName: 'Lan', role: 'member'),
];

Future<void> _open(WidgetTester tester, Widget dialog) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () =>
              showDialog<void>(context: context, builder: (_) => dialog),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester, String label) => tester
    .widget<TextField>(find.widgetWithText(TextField, label))
    .controller!
    .text;

void main() {
  testWidgets('điền sẵn nội dung và tổng tiền từ hóa đơn', (tester) async {
    await _open(
      tester,
      const GroupExpenseDialog(
        members: _members,
        initialDescription: 'Hóa đơn Highlands',
        initialTotalMinor: 120000,
      ),
    );
    expect(_fieldText(tester, 'Nội dung'), 'Hóa đơn Highlands');
    expect(_fieldText(tester, 'Tổng tiền'), '120000');
    expect(find.text('Chia tiền'), findsWidgets);
  });

  testWidgets('tổng tiền 0 từ OCR thì để trống ô tổng tiền', (tester) async {
    await _open(
      tester,
      const GroupExpenseDialog(
        members: _members,
        initialDescription: 'Hóa đơn',
        initialTotalMinor: 0,
      ),
    );
    expect(_fieldText(tester, 'Tổng tiền'), isEmpty);
  });

  testWidgets('khi sửa thì bỏ qua giá trị điền sẵn', (tester) async {
    await _open(
      tester,
      GroupExpenseDialog(
        members: _members,
        initialDescription: 'Khác',
        initialTotalMinor: 1,
        initialExpense: GroupExpense(
          id: 'e1',
          groupId: 'g1',
          payerId: 'u1',
          description: 'Ăn trưa',
          totalMinor: 50000,
          createdAt: DateTime(2026, 10, 20),
          splits: const [
            GroupExpenseSplit(userId: 'u1', amountMinor: 25000),
            GroupExpenseSplit(userId: 'u2', amountMinor: 25000),
          ],
        ),
      ),
    );
    expect(_fieldText(tester, 'Nội dung'), 'Ăn trưa');
    expect(_fieldText(tester, 'Tổng tiền'), '50000');
    expect(find.text('Sửa lần chia tiền'), findsOneWidget);
  });

  testWidgets('submit trả bản nháp chia đều cho mọi thành viên', (tester) async {
    final key = GlobalKey<GroupExpenseFormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GroupExpenseForm(key: key, members: _members),
          ),
        ),
      ),
    );
    expect(key.currentState!.submit(), isNull);
    await tester.pump();
    expect(
      find.text('Hãy nhập nội dung, tổng tiền và chọn thành viên.'),
      findsOneWidget,
    );
    await tester.enterText(find.widgetWithText(TextField, 'Nội dung'), 'Ăn tối');
    await tester.enterText(find.widgetWithText(TextField, 'Tổng tiền'), '90000');
    expect(key.currentState!.hasChanges, isTrue);
    final draft = key.currentState!.submit()!;
    expect(draft.description, 'Ăn tối');
    expect(draft.totalMinor, 90000);
    expect(draft.memberIds.toSet(), {'u1', 'u2'});
    expect(draft.splitAmounts, isNull);
  });

  test('mô tả từ hóa đơn có tên, không tên, và tên quá dài', () {
    expect(receiptExpenseDescription('  Highlands  '), 'Hóa đơn Highlands');
    expect(receiptExpenseDescription('   '), 'Hóa đơn');
    final long = receiptExpenseDescription('A' * 300);
    expect(long.length, 160);
    expect(long, startsWith('Hóa đơn AAA'));
  });
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run: `flutter test test/features/groups/group_expense_dialog_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:hoadon_insight/features/groups/presentation/group_expense_dialog.dart'`

- [ ] **Step 3: Tạo file mới**

`lib/features/groups/presentation/group_expense_dialog.dart` — biểu mẫu là phần thân của `_NewExpenseDialog` cũ (cùng ô, cùng cách chia, cùng câu lỗi), tách khỏi `AlertDialog` để Task 7 đặt được vào tab:

```dart
import 'package:flutter/material.dart';

import '../../../shared/dialogs/confirm_dialog.dart';
import '../domain/group_models.dart';
import '../domain/group_split_calculator.dart';

/// Mô tả lần chia tiền tạo từ hóa đơn quét; giới hạn 160 ký tự như server.
String receiptExpenseDescription(String sellerName) {
  final seller = sellerName.trim();
  final text = seller.isEmpty ? 'Hóa đơn' : 'Hóa đơn $seller';
  return text.length > 160 ? text.substring(0, 160) : text;
}

class GroupExpenseDraft {
  const GroupExpenseDraft({
    required this.description,
    required this.totalMinor,
    required this.memberIds,
    this.splitAmounts,
  });

  final String description;
  final int totalMinor;
  final List<String> memberIds;
  final Map<String, int>? splitAmounts;
}

/// Biểu mẫu một lần chia tiền: nội dung, tổng tiền, thành viên, cách chia.
/// Dùng chung cho dialog sửa và hai tab của dialog "Chia tiền".
class GroupExpenseForm extends StatefulWidget {
  const GroupExpenseForm({
    required this.members,
    this.initialExpense,
    this.initialDescription,
    this.initialTotalMinor,
    this.autofocus = true,
    super.key,
  });

  final List<GroupMember> members;
  final GroupExpense? initialExpense;

  /// Giá trị điền sẵn khi tạo mới; bị bỏ qua khi có [initialExpense].
  final String? initialDescription;
  final int? initialTotalMinor;
  final bool autofocus;

  @override
  State<GroupExpenseForm> createState() => GroupExpenseFormState();
}

class GroupExpenseFormState extends State<GroupExpenseForm> {
  late final TextEditingController _descriptionController;
  late final TextEditingController _amountController;
  final Map<String, TextEditingController> _splitControllers = {};
  late final Set<String> _selectedIds;
  late GroupSplitMode? _customMode;
  late final String _startDescription;
  late final String _startAmount;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialExpense;
    final prefillTotal = widget.initialTotalMinor;
    _descriptionController = TextEditingController(
      text: initial?.description ?? widget.initialDescription,
    );
    _amountController = TextEditingController(
      text:
          initial?.totalMinor.toString() ??
          (prefillTotal != null && prefillTotal > 0
              ? prefillTotal.toString()
              : null),
    );
    _startDescription = _descriptionController.text;
    _startAmount = _amountController.text;
    _selectedIds = initial == null
        ? widget.members.map((item) => item.userId).toSet()
        : initial.splits
              .map((split) => split.userId)
              .whereType<String>()
              .toSet();
    _customMode = initial == null ? null : GroupSplitMode.exact;
    if (initial != null) {
      for (final split in initial.splits) {
        final userId = split.userId;
        if (userId != null) {
          _splitControllers[userId] = TextEditingController(
            text: split.amountMinor.toString(),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    for (final controller in _splitControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _descriptionController,
          autofocus: widget.autofocus,
          decoration: const InputDecoration(labelText: 'Nội dung'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Tổng tiền',
            suffixText: '₫',
          ),
        ),
        const SizedBox(height: 16),
        SegmentedButton<GroupSplitMode?>(
          segments: const [
            ButtonSegment(value: null, label: Text('Đều')),
            ButtonSegment(value: GroupSplitMode.exact, label: Text('Số tiền')),
            ButtonSegment(value: GroupSplitMode.percentage, label: Text('%')),
          ],
          selected: {_customMode},
          onSelectionChanged: (value) => setState(() {
            _customMode = value.first;
            _error = null;
          }),
        ),
        const SizedBox(height: 12),
        Text(_customMode == null ? 'Chia đều cho' : 'Phần của từng người'),
        for (final member in widget.members) _buildMemberRow(member),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  bool get hasChanges {
    final initial = widget.initialExpense;
    final initialMemberIds = initial == null
        ? widget.members.map((item) => item.userId).toSet()
        : initial.splits
              .map((split) => split.userId)
              .whereType<String>()
              .toSet();
    if (_descriptionController.text != _startDescription ||
        _amountController.text != _startAmount ||
        _customMode != (initial == null ? null : GroupSplitMode.exact) ||
        _selectedIds.length != initialMemberIds.length ||
        !_selectedIds.containsAll(initialMemberIds)) {
      return true;
    }

    final initialSplitAmounts = {
      if (initial != null)
        for (final split in initial.splits)
          if (split.userId != null) split.userId!: split.amountMinor,
    };
    return _splitControllers.entries.any(
      (entry) =>
          entry.value.text !=
          (initialSplitAmounts[entry.key]?.toString() ?? ''),
    );
  }

  /// Kiểm tra dữ liệu; hợp lệ thì trả bản nháp, sai thì hiện lỗi và trả `null`.
  GroupExpenseDraft? submit() {
    final total = int.tryParse(
      _amountController.text.replaceAll(RegExp(r'[^0-9]'), ''),
    );
    final description = _descriptionController.text.trim();
    if (description.length < 2 ||
        total == null ||
        total <= 0 ||
        _selectedIds.isEmpty) {
      setState(
        () => _error = 'Hãy nhập nội dung, tổng tiền và chọn thành viên.',
      );
      return null;
    }
    Map<String, int>? splitAmounts;
    if (_customMode != null) {
      splitAmounts = _parseSplits(total);
      if (splitAmounts == null) return null;
    }
    return GroupExpenseDraft(
      description: description,
      totalMinor: total,
      memberIds: _selectedIds.toList(growable: false),
      splitAmounts: widget.initialExpense == null
          ? splitAmounts
          : splitAmounts!,
    );
  }

  Widget _buildMemberRow(GroupMember member) {
    final controller = _splitControllers.putIfAbsent(
      member.userId,
      TextEditingController.new,
    );
    return Row(
      children: [
        Expanded(
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _selectedIds.contains(member.userId),
            title: Text(member.displayName),
            onChanged: (value) => setState(() {
              if (value == true) {
                _selectedIds.add(member.userId);
              } else {
                _selectedIds.remove(member.userId);
              }
              _error = null;
            }),
          ),
        ),
        if (_customMode != null)
          SizedBox(
            width: 92,
            child: TextField(
              controller: controller,
              enabled: _selectedIds.contains(member.userId),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                suffixText: _customMode == GroupSplitMode.percentage
                    ? '%'
                    : '₫',
              ),
            ),
          ),
      ],
    );
  }

  Map<String, int>? _parseSplits(int total) {
    final values = <String, double>{};
    for (final id in _selectedIds) {
      final value = double.tryParse(
        _splitControllers[id]!.text.trim().replaceAll(',', '.'),
      );
      if (value == null || value < 0) {
        setState(() => _error = 'Hãy nhập phần chia hợp lệ cho mọi người.');
        return null;
      }
      values[id] = value;
    }
    final amounts = GroupSplitCalculator.calculate(
      totalMinor: total,
      memberIds: _selectedIds,
      values: values,
      mode: _customMode!,
    );
    if (amounts == null) {
      setState(
        () => _error = _customMode == GroupSplitMode.percentage
            ? 'Tổng tỷ lệ phải bằng 100%.'
            : 'Tổng các phần tiền phải bằng tổng tiền.',
      );
      return null;
    }
    return amounts;
  }
}

/// Dialog một biểu mẫu — dùng khi sửa một lần chia tiền (tạo mới dùng
/// `GroupSplitDialog` hai tab ở Task 7).
class GroupExpenseDialog extends StatefulWidget {
  const GroupExpenseDialog({
    required this.members,
    this.initialExpense,
    this.initialDescription,
    this.initialTotalMinor,
    super.key,
  });

  final List<GroupMember> members;
  final GroupExpense? initialExpense;
  final String? initialDescription;
  final int? initialTotalMinor;

  @override
  State<GroupExpenseDialog> createState() => _GroupExpenseDialogState();
}

class _GroupExpenseDialogState extends State<GroupExpenseDialog> {
  final _formKey = GlobalKey<GroupExpenseFormState>();

  @override
  Widget build(BuildContext context) {
    final editing = widget.initialExpense != null;
    return AlertDialog(
      title: Text(editing ? 'Sửa lần chia tiền' : 'Chia tiền'),
      content: SingleChildScrollView(
        child: GroupExpenseForm(
          key: _formKey,
          members: widget.members,
          initialExpense: widget.initialExpense,
          initialDescription: widget.initialDescription,
          initialTotalMinor: widget.initialTotalMinor,
        ),
      ),
      actions: [
        TextButton(onPressed: _cancel, child: const Text('Hủy')),
        FilledButton(
          onPressed: _submit,
          child: Text(editing ? 'Lưu thay đổi' : 'Chia tiền'),
        ),
      ],
    );
  }

  Future<void> _cancel() async {
    if (_formKey.currentState?.hasChanges ?? false) {
      final discard = await showDiscardChangesDialog(context);
      if (!discard || !mounted) return;
    }
    Navigator.pop(context);
  }

  void _submit() {
    final draft = _formKey.currentState?.submit();
    if (draft != null) Navigator.pop(context, draft);
  }
}
```

Lưu ý: câu lỗi "Tổng các phần tiền phải bằng tổng khoản chi." đổi thành "… bằng tổng tiền." để biểu mẫu chia tiền không còn chữ "khoản chi" (spec 4.6).

- [ ] **Step 4: Đổi `group_screen.dart` sang file mới**

1. Xóa `_NewExpenseDraft` (dòng 1307-1319) và `_NewExpenseDialog`/`_NewExpenseDialogState` (dòng 1507-1770).
2. Thêm `import 'group_expense_dialog.dart';`.
3. Trong `_addExpense`: `showDialog<_NewExpenseDraft>` → `showDialog<GroupExpenseDraft>`, `_NewExpenseDialog(` → `GroupExpenseDialog(`. (Task 7 thay hàm này bằng `_splitMoney`.)
4. Trong `_editExpense`: đổi tương tự, giữ `initialExpense: expense`.

- [ ] **Step 5: Chạy test và analyze**

Run: `dart format lib test && flutter analyze && flutter test test/features/groups`
Expected: PASS. Nếu analyze báo `unused_import` cho `group_split_calculator.dart` trong `group_screen.dart`, xóa import đó rồi chạy lại.

- [ ] **Step 6: Commit**

```bash
git add lib/features/groups/presentation/group_expense_dialog.dart lib/features/groups/presentation/group_screen.dart test/features/groups/group_expense_dialog_test.dart
git commit -m "refactor: extract reusable group split form with prefilled values

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Nút "Chia tiền" mở dialog hai tab "Nhập thủ công" / "Quét hóa đơn"

**Files:**
- Create: `lib/features/groups/presentation/group_split_dialog.dart`
- Modify: `lib/features/groups/presentation/group_screen.dart` (thay `_addExpense` bằng `_splitMoney`; thêm `_scanReceipt`; xóa `_addReceipt` và `_InvoiceAllocationDraft`, `_InvoiceAllocationLine`, `_InvoiceAllocationDialog`, `_InvoiceAllocationDialogState` — dòng 1321-1505 trước Task 6; `_GroupDetails`: một nút "Chia tiền", tiêu đề danh sách "Chia tiền")
- Test: `test/features/groups/group_split_dialog_test.dart`

**Interfaces:**
- Consumes: `GroupExpenseForm`, `GroupExpenseFormState`, `GroupExpenseDraft`, `receiptExpenseDescription` (Task 6); `importCoordinatorProvider.importImage`, `friendlyMessage` (có sẵn).
- Produces:
  - `class ReceiptPrefill { const ReceiptPrefill({required String description, required int totalMinor}); }`
  - `class GroupSplitDialog extends StatefulWidget { const GroupSplitDialog({required List<GroupMember> members, required Future<ReceiptPrefill?> Function(ImageSource source) onScan}); }` — `showDialog<GroupExpenseDraft>`. `onScan` trả `null` khi người dùng huỷ chọn ảnh, ném lỗi khi đọc hóa đơn thất bại.

- [ ] **Step 1: Viết test fail**

`test/features/groups/group_split_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/groups/domain/group_models.dart';
import 'package:hoadon_insight/features/groups/presentation/group_expense_dialog.dart';
import 'package:hoadon_insight/features/groups/presentation/group_split_dialog.dart';
import 'package:image_picker/image_picker.dart';

const _members = [
  GroupMember(userId: 'u1', displayName: 'Huy', role: 'owner'),
  GroupMember(userId: 'u2', displayName: 'Lan', role: 'member'),
];

/// Mở dialog; kết quả `showDialog` ghi vào [result] khi dialog đóng.
Future<void> _open(
  WidgetTester tester,
  Future<ReceiptPrefill?> Function(ImageSource) onScan,
  void Function(GroupExpenseDraft?) result,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result(
            await showDialog<GroupExpenseDraft>(
              context: context,
              builder: (_) =>
                  GroupSplitDialog(members: _members, onScan: onScan),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder _inTab(String tab, Finder finder) =>
    find.descendant(of: find.byKey(ValueKey(tab)), matching: finder);

Finder _saveButton() => find.widgetWithText(FilledButton, 'Chia tiền');

void main() {
  testWidgets('tab Nhập thủ công trả bản nháp chia đều', (tester) async {
    GroupExpenseDraft? draft;
    await _open(tester, (_) async => null, (d) => draft = d);
    expect(find.text('Nhập thủ công'), findsOneWidget);
    expect(find.text('Quét hóa đơn'), findsOneWidget);
    await tester.enterText(
      _inTab('tab-thu-cong', find.widgetWithText(TextField, 'Nội dung')),
      'Ăn tối',
    );
    await tester.enterText(
      _inTab('tab-thu-cong', find.widgetWithText(TextField, 'Tổng tiền')),
      '90000',
    );
    await tester.tap(_saveButton());
    await tester.pumpAndSettle();
    expect(draft!.description, 'Ăn tối');
    expect(draft!.totalMinor, 90000);
    expect(draft!.memberIds.toSet(), {'u1', 'u2'});
  });

  testWidgets('tab Quét hóa đơn điền sẵn rồi lưu', (tester) async {
    GroupExpenseDraft? draft;
    ImageSource? asked;
    await _open(tester, (source) async {
      asked = source;
      return const ReceiptPrefill(
        description: 'Hóa đơn Highlands',
        totalMinor: 120000,
      );
    }, (d) => draft = d);
    await tester.tap(find.text('Quét hóa đơn'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(_saveButton()).onPressed,
      isNull,
      reason: 'chưa quét thì chưa lưu được',
    );
    await tester.tap(find.text('Chọn từ thư viện'));
    await tester.pumpAndSettle();
    expect(asked, ImageSource.gallery);
    final ten = tester.widget<TextField>(
      _inTab('tab-quet', find.widgetWithText(TextField, 'Nội dung')),
    );
    expect(ten.controller!.text, 'Hóa đơn Highlands');
    await tester.tap(_saveButton());
    await tester.pumpAndSettle();
    expect(draft!.description, 'Hóa đơn Highlands');
    expect(draft!.totalMinor, 120000);
  });

  testWidgets('quét lỗi thì báo trong dialog, vẫn còn nút quét', (tester) async {
    await _open(tester, (_) async => throw StateError('mất mạng'), (_) {});
    await tester.tap(find.text('Quét hóa đơn'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chụp ảnh hóa đơn'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Không thể xử lý hóa đơn'), findsOneWidget);
    expect(find.text('Chụp ảnh hóa đơn'), findsOneWidget);
    expect(find.byType(GroupSplitDialog), findsOneWidget);
  });

  testWidgets('huỷ chọn ảnh thì không báo lỗi', (tester) async {
    await _open(tester, (_) async => null, (_) {});
    await tester.tap(find.text('Quét hóa đơn'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chọn từ thư viện'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Không thể xử lý hóa đơn'), findsNothing);
    expect(find.text('Chọn từ thư viện'), findsOneWidget);
  });

  testWidgets('chuyển tab không mất chữ đã nhập', (tester) async {
    await _open(tester, (_) async => null, (_) {});
    await tester.enterText(
      _inTab('tab-thu-cong', find.widgetWithText(TextField, 'Nội dung')),
      'Cà phê',
    );
    await tester.tap(find.text('Quét hóa đơn'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhập thủ công'));
    await tester.pumpAndSettle();
    final o = tester.widget<TextField>(
      _inTab('tab-thu-cong', find.widgetWithText(TextField, 'Nội dung')),
    );
    expect(o.controller!.text, 'Cà phê');
  });
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run: `flutter test test/features/groups/group_split_dialog_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:hoadon_insight/features/groups/presentation/group_split_dialog.dart'`

- [ ] **Step 3: Tạo `group_split_dialog.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/dialogs/confirm_dialog.dart';
import '../../../shared/errors/error_presenter.dart';
import '../domain/group_models.dart';
import 'group_expense_dialog.dart';

/// Kết quả đọc hóa đơn dùng để điền sẵn biểu mẫu chia tiền.
class ReceiptPrefill {
  const ReceiptPrefill({required this.description, required this.totalMinor});

  final String description;
  final int totalMinor;
}

/// Dialog "Chia tiền": tab "Nhập thủ công" và tab "Quét hóa đơn"; tab nào cũng
/// lưu được một lần chia tiền cho các thành viên.
///
/// [onScan] chụp/chọn ảnh và đọc hóa đơn: trả `null` khi người dùng huỷ chọn
/// ảnh, ném lỗi khi đọc thất bại. Dialog không đọc provider nên test độc lập.
class GroupSplitDialog extends StatefulWidget {
  const GroupSplitDialog({
    required this.members,
    required this.onScan,
    super.key,
  });

  final List<GroupMember> members;
  final Future<ReceiptPrefill?> Function(ImageSource source) onScan;

  @override
  State<GroupSplitDialog> createState() => _GroupSplitDialogState();
}

class _GroupSplitDialogState extends State<GroupSplitDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));
  final _manualKey = GlobalKey<GroupExpenseFormState>();
  final _scanKey = GlobalKey<GroupExpenseFormState>();
  ReceiptPrefill? _prefill;
  bool _scanning = false;
  String? _scanError;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  bool get _onScanTab => _tabs.index == 1;

  Future<void> _scan(ImageSource source) async {
    setState(() {
      _scanning = true;
      _scanError = null;
    });
    try {
      final prefill = await widget.onScan(source);
      if (!mounted) return;
      if (prefill != null) setState(() => _prefill = prefill);
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _scanError =
              'Không thể xử lý hóa đơn: ${friendlyMessage(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _cancel() async {
    final changed =
        (_manualKey.currentState?.hasChanges ?? false) ||
        (_scanKey.currentState?.hasChanges ?? false) ||
        _prefill != null;
    if (changed) {
      final discard = await showDiscardChangesDialog(context);
      if (!discard || !mounted) return;
    }
    Navigator.pop(context);
  }

  void _submit() {
    final form = _onScanTab ? _scanKey.currentState : _manualKey.currentState;
    final draft = form?.submit();
    if (draft != null) Navigator.pop(context, draft);
  }

  @override
  Widget build(BuildContext context) {
    final prefill = _prefill;
    // Toàn màn hình: Scaffold tự co khi bàn phím mở, không tràn như AlertDialog cố định chiều cao.
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Đóng',
            onPressed: _cancel,
            icon: const Icon(Icons.close),
          ),
          title: const Text('Chia tiền'),
          bottom: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Nhập thủ công'),
              Tab(text: 'Quét hóa đơn'),
            ],
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          // IndexedStack giữ trạng thái cả hai tab khi chuyển qua lại.
          child: IndexedStack(
            index: _tabs.index,
            children: [
              KeyedSubtree(
                key: const ValueKey('tab-thu-cong'),
                child: SingleChildScrollView(
                  child: GroupExpenseForm(
                    key: _manualKey,
                    members: widget.members,
                  ),
                ),
              ),
              KeyedSubtree(
                key: const ValueKey('tab-quet'),
                child: prefill == null
                    ? _buildScanStart(context)
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () =>
                                    setState(() => _prefill = null),
                                icon: const Icon(
                                  Icons.document_scanner_outlined,
                                ),
                                label: const Text('Quét hóa đơn khác'),
                              ),
                            ),
                            GroupExpenseForm(
                              key: _scanKey,
                              members: widget.members,
                              initialDescription: prefill.description,
                              initialTotalMinor: prefill.totalMinor,
                              autofocus: false,
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: _cancel, child: const Text('Hủy')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _onScanTab && prefill == null ? null : _submit,
                  child: const Text('Chia tiền'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScanStart(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Chụp hoặc chọn ảnh hóa đơn; nội dung và tổng tiền sẽ được điền sẵn.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        if (_scanning)
          const Center(child: CircularProgressIndicator())
        else ...[
          FilledButton.icon(
            onPressed: () => _scan(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Chụp ảnh hóa đơn'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _scan(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Chọn từ thư viện'),
          ),
        ],
        if (_scanError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _scanError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
```

Lưu ý khi "Quét hóa đơn khác": `_prefill = null` gỡ biểu mẫu cũ khỏi cây (`_scanKey` hết gắn), lần quét sau dựng biểu mẫu mới với giá trị mới.

- [ ] **Step 4: Nối vào `group_screen.dart`**

1. Thêm `import 'group_split_dialog.dart';`.
2. Thay toàn bộ `_addExpense` bằng `_splitMoney` và thêm `_scanReceipt`:

```dart
  Future<void> _splitMoney(GroupDetails details) async {
    final draft = await showDialog<GroupExpenseDraft>(
      context: context,
      builder: (context) =>
          GroupSplitDialog(members: details.members, onScan: _scanReceipt),
    );
    if (draft == null) return;
    await _runGroupAction(() async {
      final service = ref.read(expenseGroupServiceProvider)!;
      if (draft.splitAmounts == null) {
        await service.addEqualExpense(
          groupId: details.group.id,
          description: draft.description,
          totalMinor: draft.totalMinor,
          memberIds: draft.memberIds,
        );
      } else {
        await service.addCustomExpense(
          groupId: details.group.id,
          description: draft.description,
          totalMinor: draft.totalMinor,
          splitAmounts: draft.splitAmounts!,
        );
      }
    });
  }

  /// Chụp/chọn ảnh rồi đọc hóa đơn; `null` khi người dùng huỷ chọn ảnh.
  /// Lỗi đọc hóa đơn ném ra để dialog "Chia tiền" báo ngay trong tab Quét.
  Future<ReceiptPrefill?> _scanReceipt(ImageSource source) async {
    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 92,
      maxWidth: 2400,
    );
    if (image == null) return null;
    final bytes = await image.readAsBytes();
    final outcome = await ref
        .read(importCoordinatorProvider)
        .importImage(bytes: bytes, fileName: image.name, imagePath: image.path);
    final invoice = outcome.result.invoice;
    return ReceiptPrefill(
      description: receiptExpenseDescription(invoice.sellerName),
      totalMinor: invoice.totalMinor,
    );
  }
```

3. Xóa `_addReceipt` và bốn class `_InvoiceAllocationDraft`, `_InvoiceAllocationLine`, `_InvoiceAllocationDialog`, `_InvoiceAllocationDialogState`.
4. Chỗ tạo `_GroupDetails`: bỏ `onAddExpense:` và `onAddReceipt:`, thêm `onSplitMoney: () => _splitMoney(groupDetails),`.
5. Trong `_GroupDetails`: thay hai field/param `onAddExpense`, `onAddReceipt` bằng `final VoidCallback onSplitMoney;` (`required this.onSplitMoney`), rồi thay cả `Row` hai nút bằng:

```dart
        FilledButton.icon(
          onPressed: busy ? null : onSplitMoney,
          icon: const Icon(Icons.call_split_outlined),
          label: const Text('Chia tiền'),
        ),
```

6. Ngay dưới nút: tiêu đề `Text('Khoản chi', …)` → `Text('Chia tiền', …)`; câu trống `'Chưa có khoản chi nào trong nhóm.'` → `'Chưa có lần chia tiền nào trong nhóm.'`.
7. `_deleteExpense`: `title: 'Xóa khoản chi?'` → `'Xóa lần chia tiền?'`, `confirmLabel: 'Xóa khoản chi'` → `'Xóa'`.
8. Giữ import `invoice_models.dart` nếu analyze còn dùng (`InvoiceEntity` ở hộp thư chia sẻ); xóa nếu `unused_import`.

- [ ] **Step 5: Chạy test, analyze và toàn bộ test**

Run: `dart format lib test && flutter analyze && flutter test`
Expected: `No issues found!`, mọi test PASS. Xử lý mọi `unused_import`/`unused_element` analyze báo.

- [ ] **Step 6: Commit**

```bash
git add lib/features/groups/presentation/group_split_dialog.dart lib/features/groups/presentation/group_screen.dart test/features/groups/group_split_dialog_test.dart
git commit -m "feat: single Chia tien button with manual and scan-receipt tabs

Replaces the separate add-expense and from-receipt buttons; scanning
only prefills description and total, the per-line allocation dialog is
removed. Bill splitting is labelled separately from fund income/expense.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: QR mời — sinh, hiện và quét để tham gia

**Files:**
- Modify: `pubspec.yaml` (thêm `qr_flutter`), `pubspec.lock`
- Create: `lib/shared/widgets/qr_scan_screen.dart`
- Create: `lib/features/groups/presentation/group_invite_qr_sheet.dart`
- Modify: `lib/features/groups/presentation/group_screen.dart` (`_joinGroup`, `_GroupDetails`, chỗ tạo `_GroupDetails`, xóa `_copyInviteCode`)
- Modify: `test/features/groups/group_navigation_test.dart:73,79`
- Test: `test/features/groups/group_invite_qr_sheet_test.dart`

**Interfaces:**
- Consumes: `InviteLink`, `GroupInviteLink` (Task 3); `ExpenseGroupService.joinGroup` (Task 5).
- Produces:
  - `Future<void> showGroupInviteQrSheet(BuildContext context, {required String groupName, required String inviteCode})`.
  - `class QrScanScreen extends StatefulWidget { const QrScanScreen({required String title, required String? Function(String raw) validate}); }` — `Navigator.push<String>` trả chuỗi quét được khi `validate` trả `null`. Spec B dùng lại.

- [ ] **Step 1: Thêm dependency**

Trong `pubspec.yaml`, dưới `mobile_scanner: ^7.4.2` thêm:

```yaml
  qr_flutter: ^4.1.0
```

Run: `flutter pub get`
Expected: `Got dependencies!`

- [ ] **Step 2: Viết test fail cho bottom sheet QR**

`test/features/groups/group_invite_qr_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/groups/presentation/group_invite_qr_sheet.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('hiện QR chứa link mời và mã chữ', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showGroupInviteQrSheet(
                context,
                groupName: 'Đà Lạt',
                inviteCode: 'ABCD1234',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr.semanticsLabel, 'Mã QR mời vào nhóm Đà Lạt');
    expect(find.text('ABCD1234'), findsOneWidget);
    expect(find.text('Sao chép mã'), findsOneWidget);
  });
}
```

`QrImageView` không lộ `data` công khai, nên test kiểm tra `semanticsLabel`; nội dung link đã được Task 3 kiểm tra qua `InviteLink.groupUri`.

- [ ] **Step 3: Chạy test để thấy fail**

Run: `flutter test test/features/groups/group_invite_qr_sheet_test.dart`
Expected: FAIL — `Target of URI doesn't exist: .../group_invite_qr_sheet.dart`

- [ ] **Step 4: Viết `group_invite_qr_sheet.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../domain/invite_link.dart';

Future<void> showGroupInviteQrSheet(
  BuildContext context, {
  required String groupName,
  required String inviteCode,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Mời vào $groupName',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Nền trắng cố định để máy khác quét được cả khi app ở chế độ tối.
            QrImageView(
              data: InviteLink.groupUri(inviteCode),
              size: 220,
              backgroundColor: Colors.white,
              padding: const EdgeInsets.all(16),
              semanticsLabel: 'Mã QR mời vào nhóm $groupName',
            ),
            const SizedBox(height: 12),
            SelectableText(
              inviteCode,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: inviteCode));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã sao chép mã mời nhóm.')),
                );
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Sao chép mã'),
            ),
          ],
        ),
      ),
    ),
  );
}
```

- [ ] **Step 5: Chạy test để thấy pass**

Run: `flutter test test/features/groups/group_invite_qr_sheet_test.dart`
Expected: PASS

- [ ] **Step 6: Viết `qr_scan_screen.dart`**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Màn quét QR dùng chung. Trả về chuỗi đã quét khi [validate] trả `null`;
/// ngược lại hiện lỗi và quét tiếp. Không gọi server.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({required this.title, required this.validate, super.key});

  final String title;
  final String? Function(String raw) validate;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final raw = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (raw == null) return;
    final error = widget.validate(raw);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    _done = true;
    Navigator.pop(context, raw);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => ColoredBox(
              color: theme.colorScheme.surface,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Không mở được camera. Hãy cấp quyền camera trong Cài đặt, '
                    'hoặc quay lại và chọn "Nhập mã mời".',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 264,
              height: 264,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
          if (_error != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 32,
              child: Material(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 7: Nối vào `group_screen.dart`**

Thêm import:

```dart
import '../../../shared/widgets/qr_scan_screen.dart';
import '../domain/invite_link.dart';
import 'group_invite_qr_sheet.dart';
```

Thêm enum ở cuối file:

```dart
enum _JoinMethod { scan, type }
```

Thay `_joinGroup` trong `_GroupScreenState`:

```dart
  Future<void> _joinGroup() async {
    final method = await showModalBottomSheet<_JoinMethod>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Quét mã QR'),
              onTap: () => Navigator.pop(context, _JoinMethod.scan),
            ),
            ListTile(
              leading: const Icon(Icons.keyboard_outlined),
              title: const Text('Nhập mã mời'),
              onTap: () => Navigator.pop(context, _JoinMethod.type),
            ),
          ],
        ),
      ),
    );
    if (method == null || !mounted) return;
    final String? code;
    switch (method) {
      case _JoinMethod.scan:
        final raw = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => QrScanScreen(
              title: 'Quét mã mời nhóm',
              validate: (raw) => InviteLink.parse(raw) is GroupInviteLink
                  ? null
                  : 'Mã QR này không phải mã mời nhóm.',
            ),
          ),
        );
        code = switch (raw == null ? null : InviteLink.parse(raw)) {
          GroupInviteLink(code: final value) => value,
          null => null,
        };
      case _JoinMethod.type:
        code = await _askText(
          title: 'Tham gia nhóm',
          label: 'Mã mời',
          hint: 'Nhập mã 8 ký tự',
          confirmLabel: 'Tham gia',
        );
    }
    if (code == null) return;
    final inviteCode = code;
    ExpenseGroup? joinedGroup;
    await _runGroupAction(() async {
      joinedGroup = await ref
          .read(expenseGroupServiceProvider)!
          .joinGroup(inviteCode);
    });
    final group = joinedGroup;
    if (!mounted || group == null) return;
    await context.push('/groups/${group.id}');
  }
```

Trong `_GroupDetails`: đổi field `onCopyCode` thành `onShowInviteQr` (cả tham số constructor `required this.onShowInviteQr` và khai báo `final VoidCallback onShowInviteQr;`), rồi thay khối

```dart
                Text('Mã mời: ${details.group.inviteCode}'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onCopyCode,
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Sao chép mã mời'),
                  ),
                ),
```

bằng

```dart
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onShowInviteQr,
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('QR mời vào nhóm'),
                  ),
                ),
```

Ở chỗ tạo `_GroupDetails` trong `_GroupDetailScreenState.build`, thay `onCopyCode: () => _copyInviteCode(groupDetails.group.inviteCode),` bằng:

```dart
                      onShowInviteQr: () => showGroupInviteQrSheet(
                        context,
                        groupName: groupDetails.group.name,
                        inviteCode: groupDetails.group.inviteCode,
                      ),
```

Xóa method `_copyInviteCode` (bottom sheet đã có nút sao chép).

- [ ] **Step 8: Cập nhật test điều hướng**

Trong `test/features/groups/group_navigation_test.dart`, thay hai dòng 73 và 79:

```dart
    expect(find.text('QR mời vào nhóm'), findsNothing);
```

```dart
    expect(find.text('QR mời vào nhóm'), findsOneWidget);
```

- [ ] **Step 9: Chạy analyze và toàn bộ test**

Run: `dart format lib test && flutter analyze && flutter test`
Expected: `No issues found!`, mọi test PASS. Xóa import `flutter/services.dart` khỏi `group_screen.dart` nếu analyze báo không còn dùng.

- [ ] **Step 10: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/shared/widgets/qr_scan_screen.dart lib/features/groups/presentation/group_invite_qr_sheet.dart lib/features/groups/presentation/group_screen.dart test/features/groups/group_invite_qr_sheet_test.dart test/features/groups/group_navigation_test.dart
git commit -m "feat: invite to groups with QR codes and join by scanning

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Thẻ tiến độ và dialog mục tiêu ở màn quỹ

**Files:**
- Create: `lib/features/groups/presentation/fund_progress_card.dart`
- Modify: `lib/features/groups/presentation/group_fund_screen.dart`
- Test: `test/features/groups/fund_progress_card_test.dart`

**Interfaces:**
- Consumes: `GroupFundProgress`, `GroupFundStatus` (Task 4); `ExpenseGroup.fundGoalMinor`, `fundDeadline`, `ExpenseGroupService.setFundGoal` (Task 5).
- Produces: `class FundProgressCard extends StatelessWidget { const FundProgressCard({required int balanceMinor, required int? goalMinor, required DateTime? deadline, required bool isOwner, required VoidCallback onEditGoal, DateTime? today}); }`

- [ ] **Step 1: Viết test fail**

`test/features/groups/fund_progress_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/groups/presentation/fund_progress_card.dart';

Future<void> _pump(WidgetTester tester, FundProgressCard card) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: card)));

void main() {
  final today = DateTime(2026, 10, 20);

  testWidgets('thành viên không thấy gì khi chưa có mục tiêu', (tester) async {
    await _pump(
      tester,
      FundProgressCard(
        balanceMinor: 0,
        goalMinor: null,
        deadline: null,
        isOwner: false,
        onEditGoal: () {},
        today: today,
      ),
    );
    expect(find.text('Đặt mục tiêu quỹ'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('trưởng nhóm thấy nút đặt mục tiêu khi chưa có', (
    tester,
  ) async {
    var tapped = false;
    await _pump(
      tester,
      FundProgressCard(
        balanceMinor: 0,
        goalMinor: null,
        deadline: null,
        isOwner: true,
        onEditGoal: () => tapped = true,
        today: today,
      ),
    );
    await tester.tap(find.text('Đặt mục tiêu quỹ'));
    expect(tapped, isTrue);
  });

  testWidgets('đang góp hiện phần trăm và số ngày còn lại', (tester) async {
    await _pump(
      tester,
      FundProgressCard(
        balanceMinor: 6400000,
        goalMinor: 10000000,
        deadline: DateTime(2026, 12, 15),
        isOwner: false,
        onEditGoal: () {},
        today: today,
      ),
    );
    expect(find.textContaining('64%'), findsOneWidget);
    expect(find.text('Còn 56 ngày'), findsOneWidget);
    expect(find.byTooltip('Sửa mục tiêu'), findsNothing);
  });

  testWidgets('vượt mục tiêu hiện 150% và thanh đầy', (tester) async {
    await _pump(
      tester,
      FundProgressCard(
        balanceMinor: 1500,
        goalMinor: 1000,
        deadline: null,
        isOwner: true,
        onEditGoal: () {},
        today: today,
      ),
    );
    expect(find.textContaining('150%'), findsOneWidget);
    expect(find.text('Đã đạt mục tiêu'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 1.0);
  });

  testWidgets('quá hạn chưa đạt', (tester) async {
    await _pump(
      tester,
      FundProgressCard(
        balanceMinor: 100,
        goalMinor: 1000,
        deadline: DateTime(2026, 10, 17),
        isOwner: false,
        onEditGoal: () {},
        today: today,
      ),
    );
    expect(find.text('Quá hạn 3 ngày'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run: `flutter test test/features/groups/fund_progress_card_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Viết `fund_progress_card.dart`**

```dart
import 'package:flutter/material.dart';

import '../../../app/theme/finance_colors.dart';
import '../../../core/utils/money_formatter.dart';
import '../domain/group_fund_progress.dart';

class FundProgressCard extends StatelessWidget {
  const FundProgressCard({
    required this.balanceMinor,
    required this.goalMinor,
    required this.deadline,
    required this.isOwner,
    required this.onEditGoal,
    this.today,
    super.key,
  });

  final int balanceMinor;
  final int? goalMinor;
  final DateTime? deadline;
  final bool isOwner;
  final VoidCallback onEditGoal;

  /// Chỉ để test; mặc định là thời điểm hiện tại.
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final progress = GroupFundProgress.compute(
      balanceMinor: balanceMinor,
      goalMinor: goalMinor,
      deadline: deadline,
      today: today ?? DateTime.now(),
    );
    if (progress.status == GroupFundStatus.noGoal) {
      if (!isOwner) return const SizedBox.shrink();
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: onEditGoal,
          icon: const Icon(Icons.flag_outlined),
          label: const Text('Đặt mục tiêu quỹ'),
        ),
      );
    }
    final theme = Theme.of(context);
    final finance = theme.extension<AppFinanceColors>();
    final color = switch (progress.status) {
      GroupFundStatus.reached =>
        finance?.budgetSafe.color ?? theme.colorScheme.primary,
      GroupFundStatus.overdue =>
        finance?.budgetWarn.color ?? theme.colorScheme.error,
      _ => theme.colorScheme.primary,
    };
    final ratio = progress.ratio!;
    final percent = (ratio * 100).floor();
    final daysLeft = progress.daysLeft;
    final statusText = switch (progress.status) {
      GroupFundStatus.reached => 'Đã đạt mục tiêu',
      GroupFundStatus.overdue => 'Quá hạn ${-daysLeft!} ngày',
      _ when daysLeft == null => '',
      _ when daysLeft == 0 => 'Hạn hôm nay',
      _ => 'Còn $daysLeft ngày',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Mục tiêu quỹ', style: theme.textTheme.titleMedium),
                ),
                if (isOwner)
                  IconButton(
                    tooltip: 'Sửa mục tiêu',
                    onPressed: onEditGoal,
                    icon: const Icon(Icons.edit_outlined),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0).toDouble(),
              color: color,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Text('$percent% của ${MoneyFormatter.format(goalMinor!)}'),
            if (statusText.isNotEmpty)
              Text(
                statusText,
                style: TextStyle(
                  color: progress.status == GroupFundStatus.inProgress
                      ? null
                      : color,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Chạy test để thấy pass**

Run: `flutter test test/features/groups/fund_progress_card_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Nối vào `group_fund_screen.dart`**

Thêm import:

```dart
import 'fund_progress_card.dart';
```

Thêm method vào `_GroupFundScreenState` (sau `_delete`):

```dart
  Future<void> _editGoal(ExpenseGroup group) async {
    final result = await showDialog<({int? goalMinor, DateTime? deadline})>(
      context: context,
      builder: (_) => _FundGoalDialog(
        initialGoalMinor: group.fundGoalMinor,
        initialDeadline: group.fundDeadline,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(expenseGroupServiceProvider)!
          .setFundGoal(
            groupId: widget.groupId,
            goalMinor: result.goalMinor,
            deadline: result.deadline,
          );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyMessage(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refresh(force: true);
      }
    }
  }
```

Trong `build`, ngay sau `Card` số dư và trước `const SizedBox(height: 12), Row(` các nút thu/chi, chèn:

```dart
            const SizedBox(height: 12),
            FundProgressCard(
              balanceMinor: balance,
              goalMinor: data.details.group.fundGoalMinor,
              deadline: data.details.group.fundDeadline,
              isOwner: data.details.group.ownerId == currentUserId,
              onEditGoal: () => _editGoal(data.details.group),
            ),
```

Thêm dialog ở cuối file:

```dart
class _FundGoalDialog extends StatefulWidget {
  const _FundGoalDialog({this.initialGoalMinor, this.initialDeadline});

  final int? initialGoalMinor;
  final DateTime? initialDeadline;

  @override
  State<_FundGoalDialog> createState() => _FundGoalDialogState();
}

class _FundGoalDialogState extends State<_FundGoalDialog> {
  late final TextEditingController _amountController = TextEditingController(
    text: widget.initialGoalMinor?.toString(),
  );
  late DateTime? _deadline = widget.initialDeadline;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = _deadline;
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null || current.isBefore(today) ? today : current,
      firstDate: today,
      lastDate: DateTime(today.year + 10, 12, 31),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  void _save() {
    final amount = MoneyFormatter.tryParse(_amountController.text);
    if (amount == null || amount < 1 || amount > 9007199254740991) {
      setState(() => _error = 'Nhập số tiền mục tiêu hợp lệ.');
      return;
    }
    Navigator.pop(context, (goalMinor: amount, deadline: _deadline));
  }

  @override
  Widget build(BuildContext context) {
    final deadline = _deadline;
    return AlertDialog(
      title: const Text('Mục tiêu quỹ'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _amountController,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Số tiền mục tiêu',
              suffixText: '₫',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  deadline == null
                      ? 'Không có hạn'
                      : 'Hạn ${deadline.day}/${deadline.month}/${deadline.year}',
                ),
              ),
              TextButton(
                onPressed: _pickDeadline,
                child: Text(deadline == null ? 'Chọn hạn' : 'Đổi hạn'),
              ),
              if (deadline != null)
                IconButton(
                  tooltip: 'Bỏ hạn',
                  onPressed: () => setState(() => _deadline = null),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      actions: [
        if (widget.initialGoalMinor != null)
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              (goalMinor: null, deadline: null),
            ),
            child: const Text('Xóa mục tiêu'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _save, child: const Text('Lưu')),
      ],
    );
  }
}
```

`MoneyFormatter` và `ExpenseGroup` (qua `group_models.dart`) đã được import sẵn trong file này.

- [ ] **Step 6: Chạy analyze và toàn bộ test**

Run: `dart format lib test && flutter analyze && flutter test`
Expected: `No issues found!`, mọi test PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/groups/presentation/fund_progress_card.dart lib/features/groups/presentation/group_fund_screen.dart test/features/groups/fund_progress_card_test.dart
git commit -m "feat: show group fund goal progress and let the leader set it

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Kiểm tra toàn nhánh

**Files:** không đổi code, trừ khi bước kiểm tra lộ lỗi.

- [ ] **Step 1: Chạy đúng các bước CI**

```bash
flutter pub get
dart run build_runner build
git diff --exit-code
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
flutter build web
```

Expected: mọi lệnh exit 0; `git diff --exit-code` không có thay đổi file sinh.

- [ ] **Step 2: Chạy lại pgTAP từ DB sạch**

Run: `npx supabase db reset && npx supabase test db`
Expected: `All tests successful.`

- [ ] **Step 3: Kiểm tra tay trên thiết bị Android thật (hai tài khoản)**

Chạy: `flutter run --dart-define=APP_ENV=dev --dart-define-from-file=config/supabase.local.json` với Supabase local hoặc staging đã `db push`.

1. Tài khoản A tạo nhóm, mở "QR mời vào nhóm" ở chế độ tối và sáng: QR nền trắng, mã chữ đúng, "Sao chép mã" báo đã sao chép.
2. Tài khoản B: "Tham gia" → "Quét mã QR" → quét QR trên máy A → vào đúng nhóm.
3. B quét một mã VietQR bất kỳ → hiện "Mã QR này không phải mã mời nhóm.", màn quét vẫn mở.
4. B từ chối quyền camera → màn quét hiện hướng dẫn; quay lại chọn "Nhập mã mời" vẫn tham gia được.
5. B nhập sai mã 11 lần trong một phút → lần thứ 11 hiện "Bạn đã thử quá nhiều mã. Hãy thử lại sau một phút."
6. A vào quỹ → "Đặt mục tiêu quỹ" → 10.000.000 ₫, hạn sau 56 ngày → thẻ hiện "…% của 10.000.000 ₫", "Còn 56 ngày". B không thấy nút đặt/sửa.
7. B "Chi từ quỹ" vượt số dư → snackbar "Quỹ không đủ tiền cho khoản chi này".
8. A bấm "Chia tiền" → tab "Quét hóa đơn" → "Chụp ảnh hóa đơn" → biểu mẫu điền sẵn "Hóa đơn <tên quán>" và tổng tiền; chọn thành viên, bấm "Chia tiền" → lần chia xuất hiện trong mục "Chia tiền", chia đều đúng. Thử thêm tab "Nhập thủ công" chia theo số tiền.
9. Màn nhóm chỉ còn một nút "Chia tiền"; thu chi của quỹ chỉ có ở màn quỹ.

- [ ] **Step 4: Báo kết quả**

Ghi lại lệnh đã chạy và kết quả (pass/fail kèm dòng lỗi). Không push, không mở PR cho đến khi người dùng yêu cầu.
