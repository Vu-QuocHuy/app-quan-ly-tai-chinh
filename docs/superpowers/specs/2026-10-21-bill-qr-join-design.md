# Spec B — QR mời vào bill cho người ngoài nhóm — Thiết kế

- Ngày: 2026-10-21
- Branch: `feat/bill-qr-join` (tách từ `feat/group-qr-fund-goal`, PR spec A chưa merge)
- Phụ thuộc: Spec A (`2026-10-20-group-qr-invite-fund-goal-design.md`): `InviteLink`,
  `QrScanScreen`, `group_invite_qr_sheet.dart`, mã lỗi `UF001`, giới hạn tham gia
  `expense_group_join_rate_limits` đã sửa.

## 1. Mục tiêu

Team chốt: ngoài QR mời vào nhóm, mỗi bill (một lần chia tiền) có QR riêng. Người ngoài nhóm
quét QR đó để vào đúng bill, không cần vào nhóm, và thấy phần tiền mình phải trả ngay trong app.

Thành công khi:

1. Người trả bill (hoặc trưởng nhóm) mở được QR mời vào bill và đóng được lời mời.
2. Người khác (trong hay ngoài nhóm) quét QR hoặc nhập mã 10 ký tự để vào bill.
3. Bill chia đều tự chia lại mỗi khi có người vào; bill chia thủ công thì người mới nhận 0đ để
   người trả sửa.
4. Người ngoài nhóm thấy bill ở mục "Bill bạn tham gia" trong tab Nhóm, đánh dấu đã thanh toán
   và rời bill được; không thấy gì khác của nhóm.
5. Nhóm thấy người ngoài trong bill (tên, phần tiền) và trong nhật ký nhóm.

Ngoài phạm vi: thông báo push, deep link mở app từ camera hệ thống, danh sách bạn bè, thanh
toán thật, người ngoài tự mời thêm người, đổi tên server message "khoản chi".

## 2. Quyết định đã chốt

| Câu hỏi | Quyết định |
|---|---|
| Người tham gia bill là gì | Người có dòng trong `group_expense_splits` |
| Join vào bill chia đều | Tự chia đều lại; bill thủ công: người mới 0đ |
| Ai mở QR bill | Người trả bill và trưởng nhóm |
| Người ngoài thấy bill ở đâu | Mục "Bill bạn tham gia" trong tab Nhóm |
| Thông báo | Hiện trong app, không push |
| Người ngoài đọc dữ liệu thế nào | Chỉ qua RPC `list_my_external_bills`; không mở rộng RLS bảng |
| Người ngoài thấy gì | Mô tả, tổng, tên người trả, tên và phần tiền người tham gia; không tên nhóm, quỹ, thành viên, bill khác |
| Khi có người đầu tiên thanh toán | Bill tự đóng lời mời; không ai vào thêm |
| Tất toán của nhóm | Gợi ý tất toán chỉ tính giữa thành viên nhóm; nợ của người ngoài chỉ hiện trong bill |
| Nhập mã tay | Mã nhóm 8 ký tự, mã bill 10 ký tự `[0-9A-F]`; phân biệt bằng độ dài |

## 3. Hiện trạng liên quan

- RLS `group_expenses`, `group_expense_splits`, `expense_group_members`, `group_audit_events`:
  chỉ thành viên nhóm (`is_current_user_expense_group_member`, migration
  `20260929100000_harden_group_membership_policy.sql`).
- `settle_group_split` (`20260917200000_group_settlement_idempotency.sql`): join với
  `expense_group_members`, nên người ngoài nhóm không gọi được.
- `update_group_expense_custom` (spec A, `20261021100000_group_qr_fund_goal.sql`): mỗi split
  phải là thành viên nhóm (`is_expense_group_member`).
- RPC tạo bill: `create_group_expense` (chia đều, `20260918060000_group_expense_hardening.sql`),
  `create_group_expense_custom` (cùng file), `create_group_expense_from_invoice` và
  `create_group_expense_custom_from_invoice` (`20260918160000_bill_sharing.sql`).
- Tên hiển thị trong bill lấy từ `expense_group_members.display_name`; `profiles.display_name`
  là tên hồ sơ của người dùng.
- `GroupBalanceCalculator.calculate(memberIds, expenses)` cộng cả split của user không nằm trong
  `memberIds` vào kết quả.
- `audit event_type` hợp lệ hiện tại: `group_created`, `member_joined`, `member_role_changed`,
  `member_removed`, `member_left`, `expense_created`, `expense_settled`, `expense_updated`,
  `expense_deleted`.

## 4. Thiết kế

### 4.1 Schema — migration `supabase/migrations/20261022100000_bill_qr_join.sql`

```sql
alter table public.group_expenses
  add column join_code text unique check (join_code ~ '^[0-9A-F]{10}$'),
  add column join_open boolean not null default false,
  add column split_mode text not null default 'custom'
    check (split_mode in ('equal', 'custom'));

alter table public.group_expense_splits
  add column participant_name text check (char_length(participant_name) <= 80),
  add column joined_at timestamptz not null default now();
```

- `participant_name` chỉ điền cho người vào qua QR mà không là thành viên nhóm; giá trị là
  `profiles.display_name` (rỗng → `'Khách'`) lúc vào.
- `joined_at` của các split cũ là thời điểm chạy migration — chấp nhận được, chỉ dùng để xếp thứ
  tự nhận phần dư 1 đơn vị khi chia lại.
- Mở rộng `group_audit_events_event_type_check` thêm `bill_joined`, `bill_left`.

### 4.2 Quy tắc chia lại đều

Khi bill có `split_mode = 'equal'` và tập người tham gia đổi (vào hoặc rời): mọi split được tính
lại `total ~/ n`, phần dư `total % n` cộng 1 cho các split xếp đầu theo `(joined_at, user_id)`.
Chỉ chạy khi chưa split nào có `settled_at` (đã được bảo đảm vì bill tự đóng khi có người trả,
và rời bill bị chặn khi đã có người trả). Viết một hàm nội bộ
`public.rebalance_equal_bill(p_expense_id uuid)` (`security invoker`, revoke khỏi
`public, anon, authenticated`).

### 4.3 RPC

Mọi hàm mới: `security definer`, `set search_path = ''`, `revoke all ... from public, anon`,
`grant execute ... to authenticated`. Hàm `create or replace` giữ `search_path` gốc. Lỗi người
dùng đọc được dùng `UF001`.

**Mới — `open_group_bill_invite(p_expense_id uuid) returns text`**

1. Chưa đăng nhập → `28000`. Khóa bill `for update`.
2. Caller không phải `payer_id` và không phải `owner_id` của nhóm → `UF001`
   `Chỉ người trả hoặc trưởng nhóm được mời vào bill`.
3. Có split đã thanh toán → `UF001` `Bill đã có người thanh toán, không mời thêm được`.
4. `join_code` null → sinh 10 ký tự hex in hoa không trùng (vòng lặp như `create_expense_group`).
5. `join_open = true`; trả `join_code`.

**Mới — `close_group_bill_invite(p_expense_id uuid) returns void`**: cùng kiểm tra quyền bước
1-2; đặt `join_open = false`.

**Mới — `join_group_bill(p_code text) returns uuid`**

1. Chưa đăng nhập → `28000`. Mã sai định dạng (sau `upper(trim)` không khớp `^[0-9A-F]{10}$`)
   → `22023`.
2. Dùng chung bảng và luật của `expense_group_join_rate_limits` như `join_expense_group` (10 lần
   mỗi cửa sổ 1 phút, vượt → `UF001` `Bạn đã thử quá nhiều mã. Hãy thử lại sau một phút.`);
   tăng đếm trước khi tra mã, không đặt lại khi thành công.
3. Không có bill với mã đó → trả `null` (không raise, để lượt đếm được commit).
4. Caller đã có split trong bill → trả `expense_id` (không đổi gì).
5. Khóa bill `for update`. `join_open = false` → `UF001` `Bill này đã đóng lời mời`. Có split đã
   thanh toán → `UF001` `Bill đã có người thanh toán, không mời thêm được`. Đã có 100 split →
   `UF001` `Bill đã đủ 100 người`.
6. Thêm split `(expense_id, user_id, amount_minor 0, participant_name, joined_at now())`;
   `participant_name` = `null` nếu caller là thành viên nhóm, ngược lại tên hồ sơ.
7. `split_mode = 'equal'` → `rebalance_equal_bill`.
8. Ghi audit `bill_joined` (`actor_id` = caller, `target_user_id` = caller, `expense_id`).
9. Trả `expense_id`.

**Mới — `leave_group_bill(p_expense_id uuid) returns void`**

1. Chưa đăng nhập → `28000`. Khóa bill.
2. Caller không có split → `UF001` `Bạn không ở trong bill này`. Caller là người trả →
   `UF001` `Người trả không rời bill được`.
3. Có split đã thanh toán → `UF001` `Bill đã có người thanh toán, không rời được`.
4. Bill chỉ còn split của caller → `UF001` `Bill phải còn ít nhất một người`.
5. Xóa split của caller. `equal` → `rebalance_equal_bill`. `custom` → phần tiền của caller cộng
   vào split của người trả nếu người trả có split, ngược lại cộng vào split xếp đầu theo
   `(joined_at, user_id)`; tổng bill không đổi.
6. Ghi audit `bill_left`.

**Mới — `list_my_external_bills() returns jsonb`**

Trả mảng (tối đa 100, mới nhất trước) các bill mà caller có split và **không** là thành viên nhóm
của bill:

```json
[{
  "id": "uuid", "description": "Ăn tối", "total_minor": 600000,
  "created_at": "…", "payer_name": "Huy", "is_open": true,
  "my_amount_minor": 200000, "my_settled_at": null,
  "participants": [{"name": "Huy", "amount_minor": 200000, "settled": false, "is_me": false}]
}]
```

Tên: `coalesce(nullif(split.participant_name, ''), member.display_name, 'Thành viên')`; người
trả: `coalesce(member.display_name, 'Tài khoản đã xóa')`. Không trả `group_id`, tên nhóm,
`user_id` của người khác.

**Sửa — `settle_group_split(p_expense_id uuid)`**: bỏ điều kiện thành viên nhóm; điều kiện mới là
caller có split trong bill. Khi đánh dấu thành công: đặt `join_open = false` cho bill. Phần còn
lại (idempotent, audit `expense_settled`) giữ nguyên.

**Sửa — `update_group_expense_custom`**: thêm bản 5 tham số
`(p_expense_id uuid, p_description text, p_total_minor bigint, p_splits jsonb, p_split_mode text)`
— `p_split_mode` bắt buộc, không có default (default sẽ làm lời gọi 4 tham số mơ hồ giữa hai
bản). Bản 4 tham số giữ chữ ký và grant, thân hàm chỉ gọi bản 5 tham số với
`p_split_mode = 'custom'` để app cũ vẫn sửa bill được. Thay đổi trong bản 5 tham số:
- Mỗi `user_id` trong `p_splits` phải là thành viên nhóm **hoặc** đã có split trong bill này.
- Split giữ lại `participant_name` và `joined_at` cũ khi `user_id` đã có trước khi sửa.
- `p_split_mode` ngoài `('equal','custom')` → `22023`; lưu vào `split_mode`.

**Sửa — RPC tạo bill**: `create_group_expense` và `create_group_expense_from_invoice` đặt
`split_mode = 'equal'`; hai bản `custom` giữ mặc định `'custom'`. Logic khác không đổi.

### 4.4 Flutter — domain và data

- `InviteLink`: thêm `final class BillInviteLink extends InviteLink { final String code; }`;
  `parse` nhận host `join-bill` (mã `^[0-9A-F]{10}$`) và mã trơn 10 ký tự; thêm
  `static String billUri(String code)` → `hoadoninsight://join-bill?code=<CODE>`.
- `GroupExpense` thêm `String splitMode` (`'equal'`/`'custom'`), `bool joinOpen`,
  `String? joinCode`. `GroupExpenseSplit` thêm `String? participantName`.
- `GroupBalanceCalculator.calculate`: bỏ qua split có `userId` không thuộc `memberIds`; người trả
  không thuộc `memberIds` cũng bỏ qua.
- Model mới `ExternalBill` (+ `ExternalBillParticipant`) parse từ `list_my_external_bills`.
- `ExpenseGroupService` thêm: `openBillInvite(expenseId) → String`, `closeBillInvite(expenseId)`,
  `joinBill(code) → String expenseId` (null từ RPC → `StateError('Mã mời không hợp lệ.')`),
  `leaveBill(expenseId)`, `listExternalBills() → List<ExternalBill>`;
  `updateCustomExpense` nhận thêm `splitMode`. `loadDetails` select thêm `split_mode, join_open,
  join_code` và `participant_name`.
- `GroupExpenseDraft` đã có đủ thông tin; khi sửa ở chế độ "Đều", màn nhóm gửi
  `splitMode: 'equal'`.

### 4.5 Flutter — presentation

- **Quét và nhập mã (tab Nhóm, nút "Tham gia")**: màn quét chấp nhận cả `GroupInviteLink` và
  `BillInviteLink`; ô nhập mã: 8 ký tự → `joinGroup`, 10 ký tự → `joinBill`. Vào bill thành công
  → thông báo "Đã vào bill" và cuộn tới mục "Bill bạn tham gia" (người ngoài nhóm) hoặc mở màn
  nhóm (thành viên).
- **Card bill trong màn nhóm**: người trả hoặc trưởng nhóm thấy mục menu "QR mời vào bill" khi
  bill chưa có người thanh toán. Mở bottom sheet `bill_invite_qr_sheet.dart`: QR
  (`InviteLink.billUri`), mã 10 ký tự, "Sao chép mã", và nút "Đóng lời mời" (khi đang mở). Dòng
  split của người ngoài hiện `participantName` kèm nhãn "Khách".
- **Mục "Bill bạn tham gia"** (`external_bills_section.dart`, đặt dưới hộp thư chia sẻ ở tab
  Nhóm, ẩn khi rỗng): mỗi bill hiện mô tả, người trả, "Phần của bạn: …", trạng thái; nút
  "Tôi đã thanh toán" (gọi `settleMyShare`) và "Rời bill" (khi bill chưa ai trả, có xác nhận).
  Bấm vào mở bottom sheet chi tiết danh sách người tham gia. Dữ liệu qua provider
  `externalBillsProvider`, làm mới khi kéo xuống và sau mỗi thao tác.

## 5. Xử lý lỗi và đồng thời

- Mọi thay đổi tập người tham gia chạy dưới khóa `group_expenses ... for update`; hai người vào
  cùng lúc được tuần tự hóa, tổng split luôn bằng tổng bill.
- Người trả sửa bill trong lúc có người vào: cả hai cùng khóa bill; lệnh sau thấy dữ liệu mới.
  Lệnh sửa mang danh sách split cũ sẽ xóa người vừa vào — chấp nhận; nhật ký `bill_joined` vẫn
  còn và người đó có thể quét lại.
- Lỗi `UF001` hiện nguyên câu qua `friendlyMessage`.
- Người ngoài không đọc được bảng nhóm: RLS không đổi; chỉ RPC trả dữ liệu đã lọc.

## 6. Test

### 6.1 SQL — `supabase/tests/bill_qr_join_test.sql` (pgTAP)

1. Thành viên thường (không phải người trả) gọi `open_group_bill_invite` → `UF001`; người trả và
   trưởng nhóm gọi được; mã 10 ký tự hex.
2. Người ngoài vào bill chia đều 100001 với 2 người sẵn có → 3 split, tổng 100001, phần dư theo
   `(joined_at, user_id)`; `participant_name` là tên hồ sơ.
3. Bill `custom`: người mới có split 0, các split khác không đổi.
4. Vào lần hai → cùng `expense_id`, không thêm split.
5. `close_group_bill_invite` rồi vào → `UF001`.
6. Có người thanh toán → `join_open` thành false; vào → `UF001`; `open_group_bill_invite` → `UF001`.
7. Mã không tồn tại → `null`, `attempt_count` tăng; lần thứ 11 trong một phút → `UF001`.
8. Người ngoài `select` từ `group_expenses`, `group_expense_splits`, `expense_group_members`,
   `group_fund_entries` (với `set local role authenticated`) → 0 dòng.
9. `list_my_external_bills` của người ngoài trả đúng bill đã vào, không có `group_id`; của thành
   viên nhóm không trả bill của nhóm mình.
10. Người ngoài `settle_group_split` được; `leave_group_bill` khi chưa ai trả → split bị xóa, bill
    chia lại; người trả gọi `leave_group_bill` → `UF001`.
11. `update_group_expense_custom` giữ người ngoài trong `p_splits` được; thêm user lạ (không
    thành viên, không tham gia) → `22023`; `p_split_mode = 'equal'` lưu vào bill.
12. `create_group_expense` đặt `split_mode = 'equal'`; `create_group_expense_custom` đặt
    `'custom'`.

### 6.2 Dart (`flutter test`)

- `invite_link_test.dart`: URI bill, mã trơn 10 ký tự, mã 9/11 ký tự bị từ chối, URI nhóm vẫn
  ra `GroupInviteLink`, `billUri` rồi `parse` khớp.
- `group_balance_calculator_test.dart`: split của người ngoài không vào số dư thành viên; gợi ý
  tất toán chỉ giữa thành viên.
- `external_bill_test.dart`: parse JSON của `list_my_external_bills` (đủ trường, thiếu trường →
  `FormatException`).
- Widget test `external_bills_section_test.dart`: danh sách rỗng ẩn mục; có bill hiện phần của
  mình; bill đã trả không còn nút "Tôi đã thanh toán"; bill có người trả không có "Rời bill".
- Widget test `bill_invite_qr_sheet_test.dart`: hiện QR, mã 10 ký tự, nút "Đóng lời mời".

## 7. Triển khai

1. Merge spec A trước (migration `20261021100000`), rồi spec B (`20261022100000`).
2. `npx supabase db reset && npx supabase test db` local; `npx supabase db push --dry-run`, rồi
   `db push`.
3. Phát hành app mới cùng đợt. App cũ vẫn chạy: `update_group_expense_custom` 4 tham số còn
   nguyên (lưu `split_mode = 'custom'`); app cũ không thấy mục "Bill bạn tham gia" và hiện
   người ngoài trong bill bằng tên mặc định cho tới khi cập nhật.
