# QR mời vào bill cho người ngoài nhóm — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mỗi bill (một lần chia tiền) có QR/mã 10 ký tự riêng; người trong hay ngoài nhóm quét để vào đúng bill, bill chia đều tự chia lại, người ngoài thấy bill ở mục "Bill bạn tham gia", đánh dấu đã trả hoặc rời bill, còn nhóm thấy khách trong bill và trong nhật ký.

**Architecture:** Một migration Supabase thêm cột lời mời/cách chia/tên khách, sáu RPC mới (`open_group_bill_invite`, `close_group_bill_invite`, `join_group_bill`, `leave_group_bill`, `list_my_external_bills`, hàm nội bộ `rebalance_equal_bill`), bản 5 tham số của `update_group_expense_custom`, và `create or replace` bốn RPC có sẵn; RLS các bảng nhóm không đổi, người ngoài chỉ đọc qua RPC. Phía Flutter mở rộng `InviteLink`, model, `GroupBalanceCalculator`, `ExpenseGroupService`, thêm bottom sheet QR bill, mục "Bill bạn tham gia" và cho nút "Tham gia" nhận cả mã bill.

**Tech Stack:** Flutter 3.47.1 / Dart ^3.12, Riverpod 2.6, `supabase_flutter` 2.x, `qr_flutter` 4.1, `mobile_scanner` 7.4, `http` (đã là dependency, dùng `MockClient` trong test), PostgreSQL / Supabase, pgTAP qua `npx supabase test db`.

**Spec:** `docs/superpowers/specs/2026-10-21-bill-qr-join-design.md`

## Global Constraints

- Flutter `3.47.1` ở `~/flutter/bin`: mọi lệnh Flutter chạy sau `export PATH=$HOME/flutter/bin:$PATH`. Không thêm dependency mới.
- Migration duy nhất: `supabase/migrations/20261022100000_bill_qr_join.sql`; không sửa migration cũ. Thứ tự triển khai: spec A (`20261021100000`) rồi spec B.
- Hàm SQL mới: `security definer`, `set search_path = ''`, `revoke all ... from public, anon`, `grant execute ... to authenticated`. Riêng `rebalance_equal_bill`: `security invoker`, revoke khỏi `public, anon, authenticated`.
- Hàm `create or replace` copy nguyên thân hàm mới nhất trong `supabase/migrations`, chỉ đổi đúng chỗ spec yêu cầu, giữ `search_path` gốc (grant được Postgres giữ nguyên khi `create or replace`).
- Lỗi người dùng đọc được dùng SQLSTATE `UF001` (app hiện nguyên câu qua `friendlyMessage`); lỗi kỹ thuật giữ mã cũ (`28000`, `22023`, `42501`).
- Mã nhóm 8 ký tự, mã bill 10 ký tự `[0-9A-F]`, phân biệt bằng độ dài; QR bill chứa đúng `hoadoninsight://join-bill?code=<CODE>`.
- Giới hạn thử mã dùng chung bảng `expense_group_join_rate_limits` với `join_expense_group`: 10 lần mỗi cửa sổ 1 phút, tăng đếm trước khi tra mã, không đặt lại khi thành công.
- Bill tối đa 100 split; `list_my_external_bills` tối đa 100 bill, mới nhất trước; `participant_name` tối đa 80 ký tự, rỗng → `'Khách'`.
- RLS `group_expenses`, `group_expense_splits`, `expense_group_members`, `group_fund_entries`, `group_audit_events` không đổi. `list_my_external_bills` không trả `group_id`, tên nhóm hay `user_id` của người khác.
- Gợi ý tất toán của nhóm chỉ tính giữa thành viên nhóm; nợ của người ngoài chỉ hiện trong bill.
- Không push notification, không deep link từ camera hệ thống. Mọi chữ hiển thị tiếng Việt.
- Tiền luôn là `int` đơn vị nhỏ nhất, tối đa `9007199254740991`.
- Trước mỗi commit Flutter: `dart format lib test` rồi `flutter analyze` sạch (CI fail khi có cảnh báo).
- Commit message kết thúc bằng dòng `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Người trả sửa một bill chia đều đã có khách → dialog sửa mở ở "Đều", có dòng "Dũng (Khách)", lưu xong khách vẫn trong bill và bill vẫn `split_mode = 'equal'` để người vào sau còn được chia lại (Task 5: `group_expense_dialog_test.dart`, `group_bill_guest_test.dart`).
2. Khách vào bill thủ công nhận 0đ → mục "Bill bạn tham gia" hiện "Chờ người trả chia lại phần tiền", không có nút "Tôi đã thanh toán" (bấm nhầm sẽ đóng lời mời của cả bill) (Task 6).
3. Mã gõ tay chữ thường hoặc có khoảng trắng → vẫn vào đúng (10 ký tự là bill, 8 ký tự là nhóm); mã 9 hoặc 11 ký tự → báo lỗi ngay, không gọi server, không tốn lượt thử (Task 7, Task 2).
4. Thành viên nhóm quét QR bill của chính nhóm mình → mở màn nhóm, bill không hiện ở "Bill bạn tham gia" (Task 7 widget test; Task 1 pgTAP: `list_my_external_bills` của thành viên trả `[]`).
5. Nhật ký nhóm khi khách vào/rời bill → "Dũng đã vào bill “Ăn tối”", "Khách đã rời bill “Ăn tối”"; không hiện "Tài khoản đã xóa" hay "Có hoạt động mới trong nhóm" (Task 5).

## File Structure

| File | Trách nhiệm |
|---|---|
| `supabase/migrations/20261022100000_bill_qr_join.sql` (mới) | Cột mới, constraint audit, 6 hàm mới, bản 5 tham số `update_group_expense_custom`, sửa `settle_group_split`, `create_group_expense`, `create_group_expense_from_invoice`, bản 4 tham số |
| `supabase/tests/bill_qr_join_test.sql` (mới) | pgTAP cho spec §6.1 |
| `lib/features/groups/domain/invite_link.dart` | Thêm `BillInviteLink`, `billUri` |
| `lib/features/groups/domain/group_models.dart` | `GroupExpense.splitMode/joinOpen/joinCode`, `GroupExpenseSplit.participantName` |
| `lib/features/groups/domain/external_bill.dart` (mới) | `ExternalBill`, `ExternalBillParticipant` parse JSON |
| `lib/features/groups/domain/group_balance_calculator.dart` | Bỏ qua người ngoài nhóm |
| `lib/features/groups/data/group_service.dart` | Đọc cột mới; 6 hàm mới; `updateCustomExpense(splitMode:)` |
| `lib/core/providers/app_providers.dart` | `externalBillsProvider` |
| `lib/features/groups/presentation/bill_invite_qr_sheet.dart` (mới) | Bottom sheet QR bill |
| `lib/features/groups/presentation/external_bills_section.dart` (mới) | Mục "Bill bạn tham gia" |
| `lib/features/groups/presentation/group_expense_dialog.dart` | `GroupExpenseDraft.equalSplit`; sửa bill chia đều mở ở "Đều" |
| `lib/features/groups/presentation/group_screen.dart` | Menu "QR mời vào bill", tên khách, nhật ký, sửa bill gửi `splitMode`, mục bill, kéo làm mới, "Tham gia" nhận mã bill |

---

### Task 1: Migration và pgTAP

**Files:**
- Create: `supabase/migrations/20261022100000_bill_qr_join.sql`
- Create: `supabase/tests/bill_qr_join_test.sql`

**Interfaces:**
- Consumes: bảng `group_expenses`, `group_expense_splits` (không có PK; unique index `(expense_id, user_id)`; `user_id` nullable), `expense_group_members`, `expense_groups`, `profiles` (trigger `handle_new_user` tạo dòng với `display_name = ''`), `expense_group_join_rate_limits`, `group_audit_events`; hàm `is_expense_group_member(uuid, uuid)`, `add_group_fund_entry(...)`, `create_group_expense_custom(uuid, text, bigint, jsonb)`.
- Produces:
  - Cột `group_expenses.join_code text unique null`, `join_open boolean not null default false`, `split_mode text not null default 'custom'` (`'equal'|'custom'`); `group_expense_splits.participant_name text null`, `joined_at timestamptz not null default now()`.
  - `event_type` thêm `'bill_joined'`, `'bill_left'` (`actor_id = target_user_id =` người vào/rời, có `expense_id`).
  - RPC: `open_group_bill_invite(p_expense_id uuid) returns text`, `close_group_bill_invite(p_expense_id uuid) returns void`, `join_group_bill(p_code text) returns uuid` (null khi mã không tồn tại), `leave_group_bill(p_expense_id uuid) returns void`, `list_my_external_bills() returns jsonb` (mảng object khóa `id, description, total_minor, created_at, payer_name, is_open, my_amount_minor, my_settled_at, participants[{name, amount_minor, settled, is_me}]`), `update_group_expense_custom(p_expense_id uuid, p_description text, p_total_minor bigint, p_splits jsonb, p_split_mode text) returns void`.
  - Câu `UF001`: `Chỉ người trả hoặc trưởng nhóm được mời vào bill`, `Bill đã có người thanh toán, không mời thêm được`, `Bill này đã đóng lời mời`, `Bill đã đủ 100 người`, `Bạn đã thử quá nhiều mã. Hãy thử lại sau một phút.`, `Bạn không ở trong bill này`, `Người trả không rời bill được`, `Bill đã có người thanh toán, không rời được`, `Bill phải còn ít nhất một người`.

Cần Docker. Nếu Supabase local chưa chạy: `npx supabase start` (lần đầu tải image, vài phút).

Ghi chú cho người làm:
- Nguồn copy: `create_group_expense` từ `20260918060000_group_expense_hardening.sql` (bản này không ghi audit — giữ nguyên), `create_group_expense_from_invoice` từ `20260918160000_bill_sharing.sql`, `settle_group_split` từ `20260917200000_group_settlement_idempotency.sql` (`search_path = public`), `update_group_expense_custom` 4 tham số từ `20261021100000_group_qr_fund_goal.sql` (`search_path = public, pg_temp`), constraint audit từ `20260920100000_group_expense_lifecycle.sql`. `create_group_expense_custom` và `create_group_expense_custom_from_invoice` không đổi (mặc định cột là `'custom'`).
- Bản 5 tham số là hàm mới (overload) nên dùng `search_path = ''`; không có default cho `p_split_mode` để PostgREST không mơ hồ giữa hai bản. Bản 4 tham số giữ chữ ký, `search_path`, grant, thân chỉ gọi bản 5 tham số với `'custom'`.
- Bản 5 tham số thay "xóa hết split rồi chèn lại" bằng xóa split không còn trong danh sách + `insert ... on conflict (expense_id, user_id) do update`, nhờ vậy split có sẵn giữ `participant_name` và `joined_at`.
- `settle_group_split` thêm `for update of e` để tuần tự với `join_group_bill`/`leave_group_bill` (spec §5); hai câu lỗi cũ gộp thành `Không tìm thấy phần chia của bạn` vì điều kiện mới chỉ còn "caller có split".
- `join_group_bill` khóa bill ngay lúc tra mã (trước bước "đã có split"), để hai lần vào đồng thời của cùng người không đụng unique index.
- `rebalance_equal_bill` cập nhật theo `ctid` vì bảng split không có khóa chính và `user_id` có thể null.
- Trong một transaction `now()` không đổi, nên test đẩy `joined_at` của B lên sau 1 phút để kiểm tra thứ tự `(joined_at, user_id)` thật sự.

- [ ] **Step 1: Viết test pgTAP (sẽ fail vì chưa có migration)**

Tạo `supabase/tests/bill_qr_join_test.sql`:

```sql
begin;
create extension if not exists pgtap with schema extensions;
select plan(51);

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

-- Nhật ký nhóm ghi lại người vào và rời bill
select results_eq(
  $$select event_type, count(*) from public.group_audit_events
    where event_type in ('bill_joined', 'bill_left')
      and actor_id = target_user_id
    group by event_type order by event_type$$,
  $$values ('bill_joined'::text, 3::bigint), ('bill_left'::text, 2::bigint)$$,
  'audit ghi bill_joined và bill_left với actor là người vào/rời'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Chạy test để thấy fail**

Run: `npx supabase db reset && npx supabase test db`
Expected: FAIL — `bill_qr_join_test.sql` báo `ERROR:  column "join_code" does not exist` và `You planned 51 tests but ran 0`; `group_qr_fund_goal_test.sql .. ok`.

- [ ] **Step 3: Viết migration**

Tạo `supabase/migrations/20261022100000_bill_qr_join.sql`:

```sql
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
```

- [ ] **Step 4: Chạy lại test và lint**

Run: `npx supabase db reset && npx supabase test db`
Expected: `bill_qr_join_test.sql ........ ok`, `group_qr_fund_goal_test.sql .. ok`, `All tests successful.`, `Files=2, Tests=72`.

Run: `npx supabase db lint`
Expected: `No schema errors found`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20261022100000_bill_qr_join.sql supabase/tests/bill_qr_join_test.sql
git commit -m "feat: let people join a single bill by QR code on the server

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `InviteLink` nhận mã bill

**Files:**
- Modify: `lib/features/groups/domain/invite_link.dart` (thay toàn bộ)
- Test: `test/features/groups/invite_link_test.dart`

**Interfaces:**
- Consumes: không.
- Produces: `final class BillInviteLink extends InviteLink { const BillInviteLink(this.code); final String code; }` (mã đã chuẩn hóa in hoa); `InviteLink.parse(String raw)` nhận thêm host `join-bill` và mã trơn 10 ký tự; `static String InviteLink.billUri(String code)`. `GroupInviteLink` và `groupUri` giữ nguyên. Vì `InviteLink` là `sealed`, mọi `switch` không có nhánh `_` phải xử lý `BillInviteLink`.

- [ ] **Step 1: Viết test fail**

Trong `test/features/groups/invite_link_test.dart`, thay helper đầu file:

```dart
String? _groupCode(String raw) => switch (InviteLink.parse(raw)) {
  GroupInviteLink(:final code) => code,
  null => null,
};
```

bằng:

```dart
String? _groupCode(String raw) => switch (InviteLink.parse(raw)) {
  GroupInviteLink(:final code) => code,
  BillInviteLink() || null => null,
};

String? _billCode(String raw) => switch (InviteLink.parse(raw)) {
  BillInviteLink(:final code) => code,
  GroupInviteLink() || null => null,
};
```

Rồi thêm các test sau vào cuối `main()` (trước dấu `}` cuối file):

```dart
  test('đọc mã từ URI mời vào bill', () {
    expect(
      _billCode('hoadoninsight://join-bill?code=ABCDEF1234'),
      'ABCDEF1234',
    );
    expect(
      _billCode('hoadoninsight://join-bill?code=abcdef1234'),
      'ABCDEF1234',
    );
  });

  test('mã trơn 10 ký tự là mã bill, không phải mã nhóm', () {
    expect(_billCode('  abcdef1234 \n'), 'ABCDEF1234');
    expect(_groupCode('ABCDEF1234'), isNull);
  });

  test('mã bill 9 hoặc 11 ký tự bị từ chối', () {
    expect(InviteLink.parse('ABCDEF123'), isNull);
    expect(InviteLink.parse('ABCDEF12345'), isNull);
    expect(_billCode('hoadoninsight://join-bill?code=ABCD1234'), isNull);
    expect(_billCode('hoadoninsight://join-bill?code=ABCDEF12345'), isNull);
    expect(_billCode('hoadoninsight://join-bill?code=ABCDEF123G'), isNull);
  });

  test('URI nhóm vẫn ra GroupInviteLink', () {
    expect(
      InviteLink.parse('hoadoninsight://join-group?code=ABCD1234'),
      isA<GroupInviteLink>(),
    );
    expect(_groupCode('hoadoninsight://join-group?code=ABCDEF1234'), isNull);
  });

  test('billUri rồi parse cho lại đúng mã', () {
    final uri = InviteLink.billUri('ABCDEF1234');
    expect(uri, 'hoadoninsight://join-bill?code=ABCDEF1234');
    expect(_billCode(uri), 'ABCDEF1234');
  });
```

- [ ] **Step 2: Chạy test để thấy fail**

Run: `flutter test test/features/groups/invite_link_test.dart`
Expected: FAIL — lỗi biên dịch: `BillInviteLink` chưa được định nghĩa (`'BillInviteLink' isn't a type`).

- [ ] **Step 3: Viết implementation**

Thay toàn bộ `lib/features/groups/domain/invite_link.dart`:

```dart
/// Nội dung QR mời: vào nhóm (mã 8 ký tự) hoặc vào một bill (mã 10 ký tự).
sealed class InviteLink {
  const InviteLink();

  static const _scheme = 'hoadoninsight';
  static const _groupHost = 'join-group';
  static const _billHost = 'join-bill';
  static final _groupCodePattern = RegExp(r'^[0-9A-F]{8}$');
  static final _billCodePattern = RegExp(r'^[0-9A-F]{10}$');

  /// Nhận URI `hoadoninsight://join-group?code=...`,
  /// `hoadoninsight://join-bill?code=...` hoặc mã trơn (8 ký tự là nhóm,
  /// 10 ký tự là bill). Trả `null` khi không phải mã mời hợp lệ.
  static InviteLink? parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri != null && uri.hasScheme) {
      if (uri.scheme != _scheme) return null;
      final code = uri.queryParameters['code'];
      return switch (uri.host) {
        _groupHost => _group(code),
        _billHost => _bill(code),
        _ => null,
      };
    }
    return _group(text) ?? _bill(text);
  }

  static String groupUri(String code) => _uri(_groupHost, code);

  static String billUri(String code) => _uri(_billHost, code);

  static String _uri(String host, String code) => Uri(
    scheme: _scheme,
    host: host,
    queryParameters: {'code': code},
  ).toString();

  static String? _normalize(String? code, RegExp pattern) {
    final normalized = code?.trim().toUpperCase();
    if (normalized == null || !pattern.hasMatch(normalized)) return null;
    return normalized;
  }

  static GroupInviteLink? _group(String? code) {
    final normalized = _normalize(code, _groupCodePattern);
    return normalized == null ? null : GroupInviteLink(normalized);
  }

  static BillInviteLink? _bill(String? code) {
    final normalized = _normalize(code, _billCodePattern);
    return normalized == null ? null : BillInviteLink(normalized);
  }
}

final class GroupInviteLink extends InviteLink {
  const GroupInviteLink(this.code);

  final String code;
}

final class BillInviteLink extends InviteLink {
  const BillInviteLink(this.code);

  final String code;
}
```

`group_screen.dart` hiện dùng `switch` có nhánh `_ => null` nên vẫn biên dịch; Task 7 sẽ đổi luồng "Tham gia".

- [ ] **Step 4: Chạy test**

Run: `flutter test test/features/groups/invite_link_test.dart`
Expected: PASS (11 tests).

- [ ] **Step 5: Format, analyze, commit**

Run: `dart format lib test && flutter analyze`
Expected: `No issues found!`

```bash
git add lib/features/groups/domain/invite_link.dart test/features/groups/invite_link_test.dart
git commit -m "feat: parse and build bill invite links

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Model, `ExternalBill` và số dư chỉ giữa thành viên

**Files:**
- Modify: `lib/features/groups/domain/group_models.dart:55-91`
- Create: `lib/features/groups/domain/external_bill.dart`
- Modify: `lib/features/groups/domain/group_balance_calculator.dart` (thay toàn bộ)
- Test: `test/features/groups/external_bill_test.dart` (mới), `test/features/groups/group_balance_calculator_test.dart`

**Interfaces:**
- Consumes: JSON của `list_my_external_bills` (Task 1).
- Produces:
  - `GroupExpenseSplit({required String? userId, required int amountMinor, DateTime? settledAt, String? participantName})`.
  - `GroupExpense({..., String splitMode = 'custom', bool joinOpen = false, String? joinCode})` — default giữ các chỗ tạo `GroupExpense` cũ (test) biên dịch được.
  - `class ExternalBill { String id; String description; int totalMinor; DateTime createdAt; String payerName; bool isOpen; int myAmountMinor; DateTime? mySettledAt; List<ExternalBillParticipant> participants; bool get isMineSettled; bool get hasSettlement; factory ExternalBill.fromJson(Object? value); }` — sai/thiếu trường ném `FormatException`.
  - `class ExternalBillParticipant { String name; int amountMinor; bool settled; bool isMe; factory ExternalBillParticipant.fromJson(Object? value); }`.
  - `GroupBalanceCalculator.calculate` chỉ trả khóa thuộc `memberIds`.

- [ ] **Step 1: Viết test fail**

Tạo `test/features/groups/external_bill_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/groups/domain/external_bill.dart';

Map<String, dynamic> _json() => {
  'id': '6f1c2b8e-4a1d-4c3e-9b2a-1d2e3f4a5b6c',
  'description': 'Ăn tối',
  'total_minor': 600000,
  'created_at': '2026-10-21T12:00:00+00:00',
  'payer_name': 'Huy',
  'is_open': true,
  'my_amount_minor': 200000,
  'my_settled_at': null,
  'participants': [
    {'name': 'Huy', 'amount_minor': 200000, 'settled': false, 'is_me': false},
    {'name': 'Lan', 'amount_minor': 200000, 'settled': true, 'is_me': false},
    {'name': 'Dũng', 'amount_minor': 200000, 'settled': false, 'is_me': true},
  ],
};

void main() {
  test('đọc đủ trường của list_my_external_bills', () {
    final bill = ExternalBill.fromJson(_json());

    expect(bill.id, '6f1c2b8e-4a1d-4c3e-9b2a-1d2e3f4a5b6c');
    expect(bill.description, 'Ăn tối');
    expect(bill.totalMinor, 600000);
    expect(bill.createdAt, DateTime.utc(2026, 10, 21, 12).toLocal());
    expect(bill.payerName, 'Huy');
    expect(bill.isOpen, isTrue);
    expect(bill.myAmountMinor, 200000);
    expect(bill.mySettledAt, isNull);
    expect(bill.isMineSettled, isFalse);
    expect(bill.hasSettlement, isTrue);
    expect(bill.participants.map((item) => item.name), ['Huy', 'Lan', 'Dũng']);
    expect(bill.participants.last.isMe, isTrue);
    expect(bill.participants[1].settled, isTrue);
  });

  test('my_settled_at có giá trị thì bill đã được mình thanh toán', () {
    final json = _json()..['my_settled_at'] = '2026-10-21T13:00:00+00:00';

    expect(ExternalBill.fromJson(json).isMineSettled, isTrue);
  });

  test('thiếu trường bắt buộc thì FormatException', () {
    for (final key in [
      'id',
      'description',
      'total_minor',
      'created_at',
      'payer_name',
      'is_open',
      'my_amount_minor',
      'participants',
    ]) {
      final json = _json()..remove(key);
      expect(
        () => ExternalBill.fromJson(json),
        throwsFormatException,
        reason: key,
      );
    }
  });

  test('người tham gia thiếu tên hoặc số tiền âm thì FormatException', () {
    final missingName = _json()
      ..['participants'] = [
        {'amount_minor': 1, 'settled': false, 'is_me': false},
      ];
    final negative = _json()
      ..['participants'] = [
        {'name': 'Lan', 'amount_minor': -1, 'settled': false, 'is_me': false},
      ];

    expect(() => ExternalBill.fromJson(missingName), throwsFormatException);
    expect(() => ExternalBill.fromJson(negative), throwsFormatException);
  });

  test('dữ liệu không phải object thì FormatException', () {
    expect(() => ExternalBill.fromJson('bill'), throwsFormatException);
  });
}
```

Thêm vào cuối `main()` của `test/features/groups/group_balance_calculator_test.dart` (trước dấu `}` cuối file):

```dart
  test('phần của người ngoài nhóm không vào số dư thành viên', () {
    for (final settled in [null, DateTime(2026, 10, 21)]) {
      final balances = GroupBalanceCalculator.calculate(
        memberIds: const ['payer', 'member'],
        expenses: [
          GroupExpense(
            id: 'expense-1',
            groupId: 'group-1',
            payerId: 'payer',
            description: 'Ăn tối',
            totalMinor: 300000,
            createdAt: DateTime(2026, 10, 21),
            splitMode: 'equal',
            splits: [
              const GroupExpenseSplit(userId: 'payer', amountMinor: 100000),
              const GroupExpenseSplit(userId: 'member', amountMinor: 100000),
              GroupExpenseSplit(
                userId: 'guest',
                amountMinor: 100000,
                settledAt: settled,
                participantName: 'Dũng',
              ),
            ],
          ),
        ],
      );

      expect(balances, {'payer': 100000, 'member': -100000});
    }
  });

  test('gợi ý tất toán chỉ giữa thành viên nhóm', () {
    final balances = GroupBalanceCalculator.calculate(
      memberIds: const ['payer', 'member'],
      expenses: [
        GroupExpense(
          id: 'expense-1',
          groupId: 'group-1',
          payerId: 'payer',
          description: 'Ăn tối',
          totalMinor: 300000,
          createdAt: DateTime(2026, 10, 21),
          splits: const [
            GroupExpenseSplit(userId: 'member', amountMinor: 100000),
            GroupExpenseSplit(userId: 'guest-1', amountMinor: 100000),
            GroupExpenseSplit(userId: 'guest-2', amountMinor: 100000),
          ],
        ),
      ],
    );
    final transfers = GroupBalanceCalculator.calculateSettlementTransfers(
      balances,
    );

    expect(
      transfers
          .map(
            (transfer) =>
                '${transfer.fromUserId}->${transfer.toUserId}:${transfer.amountMinor}',
          )
          .toList(),
      ['member->payer:100000'],
    );
  });

  test('người trả không thuộc nhóm thì bỏ qua phần được nhận', () {
    final balances = GroupBalanceCalculator.calculate(
      memberIds: const ['member'],
      expenses: [
        GroupExpense(
          id: 'expense-1',
          groupId: 'group-1',
          payerId: 'former-member',
          description: 'Taxi',
          totalMinor: 100000,
          createdAt: DateTime(2026, 10, 21),
          splits: const [
            GroupExpenseSplit(userId: 'member', amountMinor: 50000),
            GroupExpenseSplit(userId: 'former-member', amountMinor: 50000),
          ],
        ),
      ],
    );

    expect(balances, {'member': -50000});
  });
```

- [ ] **Step 2: Chạy test để thấy fail**

Run: `flutter test test/features/groups/external_bill_test.dart test/features/groups/group_balance_calculator_test.dart`
Expected: FAIL — lỗi biên dịch: thiếu `external_bill.dart`, `GroupExpense` không có tham số `splitMode`, `GroupExpenseSplit` không có `participantName`.

- [ ] **Step 3: Mở rộng model**

Trong `lib/features/groups/domain/group_models.dart`, thay:

```dart
class GroupExpenseSplit {
  const GroupExpenseSplit({
    required this.userId,
    required this.amountMinor,
    this.settledAt,
  });

  final String? userId;
  final int amountMinor;
  final DateTime? settledAt;
```

bằng:

```dart
class GroupExpenseSplit {
  const GroupExpenseSplit({
    required this.userId,
    required this.amountMinor,
    this.settledAt,
    this.participantName,
  });

  final String? userId;
  final int amountMinor;
  final DateTime? settledAt;

  /// Tên người ngoài nhóm vào bill qua QR; `null` với thành viên nhóm.
  final String? participantName;
```

Thay:

```dart
    this.sourceInvoiceId,
    this.sourceSnapshot,
  });
```

bằng:

```dart
    this.sourceInvoiceId,
    this.sourceSnapshot,
    this.splitMode = 'custom',
    this.joinOpen = false,
    this.joinCode,
  });
```

Thay:

```dart
  final Map<String, dynamic>? sourceSnapshot;

  bool get isSharedInvoice => sourceInvoiceId != null;
```

bằng:

```dart
  final Map<String, dynamic>? sourceSnapshot;

  /// `'equal'`: tự chia đều lại khi có người vào/rời bill; `'custom'`: thủ công.
  final String splitMode;
  final bool joinOpen;
  final String? joinCode;

  bool get isSharedInvoice => sourceInvoiceId != null;
```

- [ ] **Step 4: Tạo `ExternalBill`**

Tạo `lib/features/groups/domain/external_bill.dart`:

```dart
/// Một người trong bill mà người ngoài nhóm đã vào (từ `list_my_external_bills`).
class ExternalBillParticipant {
  const ExternalBillParticipant({
    required this.name,
    required this.amountMinor,
    required this.settled,
    required this.isMe,
  });

  factory ExternalBillParticipant.fromJson(Object? value) {
    final map = _object(value, 'participant');
    return ExternalBillParticipant(
      name: _string(map, 'name'),
      amountMinor: _amount(map, 'amount_minor'),
      settled: _bool(map, 'settled'),
      isMe: _bool(map, 'is_me'),
    );
  }

  final String name;
  final int amountMinor;
  final bool settled;
  final bool isMe;
}

/// Bill mà người dùng tham gia qua QR nhưng không là thành viên nhóm của bill.
/// Không mang `group_id` hay `user_id` của người khác.
class ExternalBill {
  const ExternalBill({
    required this.id,
    required this.description,
    required this.totalMinor,
    required this.createdAt,
    required this.payerName,
    required this.isOpen,
    required this.myAmountMinor,
    required this.mySettledAt,
    required this.participants,
  });

  factory ExternalBill.fromJson(Object? value) {
    final map = _object(value, 'external_bill');
    final participants = map['participants'];
    if (participants is! List) {
      throw const FormatException('external_bill.participants không hợp lệ.');
    }
    final mySettledAt = map['my_settled_at'];
    return ExternalBill(
      id: _string(map, 'id'),
      description: _string(map, 'description'),
      totalMinor: _amount(map, 'total_minor'),
      createdAt: _date(map['created_at'], 'created_at'),
      payerName: _string(map, 'payer_name'),
      isOpen: _bool(map, 'is_open'),
      myAmountMinor: _amount(map, 'my_amount_minor'),
      mySettledAt: mySettledAt == null
          ? null
          : _date(mySettledAt, 'my_settled_at'),
      participants: List.unmodifiable(
        participants.map(ExternalBillParticipant.fromJson),
      ),
    );
  }

  final String id;
  final String description;
  final int totalMinor;
  final DateTime createdAt;
  final String payerName;
  final bool isOpen;
  final int myAmountMinor;
  final DateTime? mySettledAt;
  final List<ExternalBillParticipant> participants;

  bool get isMineSettled => mySettledAt != null;

  /// Đã có người thanh toán thì không ai rời bill được nữa.
  bool get hasSettlement => participants.any((item) => item.settled);
}

Map<String, dynamic> _object(Object? value, String field) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw FormatException('$field không hợp lệ.');
  }
  return Map<String, dynamic>.from(value);
}

String _string(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('external_bill.$key không hợp lệ.');
  }
  return value;
}

int _amount(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! int || value < 0 || value > 9007199254740991) {
    throw FormatException('external_bill.$key không hợp lệ.');
  }
  return value;
}

bool _bool(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! bool) throw FormatException('external_bill.$key không hợp lệ.');
  return value;
}

DateTime _date(Object? value, String key) {
  final result = value is String ? DateTime.tryParse(value) : null;
  if (result == null) throw FormatException('external_bill.$key không hợp lệ.');
  return result.toLocal();
}
```

- [ ] **Step 5: Bỏ qua người ngoài nhóm khi tính số dư**

Thay toàn bộ `lib/features/groups/domain/group_balance_calculator.dart`:

```dart
import 'dart:math' as math;

import 'group_models.dart';

class GroupSettlementTransfer {
  const GroupSettlementTransfer({
    required this.fromUserId,
    required this.toUserId,
    required this.amountMinor,
  });

  final String fromUserId;
  final String toUserId;
  final int amountMinor;
}

abstract final class GroupBalanceCalculator {
  static Map<String, int> calculate({
    required Iterable<String> memberIds,
    required Iterable<GroupExpense> expenses,
  }) {
    final result = {for (final memberId in memberIds) memberId: 0};
    for (final expense in expenses) {
      final payerId = expense.payerId;
      // Người trả không còn trong nhóm thì bỏ qua phần được nhận.
      final payerCounted = payerId != null && result.containsKey(payerId);
      if (payerCounted) {
        result[payerId] = result[payerId]! + expense.totalMinor;
      }
      for (final split in expense.splits) {
        final userId = split.userId;
        if (userId == null) continue;
        final paidPayer =
            split.isSettled && payerId != null && userId != payerId;
        if (!paidPayer && result.containsKey(userId)) {
          result[userId] = result[userId]! - split.amountMinor;
        } else if (payerCounted) {
          // Phần đã trả, hoặc phần của người ngoài nhóm: nợ của người ngoài
          // chỉ hiện trong bill, không vào số dư của nhóm.
          result[payerId] = result[payerId]! - split.amountMinor;
        }
      }
    }
    return result;
  }

  static List<GroupSettlementTransfer> calculateSettlementTransfers(
    Map<String, int> balances,
  ) {
    final debtors = [
      for (final entry in balances.entries)
        if (entry.value < 0) _SettlementParty(entry.key, -entry.value),
    ];
    final creditors = [
      for (final entry in balances.entries)
        if (entry.value > 0) _SettlementParty(entry.key, entry.value),
    ];
    final transfers = <GroupSettlementTransfer>[];
    var debtorIndex = 0;
    var creditorIndex = 0;
    while (debtorIndex < debtors.length && creditorIndex < creditors.length) {
      final debtor = debtors[debtorIndex];
      final creditor = creditors[creditorIndex];
      final amount = math.min(debtor.amount, creditor.amount);
      if (amount > 0) {
        transfers.add(
          GroupSettlementTransfer(
            fromUserId: debtor.userId,
            toUserId: creditor.userId,
            amountMinor: amount,
          ),
        );
        debtor.amount -= amount;
        creditor.amount -= amount;
      }
      if (debtor.amount == 0) debtorIndex++;
      if (creditor.amount == 0) creditorIndex++;
    }
    return List.unmodifiable(transfers);
  }
}

class _SettlementParty {
  _SettlementParty(this.userId, this.amount);

  final String userId;
  int amount;
}
```

Vì sao trừ phần của khách khỏi người trả thay vì chỉ "bỏ qua split": người trả đã được cộng cả `totalMinor`; nếu chỉ bỏ split của khách, thành viên khác sẽ bị gợi ý trả hộ phần của khách. Với bill toàn thành viên, kết quả giống hệt bản cũ (4 test có sẵn vẫn pass).

- [ ] **Step 6: Chạy test**

Run: `flutter test test/features/groups/external_bill_test.dart test/features/groups/group_balance_calculator_test.dart`
Expected: PASS (5 + 7 tests).

- [ ] **Step 7: Format, analyze, toàn bộ test, commit**

Run: `dart format lib test && flutter analyze && flutter test`
Expected: `No issues found!`, mọi test PASS.

```bash
git add lib/features/groups/domain/group_models.dart lib/features/groups/domain/external_bill.dart lib/features/groups/domain/group_balance_calculator.dart test/features/groups/external_bill_test.dart test/features/groups/group_balance_calculator_test.dart
git commit -m "feat: model bill guests and keep them out of group balances

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `ExpenseGroupService` cho bill

**Files:**
- Modify: `lib/features/groups/data/group_service.dart`
- Modify: `lib/features/groups/presentation/group_screen.dart` (một dòng ở `_editExpense`)
- Test: `test/features/groups/group_service_bill_test.dart` (mới)

**Interfaces:**
- Consumes: RPC Task 1; `ExternalBill.fromJson`, các trường model mới (Task 3).
- Produces (trên `ExpenseGroupService`):
  - `Future<String> openBillInvite(String expenseId)` — mã 10 ký tự.
  - `Future<void> closeBillInvite(String expenseId)`.
  - `Future<String> joinBill(String code)` — chuẩn hóa `trim().toUpperCase()`, mã sai định dạng ném `FormatException` không gọi server, RPC trả `null` ném `StateError('Mã mời không hợp lệ.')`; trả `expense_id`.
  - `Future<void> leaveBill(String expenseId)`.
  - `Future<List<ExternalBill>> listExternalBills()`.
  - `Future<String?> expenseGroupIdOf(String expenseId)` — `group_id` nếu RLS cho đọc (thành viên), `null` với người ngoài. Spec không liệt kê hàm này; cần để luồng "Tham gia" biết mở màn nhóm hay cuộn tới "Bill bạn tham gia" mà không đổi kiểu trả về của `join_group_bill`.
  - `updateCustomExpense({required String expenseId, required String description, required int totalMinor, required Map<String, int> splitAmounts, required String splitMode})` — gửi `p_split_mode`; `splitMode` ngoài `'equal'|'custom'` ném `FormatException`.
  - `loadDetails` đọc `split_mode, join_open, join_code` và `participant_name`.

- [ ] **Step 1: Viết test fail**

Tạo `test/features/groups/group_service_bill_test.dart` (Supabase giả bằng `MockClient` của package `http`; `request: request` là bắt buộc vì postgrest đọc `response.request`):

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/groups/data/group_service.dart';
import 'package:hoadon_insight/features/groups/domain/group_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _expenseId = '6f1c2b8e-4a1d-4c3e-9b2a-1d2e3f4a5b6c';
const _groupId = '1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b';

/// Service gọi Supabase giả: [respond] nhận tên RPC/bảng và body đã gửi.
({ExpenseGroupService service, List<String> calls}) _service(
  Object? Function(String path, Map<String, dynamic>? body) respond,
) {
  final calls = <String>[];
  final client = SupabaseClient(
    'https://example.supabase.co',
    'sb_publishable_test',
    httpClient: MockClient((request) async {
      final path = request.url.path.replaceFirst('/rest/v1/', '');
      final body = request.body.isEmpty
          ? null
          : jsonDecode(request.body) as Map<String, dynamic>?;
      calls.add(body == null ? path : '$path ${jsonEncode(body)}');
      return http.Response(
        jsonEncode(respond(path, body)),
        200,
        request: request,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  return (service: ExpenseGroupService(client), calls: calls);
}

void main() {
  test('joinBill chuẩn hóa mã và trả expense_id', () async {
    final fake = _service((path, body) => _expenseId);

    expect(await fake.service.joinBill('  abcdef1234 '), _expenseId);
    expect(fake.calls, ['rpc/join_group_bill {"p_code":"ABCDEF1234"}']);
  });

  test('joinBill: RPC trả null thì báo mã mời không hợp lệ', () async {
    final fake = _service((path, body) => null);

    await expectLater(
      fake.service.joinBill('ABCDEF1234'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Mã mời không hợp lệ.',
        ),
      ),
    );
  });

  test('joinBill từ chối mã sai độ dài mà không gọi server', () async {
    final fake = _service((path, body) => _expenseId);

    await expectLater(fake.service.joinBill('ABCD1234'), throwsFormatException);
    expect(fake.calls, isEmpty);
  });

  test(
    'openBillInvite trả mã 10 ký tự, closeBillInvite gọi đúng RPC',
    () async {
      final fake = _service(
        (path, body) =>
            path == 'rpc/open_group_bill_invite' ? 'ABCDEF1234' : null,
      );

      expect(await fake.service.openBillInvite(_expenseId), 'ABCDEF1234');
      await fake.service.closeBillInvite(_expenseId);
      await fake.service.leaveBill(_expenseId);
      expect(fake.calls, [
        'rpc/open_group_bill_invite {"p_expense_id":"$_expenseId"}',
        'rpc/close_group_bill_invite {"p_expense_id":"$_expenseId"}',
        'rpc/leave_group_bill {"p_expense_id":"$_expenseId"}',
      ]);
    },
  );

  test('listExternalBills đọc mảng JSON của RPC', () async {
    final fake = _service(
      (path, body) => [
        {
          'id': _expenseId,
          'description': 'Ăn tối',
          'total_minor': 600000,
          'created_at': '2026-10-21T12:00:00+00:00',
          'payer_name': 'Huy',
          'is_open': true,
          'my_amount_minor': 200000,
          'my_settled_at': null,
          'participants': [
            {
              'name': 'Dũng',
              'amount_minor': 200000,
              'settled': false,
              'is_me': true,
            },
          ],
        },
      ],
    );

    final bills = await fake.service.listExternalBills();
    expect(bills.single.description, 'Ăn tối');
    expect(bills.single.participants.single.isMe, isTrue);
  });

  test('updateCustomExpense gửi p_split_mode', () async {
    final fake = _service((path, body) => null);

    await fake.service.updateCustomExpense(
      expenseId: _expenseId,
      description: 'Ăn tối',
      totalMinor: 100,
      splitAmounts: const {_groupId: 100},
      splitMode: 'equal',
    );
    expect(fake.calls.single, contains('"p_split_mode":"equal"'));
    await expectLater(
      fake.service.updateCustomExpense(
        expenseId: _expenseId,
        description: 'Ăn tối',
        totalMinor: 100,
        splitAmounts: const {_groupId: 100},
        splitMode: 'weird',
      ),
      throwsFormatException,
    );
  });

  test(
    'expenseGroupIdOf: thành viên thấy nhóm, người ngoài nhận null',
    () async {
      final member = _service(
        (path, body) => [
          {'group_id': _groupId},
        ],
      );
      final guest = _service((path, body) => <Object>[]);

      expect(await member.service.expenseGroupIdOf(_expenseId), _groupId);
      expect(await guest.service.expenseGroupIdOf(_expenseId), isNull);
    },
  );

  test('loadDetails đọc split_mode, lời mời và tên người ngoài', () async {
    const owner = 'a1a1a1a1-0000-4000-8000-000000000001';
    const guest = 'd4d4d4d4-0000-4000-8000-000000000004';
    final fake = _service(
      (path, body) => switch (path) {
        'expense_group_members' => [
          {
            'user_id': owner,
            'display_name': 'Huy',
            'phone': null,
            'role': 'owner',
          },
        ],
        'group_expenses' => [
          {
            'id': _expenseId,
            'group_id': _groupId,
            'payer_id': owner,
            'description': 'Ăn tối',
            'total_minor': 300,
            'created_at': '2026-10-21T12:00:00+00:00',
            'source_invoice_id': null,
            'source_snapshot': null,
            'split_mode': 'equal',
            'join_open': true,
            'join_code': 'ABCDEF1234',
          },
        ],
        'group_expense_splits' => [
          {
            'expense_id': _expenseId,
            'user_id': owner,
            'amount_minor': 150,
            'settled_at': null,
            'participant_name': null,
          },
          {
            'expense_id': _expenseId,
            'user_id': guest,
            'amount_minor': 150,
            'settled_at': null,
            'participant_name': 'Dũng',
          },
        ],
        _ => <Object>[],
      },
    );

    final details = await fake.service.loadDetails(
      const ExpenseGroup(
        id: _groupId,
        name: 'Đà Lạt',
        inviteCode: 'ABCD1234',
        ownerId: owner,
      ),
    );
    final expense = details.expenses.single;
    expect(expense.splitMode, 'equal');
    expect(expense.joinOpen, isTrue);
    expect(expense.joinCode, 'ABCDEF1234');
    expect(expense.splits.map((split) => split.participantName), [
      null,
      'Dũng',
    ]);
  });
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run: `flutter test test/features/groups/group_service_bill_test.dart`
Expected: FAIL — lỗi biên dịch: `The method 'joinBill' isn't defined for the type 'ExpenseGroupService'` (và các hàm mới khác), `No named parameter with the name 'splitMode'`.

- [ ] **Step 3: Sửa `group_service.dart`**

Thay import:

```dart
import '../domain/group_models.dart';
```

bằng:

```dart
import '../domain/external_bill.dart';
import '../domain/group_models.dart';
```

Thay:

```dart
  static const _maxSafeInteger = 9007199254740991;
```

bằng:

```dart
  static const _maxSafeInteger = 9007199254740991;
  static final _billCodePattern = RegExp(r'^[0-9A-F]{10}$');
```

Trong `loadDetails`, thay:

```dart
            'id, group_id, payer_id, description, total_minor, created_at, '
            'source_invoice_id, source_snapshot',
```

bằng:

```dart
            'id, group_id, payer_id, description, total_minor, created_at, '
            'source_invoice_id, source_snapshot, split_mode, join_open, '
            'join_code',
```

Thay:

```dart
                .select('expense_id, user_id, amount_minor, settled_at')
```

bằng:

```dart
                .select(
                  'expense_id, user_id, amount_minor, settled_at, '
                  'participant_name',
                )
```

Thay:

```dart
              settledAt: _optionalDate(
                map['settled_at'],
                'group_expense_split.settledAt',
              ),
            ),
```

bằng:

```dart
              settledAt: _optionalDate(
                map['settled_at'],
                'group_expense_split.settledAt',
              ),
              participantName: map['participant_name'] as String?,
            ),
```

Thay đầu `updateCustomExpense`:

```dart
  Future<void> updateCustomExpense({
    required String expenseId,
    required String description,
    required int totalMinor,
    required Map<String, int> splitAmounts,
  }) async {
    _requiredUuid(expenseId, 'expenseId');
```

bằng:

```dart
  Future<void> updateCustomExpense({
    required String expenseId,
    required String description,
    required int totalMinor,
    required Map<String, int> splitAmounts,
    required String splitMode,
  }) async {
    _requiredUuid(expenseId, 'expenseId');
    if (splitMode != 'equal' && splitMode != 'custom') {
      throw const FormatException('Cách chia không hợp lệ.');
    }
```

Thay phần cuối `updateCustomExpense` và đầu `deleteExpense`:

```dart
        'p_splits': splitAmounts.entries
            .map((entry) => {'user_id': entry.key, 'amount_minor': entry.value})
            .toList(growable: false),
      },
    );
  }

  Future<void> deleteExpense(String expenseId) async {
```

bằng:

```dart
        'p_splits': splitAmounts.entries
            .map((entry) => {'user_id': entry.key, 'amount_minor': entry.value})
            .toList(growable: false),
        'p_split_mode': splitMode,
      },
    );
  }

  /// Mở lời mời vào bill; trả mã 10 ký tự (giữ mã cũ nếu đã có).
  Future<String> openBillInvite(String expenseId) async {
    _requiredUuid(expenseId, 'expenseId');
    final code = await _client.rpc(
      'open_group_bill_invite',
      params: {'p_expense_id': expenseId},
    );
    if (code is! String || !_billCodePattern.hasMatch(code)) {
      throw const FormatException('Mã mời bill không hợp lệ.');
    }
    return code;
  }

  Future<void> closeBillInvite(String expenseId) async {
    _requiredUuid(expenseId, 'expenseId');
    await _client.rpc(
      'close_group_bill_invite',
      params: {'p_expense_id': expenseId},
    );
  }

  /// Vào bill bằng mã 10 ký tự; trả `expense_id`.
  Future<String> joinBill(String code) async {
    final normalized = code.trim().toUpperCase();
    if (!_billCodePattern.hasMatch(normalized)) {
      throw const FormatException('Mã mời bill phải có 10 ký tự 0-9, A-F.');
    }
    final expenseId = await _client.rpc(
      'join_group_bill',
      params: {'p_code': normalized},
    );
    if (expenseId == null) throw StateError('Mã mời không hợp lệ.');
    return _requiredUuid(expenseId, 'expenseId');
  }

  Future<void> leaveBill(String expenseId) async {
    _requiredUuid(expenseId, 'expenseId');
    await _client.rpc('leave_group_bill', params: {'p_expense_id': expenseId});
  }

  Future<List<ExternalBill>> listExternalBills() async {
    final value = await _client.rpc('list_my_external_bills');
    if (value is! List) {
      throw const FormatException('Danh sách bill không hợp lệ.');
    }
    return value.map(ExternalBill.fromJson).toList(growable: false);
  }

  /// Nhóm của bill nếu người dùng là thành viên; `null` với người ngoài nhóm
  /// (RLS không trả dòng nào).
  Future<String?> expenseGroupIdOf(String expenseId) async {
    _requiredUuid(expenseId, 'expenseId');
    final rows = _asRows(
      await _client
          .from('group_expenses')
          .select('group_id')
          .eq('id', expenseId)
          .limit(1),
    );
    if (rows.isEmpty) return null;
    return _requiredUuid(rows.first['group_id'], 'group_expense.groupId');
  }

  Future<void> deleteExpense(String expenseId) async {
```

Trong `_expenseFromMap`, thay:

```dart
    if (splitTotal != totalMinor) {
      throw const FormatException('Tổng phần chia không khớp khoản chi.');
    }
    return GroupExpense(
```

bằng:

```dart
    if (splitTotal != totalMinor) {
      throw const FormatException('Tổng phần chia không khớp khoản chi.');
    }
    final splitMode = map['split_mode'];
    if (splitMode != 'equal' && splitMode != 'custom') {
      throw const FormatException('group_expense.splitMode không hợp lệ.');
    }
    final joinOpen = map['join_open'];
    if (joinOpen is! bool) {
      throw const FormatException('group_expense.joinOpen không hợp lệ.');
    }
    return GroupExpense(
```

và thay:

```dart
      sourceSnapshot: _optionalSnapshot(
        map['source_snapshot'],
        'group_expense.sourceSnapshot',
      ),
    );
```

bằng:

```dart
      sourceSnapshot: _optionalSnapshot(
        map['source_snapshot'],
        'group_expense.sourceSnapshot',
      ),
      splitMode: splitMode as String,
      joinOpen: joinOpen,
      joinCode: map['join_code'] as String?,
    );
```

- [ ] **Step 4: Giữ màn nhóm biên dịch được**

Trong `lib/features/groups/presentation/group_screen.dart`, `_editExpense`, thay:

```dart
            totalMinor: draft.totalMinor,
            splitAmounts: draft.splitAmounts!,
          );
    });
  }

  Future<void> _deleteExpense(GroupExpense expense) async {
```

bằng:

```dart
            totalMinor: draft.totalMinor,
            splitAmounts: draft.splitAmounts!,
            splitMode: 'custom',
          );
    });
  }

  Future<void> _deleteExpense(GroupExpense expense) async {
```

(Giữ hành vi hiện tại; Task 5 đổi sang theo lựa chọn "Đều".)

- [ ] **Step 5: Chạy test**

Run: `flutter test test/features/groups/group_service_bill_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 6: Format, analyze, toàn bộ test, commit**

Run: `dart format lib test && flutter analyze && flutter test`
Expected: `No issues found!`, mọi test PASS.

```bash
git add lib/features/groups/data/group_service.dart lib/features/groups/presentation/group_screen.dart test/features/groups/group_service_bill_test.dart
git commit -m "feat: add bill invite, join, leave and external bill calls to the group service

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: QR mời vào bill, tên khách, nhật ký và sửa bill giữ cách chia

**Files:**
- Create: `lib/features/groups/presentation/bill_invite_qr_sheet.dart`
- Modify: `lib/features/groups/presentation/group_expense_dialog.dart`
- Modify: `lib/features/groups/presentation/group_screen.dart` (`_GroupDetailScreenState`, `_GroupDetails`, `_ExpenseCard`)
- Test: `test/features/groups/bill_invite_qr_sheet_test.dart` (mới), `test/features/groups/group_bill_guest_test.dart` (mới), `test/features/groups/group_expense_dialog_test.dart`

**Interfaces:**
- Consumes: `InviteLink.billUri` (Task 2); `GroupExpense.splitMode`, `GroupExpenseSplit.participantName` (Task 3); `openBillInvite`, `closeBillInvite`, `updateCustomExpense(splitMode:)` (Task 4).
- Produces:
  - `Future<void> showBillInviteQrSheet(BuildContext context, {required String description, required String joinCode, required Future<void> Function() onCloseInvite})`.
  - `GroupExpenseDraft.equalSplit` (`bool`, mặc định `false`; `true` khi chọn "Đều").
  - `GroupExpenseForm` mở bill `splitMode == 'equal'` ở chế độ "Đều".
  - Nhãn nhật ký `bill_joined`/`bill_left`.

- [ ] **Step 1: Viết test fail cho bottom sheet**

Tạo `test/features/groups/bill_invite_qr_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/groups/presentation/bill_invite_qr_sheet.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('hiện QR, mã 10 ký tự và nút Đóng lời mời', (tester) async {
    var closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showBillInviteQrSheet(
                context,
                description: 'Ăn tối',
                joinCode: 'ABCDEF1234',
                onCloseInvite: () async => closed++,
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
    expect(qr.semanticsLabel, 'Mã QR mời vào bill Ăn tối');
    expect(find.text('ABCDEF1234'), findsOneWidget);
    expect(find.text('Sao chép mã'), findsOneWidget);

    await tester.tap(find.text('Đóng lời mời'));
    await tester.pumpAndSettle();
    expect(closed, 1);
    expect(find.byType(QrImageView), findsNothing);
  });
}
```

- [ ] **Step 2: Viết test fail cho biểu mẫu sửa**

Thêm vào cuối `main()` của `test/features/groups/group_expense_dialog_test.dart` (trước dấu `}` cuối file):

```dart
  testWidgets('sửa bill chia đều có khách: mở ở Đều, giữ khách khi lưu', (
    tester,
  ) async {
    final key = GlobalKey<GroupExpenseFormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GroupExpenseForm(
              key: key,
              members: const [
                ..._members,
                GroupMember(
                  userId: 'guest',
                  displayName: 'Dũng (Khách)',
                  role: 'member',
                ),
              ],
              initialExpense: GroupExpense(
                id: 'e1',
                groupId: 'g1',
                payerId: 'u1',
                description: 'Ăn tối',
                totalMinor: 100001,
                createdAt: DateTime(2026, 10, 21),
                splitMode: 'equal',
                splits: const [
                  GroupExpenseSplit(userId: 'u1', amountMinor: 33334),
                  GroupExpenseSplit(userId: 'u2', amountMinor: 33334),
                  GroupExpenseSplit(
                    userId: 'guest',
                    amountMinor: 33333,
                    participantName: 'Dũng',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Chia đều cho'), findsOneWidget);
    expect(find.text('Dũng (Khách)'), findsOneWidget);
    expect(key.currentState!.hasChanges, isFalse);
    final draft = key.currentState!.submit()!;
    expect(draft.equalSplit, isTrue);
    expect(draft.splitAmounts!.keys.toSet(), {'u1', 'u2', 'guest'});
    expect(draft.splitAmounts!.values.reduce((a, b) => a + b), 100001);
  });

  testWidgets('sửa bill thủ công: mở ở Số tiền, equalSplit = false', (
    tester,
  ) async {
    final key = GlobalKey<GroupExpenseFormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GroupExpenseForm(
              key: key,
              members: _members,
              initialExpense: GroupExpense(
                id: 'e1',
                groupId: 'g1',
                payerId: 'u1',
                description: 'Cà phê',
                totalMinor: 60000,
                createdAt: DateTime(2026, 10, 21),
                splits: const [
                  GroupExpenseSplit(userId: 'u1', amountMinor: 40000),
                  GroupExpenseSplit(userId: 'u2', amountMinor: 20000),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Phần của từng người'), findsOneWidget);
    final draft = key.currentState!.submit()!;
    expect(draft.equalSplit, isFalse);
    expect(draft.splitAmounts, {'u1': 40000, 'u2': 20000});
  });
```

- [ ] **Step 3: Viết test fail cho màn nhóm**

Tạo `test/features/groups/group_bill_guest_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/groups/data/group_service.dart';
import 'package:hoadon_insight/features/groups/domain/group_models.dart';
import 'package:hoadon_insight/features/groups/presentation/group_screen.dart';

const _group = ExpenseGroup(
  id: 'group-1',
  name: 'Đà Lạt',
  inviteCode: 'DALAT123',
  ownerId: 'user-1',
);

final _details = GroupDetails(
  group: _group,
  members: const [
    GroupMember(userId: 'user-1', displayName: 'Huy', role: 'owner'),
    GroupMember(userId: 'user-2', displayName: 'Lan', role: 'member'),
  ],
  expenses: [
    GroupExpense(
      id: 'expense-1',
      groupId: 'group-1',
      payerId: 'user-1',
      description: 'Ăn tối',
      totalMinor: 90000,
      createdAt: DateTime(2026, 10, 21),
      splitMode: 'equal',
      joinOpen: true,
      joinCode: 'ABCDEF1234',
      splits: const [
        GroupExpenseSplit(userId: 'user-1', amountMinor: 30000),
        GroupExpenseSplit(userId: 'user-2', amountMinor: 30000),
        GroupExpenseSplit(
          userId: 'guest-1',
          amountMinor: 30000,
          participantName: 'Dũng',
        ),
      ],
    ),
  ],
  auditEvents: [
    GroupAuditEvent(
      id: '1',
      eventType: 'bill_joined',
      createdAt: DateTime(2026, 10, 21, 20),
      actorId: 'guest-1',
      targetUserId: 'guest-1',
      expenseId: 'expense-1',
    ),
    GroupAuditEvent(
      id: '2',
      eventType: 'bill_left',
      createdAt: DateTime(2026, 10, 21, 21),
      actorId: 'guest-2',
      targetUserId: 'guest-2',
      expenseId: 'expense-1',
    ),
  ],
);

Future<_FakeExpenseGroupService> _pump(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 2400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final service = _FakeExpenseGroupService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [expenseGroupServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(home: GroupDetailScreen(groupId: 'group-1')),
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

void main() {
  testWidgets(
    'người ngoài trong bill hiện tên kèm nhãn Khách và trong nhật ký',
    (tester) async {
      await _pump(tester);

      expect(find.text('Dũng'), findsOneWidget);
      expect(find.text('Khách'), findsOneWidget);
      expect(find.text('Dũng đã vào bill “Ăn tối”'), findsOneWidget);
      expect(find.text('Khách đã rời bill “Ăn tối”'), findsOneWidget);
      expect(find.textContaining('Tài khoản đã xóa'), findsNothing);
    },
  );

  testWidgets('người trả mở QR mời vào bill rồi đóng lời mời', (tester) async {
    final service = await _pump(tester);

    await tester.tap(find.byTooltip('Quản lý khoản chi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QR mời vào bill'));
    await tester.pumpAndSettle();
    expect(service.calls, ['open expense-1']);
    expect(find.text('ABCDEF1234'), findsOneWidget);

    await tester.tap(find.text('Đóng lời mời'));
    await tester.pumpAndSettle();
    expect(service.calls, ['open expense-1', 'close expense-1']);
  });

  testWidgets('sửa bill chia đều giữ khách và gửi splitMode equal', (
    tester,
  ) async {
    final service = await _pump(tester);

    await tester.tap(find.byTooltip('Quản lý khoản chi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sửa khoản chi'));
    await tester.pumpAndSettle();
    expect(find.text('Dũng (Khách)'), findsOneWidget);
    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();

    expect(service.calls, ['update expense-1 equal guest-1,user-1,user-2']);
  });
}

class _FakeExpenseGroupService implements ExpenseGroupService {
  final calls = <String>[];

  @override
  String get currentUserId => 'user-1';

  @override
  Future<List<ExpenseGroup>> listGroups() async => const [_group];

  @override
  Future<GroupDetails> loadDetails(ExpenseGroup group) async => _details;

  @override
  Future<String> openBillInvite(String expenseId) async {
    calls.add('open $expenseId');
    return 'ABCDEF1234';
  }

  @override
  Future<void> closeBillInvite(String expenseId) async {
    calls.add('close $expenseId');
  }

  @override
  Future<void> updateCustomExpense({
    required String expenseId,
    required String description,
    required int totalMinor,
    required Map<String, int> splitAmounts,
    required String splitMode,
  }) async {
    final ids = splitAmounts.keys.toList()..sort();
    calls.add('update $expenseId $splitMode ${ids.join(',')}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

- [ ] **Step 4: Chạy test để thấy fail**

Run: `flutter test test/features/groups/bill_invite_qr_sheet_test.dart test/features/groups/group_expense_dialog_test.dart test/features/groups/group_bill_guest_test.dart`
Expected: FAIL — lỗi biên dịch: thiếu `bill_invite_qr_sheet.dart`, `GroupExpenseDraft` không có getter `equalSplit`.

- [ ] **Step 5: Tạo bottom sheet QR bill**

Tạo `lib/features/groups/presentation/bill_invite_qr_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../domain/invite_link.dart';

/// Bottom sheet QR mời vào một bill. Chỉ mở sau khi `openBillInvite` thành
/// công, nên lời mời luôn đang mở; "Đóng lời mời" gọi [onCloseInvite] rồi đóng.
Future<void> showBillInviteQrSheet(
  BuildContext context, {
  required String description,
  required String joinCode,
  required Future<void> Function() onCloseInvite,
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
              'Mời vào bill “$description”',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              'Người quét mã sẽ vào bill này, không vào nhóm.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Nền trắng cố định để máy khác quét được cả khi app ở chế độ tối.
            QrImageView(
              data: InviteLink.billUri(joinCode),
              size: 220,
              backgroundColor: Colors.white,
              padding: const EdgeInsets.all(16),
              semanticsLabel: 'Mã QR mời vào bill $description',
            ),
            const SizedBox(height: 12),
            SelectableText(
              joinCode,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: joinCode));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã sao chép mã mời bill.')),
                );
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Sao chép mã'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await onCloseInvite();
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.link_off_outlined),
              label: const Text('Đóng lời mời'),
            ),
          ],
        ),
      ),
    ),
  );
}
```

- [ ] **Step 6: Biểu mẫu sửa giữ chế độ "Đều"**

Trong `lib/features/groups/presentation/group_expense_dialog.dart`, thay:

```dart
    required this.memberIds,
    this.splitAmounts,
  });

  final String description;
  final int totalMinor;
  final List<String> memberIds;
  final Map<String, int>? splitAmounts;
}
```

bằng:

```dart
    required this.memberIds,
    this.splitAmounts,
    this.equalSplit = false,
  });

  final String description;
  final int totalMinor;
  final List<String> memberIds;
  final Map<String, int>? splitAmounts;

  /// `true` khi người dùng chọn "Đều"; màn nhóm gửi `splitMode: 'equal'`.
  final bool equalSplit;
}
```

Thay:

```dart
    _customMode = initial == null ? null : GroupSplitMode.exact;
```

bằng:

```dart
    _customMode = _initialMode;
```

Thay:

```dart
  @override
  void dispose() {
    _descriptionController.dispose();
```

bằng:

```dart
  /// Tạo mới và bill chia đều mở ở "Đều"; bill thủ công mở ở "Số tiền".
  GroupSplitMode? get _initialMode {
    final initial = widget.initialExpense;
    if (initial == null || initial.splitMode == 'equal') return null;
    return GroupSplitMode.exact;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
```

Trong `hasChanges`, thay:

```dart
        _customMode != (initial == null ? null : GroupSplitMode.exact) ||
```

bằng:

```dart
        _customMode != _initialMode ||
```

Trong `submit()`, thay:

```dart
      splitAmounts: widget.initialExpense == null
          ? splitAmounts
          : splitAmounts!,
    );
```

bằng:

```dart
      splitAmounts: widget.initialExpense == null
          ? splitAmounts
          : splitAmounts!,
      equalSplit: _customMode == null,
    );
```

- [ ] **Step 7: Nối vào màn nhóm**

Trong `lib/features/groups/presentation/group_screen.dart`:

Thêm import, thay:

```dart
import 'group_expense_dialog.dart';
```

bằng:

```dart
import 'bill_invite_qr_sheet.dart';
import 'group_expense_dialog.dart';
```

Trong `_GroupDetailScreenState.build`, thay:

```dart
                      onSettle: _settleShare,
                      onEditExpense: (expense) =>
                          _editExpense(groupDetails, expense),
```

bằng:

```dart
                      onSettle: _settleShare,
                      onShowBillQr: _showBillQr,
                      onEditExpense: (expense) =>
                          _editExpense(groupDetails, expense),
```

Thay toàn bộ `_editExpense` (bản sau Task 4):

```dart
  Future<void> _editExpense(GroupDetails details, GroupExpense expense) async {
    final draft = await showDialog<GroupExpenseDraft>(
      context: context,
      builder: (context) =>
          GroupExpenseDialog(members: details.members, initialExpense: expense),
    );
    if (draft == null || !mounted) return;
    await _runGroupAction(() async {
      await ref
          .read(expenseGroupServiceProvider)!
          .updateCustomExpense(
            expenseId: expense.id,
            description: draft.description,
            totalMinor: draft.totalMinor,
            splitAmounts: draft.splitAmounts!,
            splitMode: 'custom',
          );
    });
  }
```

bằng:

```dart
  Future<void> _showBillQr(GroupExpense expense) async {
    String? code;
    await _runGroupAction(() async {
      code = await ref
          .read(expenseGroupServiceProvider)!
          .openBillInvite(expense.id);
    });
    final joinCode = code;
    if (joinCode == null || !mounted) return;
    await showBillInviteQrSheet(
      context,
      description: expense.description,
      joinCode: joinCode,
      onCloseInvite: () => _runGroupAction(() async {
        await ref
            .read(expenseGroupServiceProvider)!
            .closeBillInvite(expense.id);
      }),
    );
  }

  Future<void> _editExpense(GroupDetails details, GroupExpense expense) async {
    final memberIds = {for (final member in details.members) member.userId};
    final members = [
      ...details.members,
      // Người ngoài nhóm đã vào bill: hiện trong dialog để sửa không xóa họ.
      for (final split in expense.splits)
        if (split.userId != null && !memberIds.contains(split.userId))
          GroupMember(
            userId: split.userId!,
            displayName: '${split.participantName ?? 'Thành viên'} (Khách)',
            role: 'member',
          ),
    ];
    final draft = await showDialog<GroupExpenseDraft>(
      context: context,
      builder: (context) =>
          GroupExpenseDialog(members: members, initialExpense: expense),
    );
    if (draft == null || !mounted) return;
    await _runGroupAction(() async {
      await ref
          .read(expenseGroupServiceProvider)!
          .updateCustomExpense(
            expenseId: expense.id,
            description: draft.description,
            totalMinor: draft.totalMinor,
            splitAmounts: draft.splitAmounts!,
            splitMode: draft.equalSplit ? 'equal' : 'custom',
          );
    });
  }
```

Trong `_GroupDetails`, thay:

```dart
    required this.onSettle,
    required this.onEditExpense,
    required this.onDeleteExpense,
    required this.onSetMemberRole,
```

bằng:

```dart
    required this.onSettle,
    required this.onShowBillQr,
    required this.onEditExpense,
    required this.onDeleteExpense,
    required this.onSetMemberRole,
```

Thay:

```dart
  final Future<void> Function(String expenseId) onSettle;
  final Future<void> Function(GroupExpense expense) onEditExpense;
```

bằng:

```dart
  final Future<void> Function(String expenseId) onSettle;
  final Future<void> Function(GroupExpense expense) onShowBillQr;
  final Future<void> Function(GroupExpense expense) onEditExpense;
```

Thay:

```dart
    final names = {
      for (final member in details.members) member.userId: member.displayName,
    };
```

bằng:

```dart
    final names = {
      // Tên người ngoài nhóm trong bill, để nhật ký không hiện "Tài khoản đã xóa".
      for (final expense in details.expenses)
        for (final split in expense.splits)
          if (split.userId != null && split.participantName != null)
            split.userId!: split.participantName!,
      for (final member in details.members) member.userId: member.displayName,
    };
```

Thay:

```dart
            onEdit: () => onEditExpense(expense),
            onDelete: () => onDeleteExpense(expense),
          ),
```

bằng:

```dart
            onShowBillQr: () => onShowBillQr(expense),
            onEdit: () => onEditExpense(expense),
            onDelete: () => onDeleteExpense(expense),
          ),
```

Trong `_auditLabel`, thay:

```dart
      'expense_settled' => '$actor đã xác nhận phần chia',
      _ => 'Có hoạt động mới trong nhóm',
    };
  }
```

bằng:

```dart
      'expense_settled' => '$actor đã xác nhận phần chia',
      'bill_joined' => _billAuditLabel(event, names, 'đã vào'),
      'bill_left' => _billAuditLabel(event, names, 'đã rời'),
      _ => 'Có hoạt động mới trong nhóm',
    };
  }

  String _billAuditLabel(
    GroupAuditEvent event,
    Map<String, String> names,
    String action,
  ) {
    // Người ngoài đã rời bill thì không còn tên trong split.
    final who = names[event.actorId] ?? 'Khách';
    final description = details.expenses
        .where((expense) => expense.id == event.expenseId)
        .firstOrNull
        ?.description;
    return description == null
        ? '$who $action bill'
        : '$who $action bill “$description”';
  }
```

Trong `_ExpenseCard`, thay:

```dart
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  final GroupExpense expense;
  final Map<String, String> names;
  final String currentUserId;
  final Future<void> Function(String expenseId) onSettle;
  final bool canManage;
  final Future<void> Function() onEdit;
```

bằng:

```dart
    required this.canManage,
    required this.onShowBillQr,
    required this.onEdit,
    required this.onDelete,
  });

  final GroupExpense expense;
  final Map<String, String> names;
  final String currentUserId;
  final Future<void> Function(String expenseId) onSettle;
  final bool canManage;
  final Future<void> Function() onShowBillQr;
  final Future<void> Function() onEdit;
```

Menu đã chỉ hiện khi `canManage && !hasSettlement` (người trả hoặc trưởng nhóm, bill chưa ai trả) — đúng điều kiện spec. Thay:

```dart
                    onSelected: (value) {
                      if (value == 'edit') {
                        onEdit();
                      } else {
                        onDelete();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
```

bằng:

```dart
                    onSelected: (value) {
                      if (value == 'invite') {
                        onShowBillQr();
                      } else if (value == 'edit') {
                        onEdit();
                      } else {
                        onDelete();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'invite',
                        child: ListTile(
                          leading: Icon(Icons.qr_code_2),
                          title: Text('QR mời vào bill'),
                        ),
                      ),
                      PopupMenuItem(
```

Thay dòng tên trong danh sách split:

```dart
                title: Text(
                  split.userId == null
                      ? 'Tài khoản đã xóa'
                      : names[split.userId!] ?? 'Thành viên',
                ),
```

bằng:

```dart
                title: Text(
                  split.userId == null
                      ? 'Tài khoản đã xóa'
                      : split.participantName ??
                            names[split.userId!] ??
                            'Thành viên',
                ),
                subtitle: split.participantName == null
                    ? null
                    : const Text('Khách'),
```

- [ ] **Step 8: Chạy test**

Run: `flutter test test/features/groups/bill_invite_qr_sheet_test.dart test/features/groups/group_expense_dialog_test.dart test/features/groups/group_bill_guest_test.dart`
Expected: PASS (1 + 8 + 3 tests).

- [ ] **Step 9: Format, analyze, toàn bộ test, commit**

Run: `dart format lib test && flutter analyze && flutter test`
Expected: `No issues found!`, mọi test PASS.

```bash
git add lib/features/groups/presentation/bill_invite_qr_sheet.dart lib/features/groups/presentation/group_expense_dialog.dart lib/features/groups/presentation/group_screen.dart test/features/groups/bill_invite_qr_sheet_test.dart test/features/groups/group_expense_dialog_test.dart test/features/groups/group_bill_guest_test.dart
git commit -m "feat: show bill invite QR, guest names and keep equal split when editing

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Mục "Bill bạn tham gia"

Đặt trước luồng "Tham gia" (Task 7) vì luồng đó cuộn tới mục này.

**Files:**
- Create: `lib/features/groups/presentation/external_bills_section.dart`
- Modify: `lib/core/providers/app_providers.dart`
- Modify: `lib/features/groups/presentation/group_screen.dart` (`GroupScreen`)
- Modify: `test/features/groups/group_navigation_test.dart` (fake thêm `listExternalBills`)
- Test: `test/features/groups/external_bills_section_test.dart` (mới)

**Interfaces:**
- Consumes: `ExternalBill` (Task 3); `listExternalBills`, `settleMyShare`, `leaveBill` (Task 4).
- Produces:
  - `final externalBillsProvider = FutureProvider.autoDispose<List<ExternalBill>>(...)` trong `app_providers.dart`.
  - `class ExternalBillsSection extends ConsumerWidget { const ExternalBillsSection({super.key}); }` — ẩn khi rỗng.
  - `_GroupScreenState._externalBillsKey` (`GlobalKey`) gắn vào section; `_refresh()` làm mới cả `externalBillsProvider`; kéo xuống để làm mới.

- [ ] **Step 1: Viết test fail**

Tạo `test/features/groups/external_bills_section_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/core/utils/money_formatter.dart';
import 'package:hoadon_insight/features/groups/data/group_service.dart';
import 'package:hoadon_insight/features/groups/domain/external_bill.dart';
import 'package:hoadon_insight/features/groups/presentation/external_bills_section.dart';

ExternalBill _bill({
  int myAmountMinor = 200000,
  DateTime? mySettledAt,
  bool someoneSettled = false,
}) => ExternalBill(
  id: 'bill-1',
  description: 'Ăn tối',
  totalMinor: 600000,
  createdAt: DateTime(2026, 10, 21),
  payerName: 'Huy',
  isOpen: !someoneSettled,
  myAmountMinor: myAmountMinor,
  mySettledAt: mySettledAt,
  participants: [
    ExternalBillParticipant(
      name: 'Huy',
      amountMinor: 600000 - 2 * myAmountMinor,
      settled: false,
      isMe: false,
    ),
    ExternalBillParticipant(
      name: 'Lan',
      amountMinor: myAmountMinor,
      settled: someoneSettled,
      isMe: false,
    ),
    ExternalBillParticipant(
      name: 'Dũng',
      amountMinor: myAmountMinor,
      settled: mySettledAt != null,
      isMe: true,
    ),
  ],
);

Future<_FakeExpenseGroupService> _pump(
  WidgetTester tester,
  List<ExternalBill> bills,
) async {
  final service = _FakeExpenseGroupService(bills);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [expenseGroupServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ExternalBillsSection()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

void main() {
  testWidgets('danh sách rỗng thì ẩn mục', (tester) async {
    await _pump(tester, const []);

    expect(find.text('Bill bạn tham gia'), findsNothing);
  });

  testWidgets('có bill thì hiện phần của mình và hai nút', (tester) async {
    await _pump(tester, [_bill()]);

    expect(find.text('Bill bạn tham gia'), findsOneWidget);
    expect(find.text('Người trả: Huy'), findsOneWidget);
    expect(
      find.text('Phần của bạn: ${MoneyFormatter.format(200000)}'),
      findsOneWidget,
    );
    expect(find.text('Tôi đã thanh toán'), findsOneWidget);
    expect(find.text('Rời bill'), findsOneWidget);
  });

  testWidgets('bill mình đã trả thì không còn nút Tôi đã thanh toán', (
    tester,
  ) async {
    await _pump(tester, [_bill(mySettledAt: DateTime(2026, 10, 21))]);

    expect(find.text('Bạn đã thanh toán'), findsOneWidget);
    expect(find.text('Tôi đã thanh toán'), findsNothing);
  });

  testWidgets('bill đã có người trả thì không có nút Rời bill', (tester) async {
    await _pump(tester, [_bill(someoneSettled: true)]);

    expect(find.text('Rời bill'), findsNothing);
    expect(find.text('Tôi đã thanh toán'), findsOneWidget);
  });

  testWidgets('phần của mình 0đ thì chờ người trả, không cho thanh toán', (
    tester,
  ) async {
    await _pump(tester, [_bill(myAmountMinor: 0)]);

    expect(find.text('Chờ người trả chia lại phần tiền'), findsOneWidget);
    expect(find.text('Tôi đã thanh toán'), findsNothing);
    expect(find.text('Rời bill'), findsOneWidget);
  });

  testWidgets('bấm Tôi đã thanh toán gọi settle rồi tải lại', (tester) async {
    final service = await _pump(tester, [_bill()]);

    await tester.tap(find.text('Tôi đã thanh toán'));
    await tester.pumpAndSettle();

    expect(service.calls, ['list', 'settle bill-1', 'list']);
  });

  testWidgets('bấm vào bill hiện danh sách người tham gia', (tester) async {
    await _pump(tester, [_bill()]);

    await tester.tap(find.text('Ăn tối'));
    await tester.pumpAndSettle();

    expect(find.text('Dũng (Bạn)'), findsOneWidget);
    expect(find.text('Lan'), findsOneWidget);
  });
}

class _FakeExpenseGroupService implements ExpenseGroupService {
  _FakeExpenseGroupService(this.bills);

  final List<ExternalBill> bills;
  final calls = <String>[];

  @override
  Future<List<ExternalBill>> listExternalBills() async {
    calls.add('list');
    return bills;
  }

  @override
  Future<void> settleMyShare(String expenseId) async {
    calls.add('settle $expenseId');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run: `flutter test test/features/groups/external_bills_section_test.dart`
Expected: FAIL — lỗi biên dịch: thiếu `external_bills_section.dart`.

- [ ] **Step 3: Thêm provider**

Trong `lib/core/providers/app_providers.dart`, thay:

```dart
import '../../features/groups/data/group_service.dart';
```

bằng:

```dart
import '../../features/groups/data/group_service.dart';
import '../../features/groups/domain/external_bill.dart';
```

và thay:

```dart
final expenseGroupDetailsProvider = FutureProvider.autoDispose
```

bằng:

```dart
final externalBillsProvider = FutureProvider.autoDispose<List<ExternalBill>>((
  ref,
) {
  final service = ref.watch(expenseGroupServiceProvider);
  return service?.listExternalBills() ?? const [];
});

final expenseGroupDetailsProvider = FutureProvider.autoDispose
```

- [ ] **Step 4: Tạo mục "Bill bạn tham gia"**

Tạo `lib/features/groups/presentation/external_bills_section.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/dialogs/confirm_dialog.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/widgets/app_callout.dart';
import '../data/group_service.dart';
import '../domain/external_bill.dart';

/// Mục "Bill bạn tham gia": bill mà người dùng vào qua QR nhưng không là
/// thành viên nhóm. Ẩn khi rỗng.
class ExternalBillsSection extends ConsumerWidget {
  const ExternalBillsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(externalBillsProvider);
    final items = bills.valueOrNull;
    if (items == null && bills.hasError) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: AppCallout(
          tone: CalloutTone.warning,
          message:
              'Không tải được bill bạn tham gia: ${friendlyMessage(bills.error!)}',
        ),
      );
    }
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Bill bạn tham gia',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final bill in items)
                _ExternalBillTile(
                  bill: bill,
                  onOpen: () => _showParticipants(context, bill),
                  onSettle: () => _run(
                    context,
                    ref,
                    (service) => service.settleMyShare(bill.id),
                  ),
                  onLeave: () => _leave(context, ref, bill),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _leave(
    BuildContext context,
    WidgetRef ref,
    ExternalBill bill,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Rời bill?',
      message:
          'Bạn sẽ không còn trong “${bill.description}”. '
          'Phần tiền của bạn sẽ được chia lại cho những người còn lại.',
      confirmLabel: 'Rời bill',
      icon: Icons.logout_outlined,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await _run(context, ref, (service) => service.leaveBill(bill.id));
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(ExpenseGroupService service) action,
  ) async {
    final service = ref.read(expenseGroupServiceProvider);
    if (service == null) return;
    try {
      await action(service);
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyMessage(error))));
      }
    }
    ref.invalidate(externalBillsProvider);
  }

  Future<void> _showParticipants(BuildContext context, ExternalBill bill) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(
              bill.description,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('Tổng: ${MoneyFormatter.format(bill.totalMinor)}'),
            const SizedBox(height: 8),
            for (final participant in bill.participants)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  participant.isMe
                      ? '${participant.name} (Bạn)'
                      : participant.name,
                ),
                trailing: Text(
                  '${MoneyFormatter.format(participant.amountMinor)}'
                  '${participant.settled ? ' · Đã trả' : ''}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ExternalBillTile extends StatelessWidget {
  const _ExternalBillTile({
    required this.bill,
    required this.onOpen,
    required this.onSettle,
    required this.onLeave,
  });

  final ExternalBill bill;
  final VoidCallback onOpen;
  final Future<void> Function() onSettle;
  final Future<void> Function() onLeave;

  @override
  Widget build(BuildContext context) {
    // Bill thủ công: người mới nhận 0đ cho tới khi người trả chia lại.
    final waitingForAmount = !bill.isMineSettled && bill.myAmountMinor == 0;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                bill.description,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text('Người trả: ${bill.payerName}'),
              Text(
                'Phần của bạn: ${MoneyFormatter.format(bill.myAmountMinor)}',
              ),
              Text(
                bill.isMineSettled
                    ? 'Bạn đã thanh toán'
                    : waitingForAmount
                    ? 'Chờ người trả chia lại phần tiền'
                    : 'Chưa thanh toán',
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!bill.hasSettlement)
                    TextButton(
                      onPressed: onLeave,
                      child: const Text('Rời bill'),
                    ),
                  if (!bill.isMineSettled && !waitingForAmount)
                    FilledButton.tonal(
                      onPressed: onSettle,
                      child: const Text('Tôi đã thanh toán'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

`valueOrNull` giữ danh sách cũ trong lúc làm mới, nên mục không chớp tắt sau mỗi thao tác.

- [ ] **Step 5: Đặt mục vào tab Nhóm và cho kéo xuống để làm mới**

Trong `lib/features/groups/presentation/group_screen.dart`:

Thay:

```dart
import 'bill_invite_qr_sheet.dart';
```

bằng:

```dart
import 'bill_invite_qr_sheet.dart';
import 'external_bills_section.dart';
```

Thay:

```dart
class _GroupScreenState extends ConsumerState<GroupScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(expenseGroupServiceProvider);
    final groups = ref.watch(expenseGroupsProvider);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
```

bằng:

```dart
class _GroupScreenState extends ConsumerState<GroupScreen> {
  final _externalBillsKey = GlobalKey();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(expenseGroupServiceProvider);
    final groups = ref.watch(expenseGroupsProvider);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _pullToRefresh,
        child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
```

Thay:

```dart
          if (service != null)
            const SliverToBoxAdapter(child: _DirectShareInbox()),
```

bằng:

```dart
          if (service != null)
            const SliverToBoxAdapter(child: _DirectShareInbox()),
          if (service != null)
            SliverToBoxAdapter(
              child: ExternalBillsSection(key: _externalBillsKey),
            ),
```

Thay (đóng thêm một tầng cho `RefreshIndicator`):

```dart
          const SliverToBoxAdapter(child: SizedBox(height: 112)),
        ],
      ),
    );
  }
```

bằng:

```dart
          const SliverToBoxAdapter(child: SizedBox(height: 112)),
        ],
        ),
      ),
    );
  }
```

Thay:

```dart
  void _refresh() {
    ref.invalidate(expenseGroupsProvider);
  }
}
```

bằng:

```dart
  void _refresh() {
    ref.invalidate(expenseGroupsProvider);
    ref.invalidate(externalBillsProvider);
  }

  Future<void> _pullToRefresh() async {
    _refresh();
    try {
      await ref.read(externalBillsProvider.future);
    } on Object catch (_) {
      // Lỗi tải đã hiện ngay trong mục "Bill bạn tham gia".
    }
  }
}
```

`dart format` ở Step 7 sẽ thụt lề lại khối `slivers` bên trong `RefreshIndicator`.

- [ ] **Step 6: Cập nhật fake của test điều hướng**

`GroupScreen` giờ đọc `listExternalBills`. Trong `test/features/groups/group_navigation_test.dart`, thay:

```dart
import 'package:hoadon_insight/features/groups/data/group_service.dart';
```

bằng:

```dart
import 'package:hoadon_insight/features/groups/data/group_service.dart';
import 'package:hoadon_insight/features/groups/domain/external_bill.dart';
```

và thay:

```dart
  @override
  Future<GroupDetails> loadDetails(ExpenseGroup group) async => details;
```

bằng:

```dart
  @override
  Future<GroupDetails> loadDetails(ExpenseGroup group) async => details;

  @override
  Future<List<ExternalBill>> listExternalBills() async => const [];
```

- [ ] **Step 7: Chạy test, format, analyze**

Run: `dart format lib test && flutter analyze && flutter test test/features/groups/external_bills_section_test.dart test/features/groups/group_navigation_test.dart`
Expected: `No issues found!`, PASS (7 + 1 tests).

- [ ] **Step 8: Toàn bộ test và commit**

Run: `flutter test`
Expected: mọi test PASS.

```bash
git add lib/core/providers/app_providers.dart lib/features/groups/presentation/external_bills_section.dart lib/features/groups/presentation/group_screen.dart test/features/groups/external_bills_section_test.dart test/features/groups/group_navigation_test.dart
git commit -m "feat: list bills joined from outside the group in the Groups tab

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Nút "Tham gia" nhận QR bill và mã 10 ký tự

**Files:**
- Modify: `lib/features/groups/presentation/group_screen.dart` (`_GroupScreenState._joinGroup`, `_askText`)
- Test: `test/features/groups/group_join_test.dart` (mới)

**Interfaces:**
- Consumes: `InviteLink.parse`, `GroupInviteLink`, `BillInviteLink` (Task 2); `joinGroup`, `joinBill`, `expenseGroupIdOf` (Task 4); `externalBillsProvider`, `_externalBillsKey` (Task 6).
- Produces: `_joinGroupByCode(String)`, `_joinBill(String)` trong `_GroupScreenState`. Mã gõ tay không hợp lệ hiện snackbar `Mã mời phải có 8 ký tự (nhóm) hoặc 10 ký tự (bill), gồm 0-9 và A-F.` và không gọi server. Vào bill thành công hiện `Đã vào bill`.

`_askText` hiện `dispose` controller ngay khi dialog trả kết quả, trong khi `TextField` còn dùng nó suốt animation đóng dialog: test nhập mã ở bước này sẽ lỗi `A TextEditingController was used after being disposed`. Bước 3 bỏ `dispose` đó.

- [ ] **Step 1: Viết test fail**

Tạo `test/features/groups/group_join_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/groups/data/group_service.dart';
import 'package:hoadon_insight/features/groups/domain/external_bill.dart';
import 'package:hoadon_insight/features/groups/domain/group_models.dart';
import 'package:hoadon_insight/features/groups/presentation/group_screen.dart';

const _group = ExpenseGroup(
  id: 'group-1',
  name: 'Đà Lạt',
  inviteCode: 'DALAT123',
  ownerId: 'user-1',
);

final _externalBill = ExternalBill(
  id: 'bill-9',
  description: 'Karaoke',
  totalMinor: 300000,
  createdAt: DateTime(2026, 10, 21),
  payerName: 'Minh',
  isOpen: true,
  myAmountMinor: 100000,
  mySettledAt: null,
  participants: const [
    ExternalBillParticipant(
      name: 'Minh',
      amountMinor: 200000,
      settled: false,
      isMe: false,
    ),
    ExternalBillParticipant(
      name: 'Huy',
      amountMinor: 100000,
      settled: false,
      isMe: true,
    ),
  ],
);

Future<_FakeExpenseGroupService> _pump(
  WidgetTester tester, {
  String? billGroupId,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1600);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final service = _FakeExpenseGroupService(billGroupId: billGroupId);
  final rootKey = GlobalKey<NavigatorState>();
  final router = GoRouter(
    navigatorKey: rootKey,
    initialLocation: '/groups',
    routes: [
      GoRoute(
        path: '/groups',
        builder: (context, state) => const GroupScreen(),
        routes: [
          GoRoute(
            path: ':groupId',
            parentNavigatorKey: rootKey,
            builder: (context, state) =>
                GroupDetailScreen(groupId: state.pathParameters['groupId']!),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [expenseGroupServiceProvider.overrideWithValue(service)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

Future<void> _typeCode(WidgetTester tester, String code) async {
  await tester.tap(find.widgetWithText(OutlinedButton, 'Tham gia'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Nhập mã mời'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, 'Mã mời'), code);
  await tester.tap(find.widgetWithText(FilledButton, 'Tham gia'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mã 10 ký tự chữ thường vào bill, người ngoài thấy mục bill', (
    tester,
  ) async {
    final service = await _pump(tester);
    expect(find.text('Bill bạn tham gia'), findsNothing);

    await _typeCode(tester, ' abcdef1234 ');

    expect(service.calls, ['joinBill ABCDEF1234', 'groupOf bill-9']);
    expect(find.text('Đã vào bill'), findsOneWidget);
    expect(find.text('Bill bạn tham gia'), findsOneWidget);
    expect(find.text('Karaoke'), findsOneWidget);
  });

  testWidgets('thành viên nhóm vào bill của nhóm mình thì mở màn nhóm', (
    tester,
  ) async {
    final service = await _pump(tester, billGroupId: 'group-1');

    await _typeCode(tester, 'ABCDEF1234');

    expect(service.calls, ['joinBill ABCDEF1234', 'groupOf bill-9']);
    expect(find.text('QR mời vào nhóm'), findsOneWidget);
  });

  testWidgets('mã 8 ký tự vẫn vào nhóm', (tester) async {
    final service = await _pump(tester);

    await _typeCode(tester, 'abcd1234');

    expect(service.calls, ['joinGroup ABCD1234']);
    expect(find.text('QR mời vào nhóm'), findsOneWidget);
  });

  testWidgets('mã 9 hoặc 11 ký tự báo lỗi tại chỗ, không gọi server', (
    tester,
  ) async {
    final service = await _pump(tester);

    for (final code in ['ABCDEF123', 'ABCDEF12345']) {
      await _typeCode(tester, code);
      expect(
        find.text(
          'Mã mời phải có 8 ký tự (nhóm) hoặc 10 ký tự (bill), gồm 0-9 và A-F.',
        ),
        findsOneWidget,
      );
      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold).first),
      ).removeCurrentSnackBar();
      await tester.pumpAndSettle();
    }
    expect(service.calls, isEmpty);
  });
}

class _FakeExpenseGroupService implements ExpenseGroupService {
  _FakeExpenseGroupService({this.billGroupId});

  final String? billGroupId;
  final calls = <String>[];
  bool _joinedBill = false;

  @override
  String get currentUserId => 'user-1';

  @override
  Future<List<ExpenseGroup>> listGroups() async => const [_group];

  @override
  Future<GroupDetails> loadDetails(ExpenseGroup group) async => GroupDetails(
    group: group,
    members: const [
      GroupMember(userId: 'user-1', displayName: 'Huy', role: 'owner'),
    ],
    expenses: const [],
    auditEvents: const [],
  );

  @override
  Future<ExpenseGroup> joinGroup(String inviteCode) async {
    calls.add('joinGroup $inviteCode');
    return _group;
  }

  @override
  Future<String> joinBill(String code) async {
    calls.add('joinBill $code');
    _joinedBill = true;
    return 'bill-9';
  }

  @override
  Future<String?> expenseGroupIdOf(String expenseId) async {
    calls.add('groupOf $expenseId');
    return billGroupId;
  }

  @override
  Future<List<ExternalBill>> listExternalBills() async =>
      _joinedBill && billGroupId == null ? [_externalBill] : const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run: `flutter test test/features/groups/group_join_test.dart`
Expected: FAIL cả 4 test — `Expected: ['joinBill ABCDEF1234', 'groupOf bill-9']  Actual: ['joinGroup abcdef1234']` (mã đang đi thẳng vào `joinGroup`), test mã 9/11 ký tự không thấy snackbar, và mỗi test kèm `A TextEditingController was used after being disposed.`

- [ ] **Step 3: Đổi luồng "Tham gia"**

Trong `lib/features/groups/presentation/group_screen.dart`, `_joinGroup`, thay toàn bộ đoạn từ `if (method == null || !mounted) return;` tới hết hàm:

```dart
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
          _ => null,
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

bằng:

```dart
    if (method == null || !mounted) return;
    final InviteLink? link;
    switch (method) {
      case _JoinMethod.scan:
        final raw = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => QrScanScreen(
              title: 'Quét mã mời',
              validate: (raw) => InviteLink.parse(raw) == null
                  ? 'Mã QR này không phải mã mời nhóm hoặc bill.'
                  : null,
            ),
          ),
        );
        link = raw == null ? null : InviteLink.parse(raw);
      case _JoinMethod.type:
        final text = await _askText(
          title: 'Tham gia nhóm hoặc bill',
          label: 'Mã mời',
          hint: 'Mã nhóm 8 ký tự hoặc mã bill 10 ký tự',
          confirmLabel: 'Tham gia',
        );
        if (text == null) return;
        link = InviteLink.parse(text);
        if (link == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Mã mời phải có 8 ký tự (nhóm) hoặc 10 ký tự (bill), '
                'gồm 0-9 và A-F.',
              ),
            ),
          );
        }
    }
    switch (link) {
      case GroupInviteLink(:final code):
        await _joinGroupByCode(code);
      case BillInviteLink(:final code):
        await _joinBill(code);
      case null:
        return;
    }
  }

  Future<void> _joinGroupByCode(String inviteCode) async {
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

  /// Vào bill: thành viên nhóm thì mở màn nhóm, người ngoài thì cuộn tới
  /// mục "Bill bạn tham gia".
  Future<void> _joinBill(String code) async {
    var joined = false;
    String? groupId;
    await _runGroupAction(() async {
      final service = ref.read(expenseGroupServiceProvider)!;
      final expenseId = await service.joinBill(code);
      groupId = await service.expenseGroupIdOf(expenseId);
      joined = true;
    });
    if (!joined || !mounted) return;
    ref.invalidate(externalBillsProvider);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đã vào bill')));
    final id = groupId;
    if (id != null) {
      await context.push('/groups/$id');
      return;
    }
    try {
      await ref.read(externalBillsProvider.future);
    } on Object catch (_) {
      // Lỗi tải đã hiện ngay trong mục "Bill bạn tham gia".
    }
    final section = _externalBillsKey.currentContext;
    if (section == null || !section.mounted) return;
    await Scrollable.ensureVisible(
      section,
      duration: const Duration(milliseconds: 300),
    );
  }
```

- [ ] **Step 4: Bỏ `dispose` sớm trong `_askText`**

Thay:

```dart
    final controller = TextEditingController();
    return showDialog<String>(
```

bằng:

```dart
    // Không dispose khi dialog trả kết quả: TextField còn dùng controller
    // trong animation đóng dialog. Controller không còn ai giữ sẽ được GC thu.
    final controller = TextEditingController();
    return showDialog<String>(
```

và thay dòng cuối của `_askText`:

```dart
    ).whenComplete(controller.dispose);
```

bằng:

```dart
    );
```

- [ ] **Step 5: Chạy test**

Run: `flutter test test/features/groups/group_join_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Format, analyze, toàn bộ test, commit**

Run: `dart format lib test && flutter analyze && flutter test`
Expected: `No issues found!`, mọi test PASS.

```bash
git add lib/features/groups/presentation/group_screen.dart test/features/groups/group_join_test.dart
git commit -m "feat: join a bill by scanning its QR or typing its 10-character code

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Kiểm tra toàn nhánh

**Files:** không đổi code, trừ khi bước kiểm tra lộ lỗi (khi đó sửa ở task sở hữu file và commit riêng).

- [ ] **Step 1: Chạy đúng các bước CI phía Flutter**

```bash
export PATH=$HOME/flutter/bin:$PATH
flutter pub get
dart run build_runner build
git diff --exit-code
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web
```

Expected: mọi lệnh exit 0; `git diff --exit-code` không có thay đổi file sinh; `flutter test` báo `All tests passed!`; `flutter build web` báo `✓ Built build/web`.

`flutter build apk --debug` (cũng là bước CI) cần Android SDK — máy này chưa có. Chạy trên CI hoặc máy có SDK; Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`.

- [ ] **Step 2: Chạy lại pgTAP và lint từ DB sạch**

Run: `npx supabase db reset && npx supabase test db && npx supabase db lint`
Expected: `All tests successful.` (`Files=2, Tests=72`), `No schema errors found`.

- [ ] **Step 3: Kiểm tra tay với ba tài khoản (A trưởng nhóm, B thành viên, D không ở nhóm)**

Chạy: `flutter run --dart-define=APP_ENV=dev --dart-define-from-file=config/supabase.local.json` với Supabase local hoặc staging đã `db push`.

1. B tạo bill chia đều 300.000 ₫ cho A, B. Trên card, menu "Quản lý khoản chi" → "QR mời vào bill": QR nền trắng, mã 10 ký tự, "Sao chép mã" báo đã sao chép.
2. D: tab Nhóm → "Tham gia" → "Quét mã QR" → quét QR trên máy B → snackbar "Đã vào bill", mục "Bill bạn tham gia" hiện "Phần của bạn: 100.000 ₫", người trả B.
3. B kéo làm mới màn nhóm: bill có dòng "<tên D>" kèm nhãn "Khách", mỗi người 100.000 ₫; nhật ký có "<tên D> đã vào bill “…”"; gợi ý thanh toán chỉ có A trả B 100.000 ₫.
4. A nhập tay mã bill bằng chữ thường → mở thẳng màn nhóm, không có mục "Bill bạn tham gia". Nhập mã 9 ký tự → báo lỗi ngay.
5. B sửa bill (để "Đều", không đổi gì) → lưu → D vẫn còn trong bill.
6. D bấm "Rời bill" → xác nhận → bill chia lại cho A, B 150.000 ₫; nhật ký có "… đã rời bill". D quét lại, bấm "Tôi đã thanh toán" → nút "Rời bill" biến mất; người thứ tư quét QR → "Bill này đã đóng lời mời"; B mở lại menu → không còn mục "QR mời vào bill" (bill đã có thanh toán).
7. B tạo bill "Số tiền", mở QR, D vào → D thấy "Chờ người trả chia lại phần tiền", không có "Tôi đã thanh toán"; B sửa bill gán tiền cho D → D kéo làm mới thấy số tiền và nút.

- [ ] **Step 4: Báo kết quả**

Ghi lại lệnh đã chạy và kết quả (pass/fail kèm dòng lỗi), nêu rõ bước APK chưa chạy nếu máy không có Android SDK. Không push, không mở PR cho đến khi người dùng yêu cầu.

---

## Self-Review

**1. Spec coverage**

| Spec | Task |
|---|---|
| §4.1 cột `join_code`, `join_open`, `split_mode`, `participant_name`, `joined_at`; audit `bill_joined`/`bill_left` | 1 |
| §4.2 `rebalance_equal_bill` (security invoker, revoke 3 role, phần dư theo `(joined_at, user_id)`) | 1 (test 2, 10) |
| §4.3 `open_group_bill_invite` 1-5, `close_group_bill_invite` | 1 (test 1, 5, 6) |
| §4.3 `join_group_bill` 1-9 (định dạng `22023`, rate limit chung, `null`, idempotent, đóng/đã trả/100 người, tên hồ sơ/`Khách`, chia lại, audit) | 1 (test 2, 3, 4, 6, 7); "đủ 100 người" chỉ có trong code, không test (cần 100 user) |
| §4.3 `leave_group_bill` 1-6 (kể cả "ít nhất một người", custom về người trả) | 1 (test 10 + bill "Taxi", "Cà phê") |
| §4.3 `list_my_external_bills` (không `group_id`/`user_id`, thành viên không thấy) | 1 (test 9) |
| §4.3 `settle_group_split` cho người ngoài + tự đóng lời mời | 1 (test 6, 10) |
| §4.3 `update_group_expense_custom` 5 tham số bắt buộc, bản 4 tham số giữ nguyên chữ ký/grant | 1 (test 11) |
| §4.3 `create_group_expense(_from_invoice)` đặt `equal` | 1 (test 12; bản `_from_invoice` chỉ đổi đúng một cột như bản thường) |
| §4.4 `InviteLink` bill | 2 |
| §4.4 model, `ExternalBill`, calculator | 3 |
| §4.4 service + `loadDetails` | 4 |
| §4.4 sửa ở "Đều" gửi `splitMode: 'equal'` | 5 |
| §4.5 card menu + bottom sheet + tên "Khách" | 5 |
| §4.5 "Bill bạn tham gia", provider, kéo làm mới, xác nhận rời | 6 |
| §4.5 quét/nhập mã 8/10 ký tự, "Đã vào bill", cuộn/mở màn nhóm | 7 |
| §5 khóa `for update`, `UF001` qua `friendlyMessage`, RLS không đổi | 1 (RLS test 8) |
| §6.1 cả 12 mục | 1 (51 assertion) |
| §6.2 `invite_link_test`, `group_balance_calculator_test`, `external_bill_test`, `external_bills_section_test`, `bill_invite_qr_sheet_test` | 2, 3, 3, 6, 5 |
| §7 triển khai | 8 |
| Thành công #5 (nhóm thấy khách trong nhật ký) | 5 |

**2. Placeholder scan:** không có "TBD"/"TODO"/"tương tự Task N"; mọi bước code có code đầy đủ; mọi lệnh có Expected.

**3. Type consistency:** `BillInviteLink.code` (Task 2) dùng ở Task 7; `ExternalBill`/`ExternalBillParticipant` và getter `isMineSettled`, `hasSettlement` (Task 3) dùng ở Task 4, 6, 7; `updateCustomExpense(splitMode:)` (Task 4) được gọi ở Task 4 (`'custom'`) và Task 5 (`draft.equalSplit`); `GroupExpenseDraft.equalSplit` (Task 5); `externalBillsProvider`, `_externalBillsKey` (Task 6) dùng ở Task 7; `expenseGroupIdOf` (Task 4) dùng ở Task 7; các fake trong test override đúng chữ ký service.

**4. Review Focus:** năm mục ở đầu plan đều có test trong task sở hữu (Task 5 ×2, Task 6, Task 7 ×2, Task 1 pgTAP cho mục 4).

**Các điểm spec chưa nói rõ và cách plan xử lý:**
- Spec nói `GroupExpenseDraft` "đã có đủ thông tin", nhưng khi sửa, bản nháp luôn có `splitAmounts` nên không phân biệt được "Đều": thêm `equalSplit`, và bill `equal` mở ở "Đều" (nếu không, sửa mô tả cũng biến bill thành `custom`).
- Dialog sửa chỉ liệt kê thành viên nhóm: thêm khách thành dòng "<tên> (Khách)" để không mất khách khi lưu.
- "Bỏ qua split người ngoài" trong calculator được hiểu là trừ phần đó khỏi phần người trả được nhận, để tổng số dư nhóm vẫn bằng 0.
- Luồng "Tham gia" cần biết người vào có là thành viên không: thêm `expenseGroupIdOf` (đọc qua RLS) thay vì đổi kiểu trả về của `join_group_bill`.
- Nút "Tôi đã thanh toán" ẩn khi phần của mình là 0đ (bill thủ công vừa vào), vì thanh toán sẽ đóng lời mời của cả bill.
- Thứ tự task 6/7 đổi so với gợi ý ban đầu: mục "Bill bạn tham gia" làm trước vì luồng "Tham gia" cuộn tới nó.
