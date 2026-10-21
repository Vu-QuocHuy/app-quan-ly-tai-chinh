# Spec A — QR mời nhóm, mục tiêu quỹ, nút "Chia tiền" hai tab — Thiết kế

- Ngày: 2026-10-20
- Branch: `feat/group-fund-bills`
- Thay thế: `2026-10-20-group-fund-bills-design.md` (mô hình "bill trừ từ quỹ" đã bị bỏ)
- Spec liên quan: Spec B — Bill QR cho người ngoài nhóm (viết sau, dùng lại `QrScanScreen` và
  `InviteLink` của spec này)

## 1. Bối cảnh và mục tiêu

Team chốt mô hình nhóm:

- Một người tạo được nhiều nhóm; mỗi nhóm có một trưởng nhóm (role `owner` hiện có).
- Trong nhóm có **quỹ chung** (chi tiêu chung) và **chia tiền** (chia hóa đơn lẻ). Hai chức năng
  độc lập; bill không liên quan đến quỹ.
- **Thu chi chỉ nằm trong quỹ** (màn quỹ). **Chia tiền** ở màn chi tiết nhóm, tách khỏi thu chi:
  không gọi là "khoản chi", không đặt chung chỗ với sổ quỹ (team chốt 20/10).
- Chỉ **một nút "Chia tiền"**: mở cửa sổ có hai tab **"Nhập thủ công"** và **"Quét hóa đơn"**; tab
  nào cũng chia được tiền cho các thành viên.
- Tạo nhóm thì có **mã QR mời** vào nhóm.
- Luồng "quét hóa đơn rồi gán từng dòng cho thành viên" quá rườm rà; quét chỉ để điền sẵn.
- Danh sách bạn bè kiểu Zalo/Facebook: chưa làm.

Spec A gồm phần không cần mô hình truy cập mới. Bill QR cho người ngoài nhóm thuộc Spec B.

Thành công khi:

1. Thành viên mở được QR mời của nhóm; người khác quét QR trong app để tham gia.
2. Trưởng nhóm đặt được mục tiêu và hạn cho quỹ; mọi thành viên thấy tiến độ.
3. Nút "Chia tiền" mở cửa sổ hai tab: "Nhập thủ công" nhập tay; "Quét hóa đơn" chụp hoặc chọn
   ảnh rồi hiện cùng biểu mẫu chia tiền đã điền sẵn nội dung và tổng tiền. Tab nào cũng lưu được
   một lần chia tiền cho các thành viên đã chọn.
4. Thông báo lỗi tiếng Việt từ server tới được người dùng ở các luồng nhóm, quỹ, tham gia.
5. Các lỗi có sẵn ở mục 3 được sửa.

Ngoài phạm vi: mở app bằng camera hệ thống (deep link `join-group`), đổi/thu hồi mã mời, nhiều
quỹ trong một nhóm, phần góp kỳ vọng mỗi người, danh sách bạn bè, mọi thứ thuộc Spec B.

## 2. Hiện trạng liên quan

- `lib/features/groups/presentation/group_screen.dart` (1770 dòng): danh sách nhóm với nút
  "Tạo nhóm" và "Tham gia" (nhập mã qua `_askText`); màn chi tiết hiện "Mã mời: X" và nút sao
  chép; nút "Từ hóa đơn" chọn ảnh thư viện, gọi `importCoordinatorProvider.importImage`, mở
  `_InvoiceAllocationDialog` để gán từng dòng hóa đơn cho thành viên, rồi gọi
  `addCustomExpense`.
- `_NewExpenseDialog`: chọn tập con thành viên, chia đều / theo số tiền / theo phần trăm.
- `invite_code`: 8 ký tự `[0-9A-F]` (`upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 8))`).
- `join_expense_group` (định nghĩa mới nhất ở `20260918080000_group_rpc_lint_fix.sql`): có bảng
  `expense_group_join_rate_limits` giới hạn 10 lần mỗi phút.
- `group_fund_entries` (`20261008120000_group_fund.sql`): sổ `deposit`/`expense`, ghi qua
  `add_group_fund_entry` dưới khóa `expense_groups ... for update`.
- `mobile_scanner` đã có và đang dùng ở `qr_payment_screen.dart`; quyền camera Android/iOS đã
  khai báo. Repo chưa có package sinh QR.
- `friendlyMessage` (`lib/shared/errors/error_presenter.dart`) gộp mọi `PostgrestException`
  ngoài `PGRST301`/`23505` thành "Máy chủ từ chối yêu cầu…".

## 3. Lỗi có sẵn được sửa trong spec này

1. **Thông báo tiếng Việt từ RPC không tới người dùng.** Do `friendlyMessage` ở trên. Không thể
   map thẳng `22023` vì 84/185 lỗi `22023` trong migrations là tiếng Anh nội bộ.
2. **Giới hạn số lần tham gia nhóm không đếm lần nhập sai.** `join_expense_group` tăng
   `attempt_count` rồi `raise exception 'Mã tham gia nhóm không hợp lệ'`; `raise` rollback cả
   transaction nên lượt tăng bị hủy. Mã sai không bao giờ bị giới hạn, nên dò mã mời không bị
   chặn.
3. **Lỗi quyền khi so sánh với `null`.** `update_group_expense_custom` và `delete_group_expense`
   (`20260920100000_group_expense_lifecycle.sql`) dùng `v_actor_id <> v_payer_id`. Khi người
   trả đã xóa tài khoản, `payer_id` là `null`, biểu thức cho ra `null`, điều kiện chặn không
   kích hoạt, và mọi thành viên sửa/xóa được bill đó. `delete_group_fund_entry` có cùng mẫu với
   `actor_id`, sẽ lộ ra sau khi sửa lỗi 4.
4. **User từng ghi quỹ không xóa được tài khoản.** `group_fund_entries.actor_id` là
   `not null ... on delete restrict`, và Edge Function `delete-account` không dọn bảng này.

## 4. Thiết kế

### 4.1 Mã lỗi hiển thị cho người dùng

- Lỗi mà người dùng cần đọc dùng SQLSTATE `UF001` (lớp `U` không thuộc lớp chuẩn của
  PostgreSQL) với thông điệp tiếng Việt. Lỗi kỹ thuật giữ mã cũ.
- `friendlyMessage`: trong nhánh `PostgrestException`, thêm `'UF001' => e.message`.

Các thông điệp `UF001` trong spec này:

| Thông điệp | RPC |
|---|---|
| `Quỹ không đủ tiền cho khoản chi này` | `add_group_fund_entry` |
| `Bạn đã thử quá nhiều mã. Hãy thử lại sau một phút.` | `join_expense_group` |
| `Chỉ trưởng nhóm được đặt mục tiêu quỹ` | `set_group_fund_goal` |
| `Mục tiêu quỹ không hợp lệ` | `set_group_fund_goal` |
| `Hạn quỹ phải từ hôm nay trở đi` | `set_group_fund_goal` |

### 4.2 Schema

Một migration mới: `supabase/migrations/20261021100000_group_qr_fund_goal.sql`.

```sql
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
```

Tên constraint `group_fund_entries_actor_id_fkey` là tên Postgres tự sinh; xác nhận bằng
`supabase db reset` trước khi đẩy.

### 4.3 RPC

Mọi hàm mới hoặc `create or replace` giữ chữ ký, `security definer`, `search_path` cố định như
hàm gốc (hàm mới dùng `set search_path = ''`), `revoke all ... from public, anon`,
`grant execute ... to authenticated`.

**Mới — `set_group_fund_goal(p_group_id uuid, p_goal_minor bigint, p_deadline date) returns void`**

1. `auth.uid()` null → `28000`.
2. Khóa `expense_groups` của `p_group_id` `for update`. Không tồn tại hoặc caller không phải
   `owner_id` → `UF001` `Chỉ trưởng nhóm được đặt mục tiêu quỹ`.
3. `p_goal_minor is null` → đặt `fund_goal_minor` và `fund_deadline` về `null`; kết thúc.
4. `p_goal_minor` ngoài `1..9007199254740991` → `UF001` `Mục tiêu quỹ không hợp lệ`.
5. `p_deadline is not null and p_deadline < current_date` → `UF001`
   `Hạn quỹ phải từ hôm nay trở đi`. `current_date` theo múi giờ DB (UTC); client giới hạn date
   picker từ hôm nay theo giờ máy; chênh lệch tối đa một ngày quanh nửa đêm được chấp nhận.
6. Cập nhật hai cột. Không ghi audit (sổ quỹ hiện cũng không ghi audit).

**Sửa — `join_expense_group`**

- Khi không tìm thấy mã: **không `raise`**; `return;` với 0 dòng, để lượt tăng `attempt_count`
  được commit. Client đã ném lỗi khi kết quả rỗng; chỉ đổi câu thông báo (mục 4.5).
- Lỗi vượt giới hạn: đổi `errcode` từ `P0001` sang `UF001`.
- Lỗi đầu vào sai định dạng (`null`, dài hơn 32 ký tự) giữ `22023`; client đã chặn trước.
- Phần còn lại không đổi.

**Sửa — `add_group_fund_entry`**: lỗi số dư không đủ đổi sang `UF001`. Logic không đổi.

**Sửa — `update_group_expense_custom`, `delete_group_expense`**: đổi
`v_actor_id <> v_payer_id` thành `v_actor_id is distinct from v_payer_id`. Logic khác không
đổi. Kết quả: bill của người đã xóa tài khoản chỉ trưởng nhóm sửa/xóa được.

**Sửa — `delete_group_fund_entry`**: đổi kiểm tra quyền thành
`v_entry.actor_id is distinct from v_user_id and v_owner_id <> v_user_id`. Dòng có `actor_id`
`null` chỉ trưởng nhóm xóa được.

### 4.4 Flutter — domain

- `lib/features/groups/domain/invite_link.dart` (mới):
  - `sealed class InviteLink` với một biến thể `GroupInviteLink(String code)`. Spec B sẽ thêm
    biến thể cho bill.
  - `static InviteLink? parse(String raw)`: `trim`; nếu là URI `hoadoninsight://join-group`
    thì lấy query `code`; nếu không phải URI thì coi cả chuỗi là mã. Mã hợp lệ khi sau
    `toUpperCase()` khớp `^[0-9A-F]{8}$`. Sai → `null`.
  - `static String groupUri(String code)` → `hoadoninsight://join-group?code=<code>`.
- `lib/features/groups/domain/group_fund_progress.dart` (mới): hàm thuần
  `GroupFundProgress.compute({required int balanceMinor, int? goalMinor, DateTime? deadline, required DateTime today})`
  trả `status` (`noGoal`, `inProgress`, `reached`, `overdue`), `ratio` (không chặn ở 1.0,
  `null` khi `noGoal`), `daysLeft` (âm khi quá hạn, `null` khi không có hạn).
  - `reached`: số dư ≥ mục tiêu, bất kể hạn.
  - `overdue`: chưa đạt và `today` (chỉ phần ngày) sau `deadline`.
  - Hạn đúng hôm nay: `inProgress`, `daysLeft == 0`.
- `group_models.dart`:
  - `ExpenseGroup` thêm `int? fundGoalMinor`, `DateTime? fundDeadline`.
  - `GroupFundEntry.actorId` thành `String?`.

### 4.5 Flutter — data (`group_service.dart`)

- `listGroups`: select thêm `fund_goal_minor, fund_deadline`.
- `listFundEntries`: chấp nhận `actor_id` `null`.
- Mới `Future<void> setFundGoal({required String groupId, int? goalMinor, DateTime? deadline})`
  — gửi `p_deadline` dạng `yyyy-MM-dd`.
- `joinGroup`: khi kết quả rỗng ném `StateError('Mã mời không hợp lệ.')`.

### 4.6 Flutter — presentation

**Màn quét dùng chung — `lib/shared/widgets/qr_scan_screen.dart` (mới).**
`QrScanScreen({required String title, required String? Function(String raw) validate})`:
`MobileScanner` với khung quét như `qr_payment_screen.dart`. Mỗi lần nhận mã, gọi `validate`;
trả về chuỗi lỗi thì hiện lỗi inline và quét tiếp; trả `null` thì `Navigator.pop(raw)`. Không
tự gọi server.

**Hiện QR mời — trong thẻ thành viên ở màn chi tiết nhóm.**
Dòng "Mã mời: X" và nút "Sao chép mã mời" thay bằng nút "QR mời vào nhóm". Nút mở bottom sheet:

- `QrImageView` (`qr_flutter`) với dữ liệu `InviteLink.groupUri(inviteCode)`, nền trắng cố
  định để quét được ở chế độ tối.
- Mã chữ bên dưới và nút "Sao chép mã".
- Mọi thành viên đều mở được (giống mã chữ hiện nay).

**Tham gia nhóm — màn danh sách nhóm.**
Nút "Tham gia" mở bottom sheet hai lựa chọn:

- *Quét mã QR* → `QrScanScreen` với `validate` = `InviteLink.parse(raw) is GroupInviteLink ? null : 'Mã QR không phải mã mời nhóm.'`
  → `joinGroup(code)` → mở nhóm như luồng cũ.
- *Nhập mã* → luồng `_askText` hiện có.

**Chia tiền — màn chi tiết nhóm.**

- Hai nút "Thêm khoản chi" và "Từ hóa đơn" thay bằng **một nút "Chia tiền"** (rộng hết hàng).
- Danh sách bên dưới đổi tiêu đề "Khoản chi" → **"Chia tiền"**, câu trống "Chưa có lần chia tiền
  nào trong nhóm." Thu chi của quỹ vẫn chỉ ở màn quỹ (thẻ "Quỹ chung").
- Nút mở **dialog "Chia tiền" toàn màn hình** (`Dialog.fullscreen`; `GroupSplitDialog`, file mới
  `group_split_dialog.dart`) để bàn phím không làm tràn khung trên điện thoại. Dialog gồm:
  - `TabBar` hai tab **"Nhập thủ công"** và **"Quét hóa đơn"**. Nội dung hai tab giữ trạng thái
    khi chuyển qua lại (dùng `IndexedStack`, không dùng `TabBarView`).
  - Tab "Nhập thủ công": biểu mẫu chia tiền trống (`GroupExpenseForm`) — nội dung, tổng tiền,
    chọn thành viên, chia đều / theo số tiền / theo phần trăm như dialog hiện nay.
  - Tab "Quét hóa đơn": trước khi quét hiện hai nút *Chụp ảnh hóa đơn* (`ImageSource.camera`) và
    *Chọn từ thư viện* (`ImageSource.gallery`), cùng `imageQuality: 92`, `maxWidth: 2400`. Đang
    đọc hóa đơn thì hiện vòng chờ. Đọc xong hiện **cùng biểu mẫu** đã điền sẵn
    `'Hóa đơn {sellerName}'` (bỏ tên nếu rỗng, tối đa 160 ký tự) và `totalMinor` (bằng 0 thì để
    trống), mặc định chia đều cho mọi thành viên; có nút "Quét hóa đơn khác".
  - Nút **"Chia tiền"** lưu biểu mẫu của tab đang mở (tắt khi tab Quét chưa có kết quả); nút
    "Hủy" hỏi xác nhận nếu đã nhập hoặc đã quét.
  - Việc chụp/chọn ảnh và gọi `importCoordinatorProvider.importImage` do màn nhóm truyền vào qua
    callback `onScan(ImageSource) → Future<ReceiptPrefill?>` (dialog không đọc provider, test
    được độc lập). Lưu đi qua `addEqualExpense` / `addCustomExpense` như hiện nay.
- Sửa một lần chia tiền vẫn mở dialog một biểu mẫu (`GroupExpenseDialog`, tiêu đề "Sửa lần chia
  tiền"), không có tab.
- Nhãn ô nội dung đổi "Nội dung chi" → "Nội dung".
- Xóa `_InvoiceAllocationDialog`, `_InvoiceAllocationDialogState`, `_InvoiceAllocationDraft`,
  `_InvoiceAllocationLine`.
- Thông điệp lỗi phía server của bill (`… khoản chi …` trong RPC `group_expense*`) giữ nguyên ở
  spec này; đổi chữ server để sau nếu team cần.

**Màn quỹ (`group_fund_screen.dart`).**

- Thẻ tiến độ theo `GroupFundProgress`:
  - `noGoal`: trưởng nhóm thấy nút "Đặt mục tiêu"; thành viên không thấy thẻ.
  - `inProgress`: thanh tiến độ, "64% của 10.000.000 ₫ · còn 56 ngày" (không có hạn thì bỏ
    phần ngày).
  - `reached`: màu success, cho phép vượt 100%.
  - `overdue`: màu warning, "Quá hạn N ngày".
- Dialog đặt mục tiêu (trưởng nhóm): ô số tiền, `showDatePicker` với `firstDate` là hôm nay,
  nút "Xóa mục tiêu" khi đã có mục tiêu.
- Dòng quỹ có `actorId == null` hiện "Tài khoản đã xóa"; nút "Xóa" chỉ hiện cho trưởng nhóm.

### 4.7 Dependency

Thêm `qr_flutter` vào `pubspec.yaml` (pure Dart, chạy trên Android, iOS và web; CI build cả
APK và web). Không thêm package nào khác.

## 5. Xử lý lỗi

- Server là nguồn đúng duy nhất cho quyền, số dư và mục tiêu; kiểm tra ở client chỉ để báo sớm.
- Lỗi RPC hiện qua `friendlyMessage`; lỗi `UF001` hiện nguyên câu tiếng Việt.
- Quét QR: mã không đúng định dạng báo lỗi ngay trên màn quét, không gọi server; mã đúng định
  dạng nhưng không tồn tại → "Mã mời không hợp lệ." và lượt thử được tính vào giới hạn.
- Camera bị từ chối quyền: `MobileScanner` báo lỗi qua `errorBuilder`; màn quét hiện hướng dẫn
  cấp quyền trong Cài đặt hoặc quay lại và chọn "Nhập mã mời".
- `importImage` lỗi (mạng, AI chưa cấu hình): tab "Quét hóa đơn" hiện "Không thể xử lý hóa đơn: …"
  ngay trong dialog, giữ hai nút quét để thử lại; dialog không đóng, tab "Nhập thủ công" vẫn dùng
  được. Người dùng huỷ chọn ảnh → không báo lỗi.

## 6. Test

### 6.1 Dart (`flutter test`, chạy trong CI)

- `test/features/groups/invite_link_test.dart` (mới): URI hợp lệ; mã trơn chữ thường được
  uppercase; sai scheme hoặc host; thiếu `code`; mã 7 hoặc 9 ký tự; ký tự ngoài `0-9A-F`;
  chuỗi rỗng; `groupUri` rồi `parse` cho lại đúng mã.
- `test/features/groups/group_fund_progress_test.dart` (mới): bốn trạng thái; hạn đúng hôm
  nay; vượt mục tiêu `ratio > 1`; đạt mục tiêu sau hạn là `reached`; không có hạn thì
  `daysLeft == null`.
- `test/shared/errors/error_presenter_test.dart`: `UF001` trả nguyên `message`; `22023` và
  `P0001` vẫn trả câu chung.
- `test/features/groups/group_expense_dialog_test.dart` (mới): biểu mẫu nhận
  `initialDescription` và `initialTotalMinor`; tổng 0 để trống; có `initialExpense` thì bỏ qua hai
  giá trị này; `receiptExpenseDescription` cắt 160 ký tự.
- `test/features/groups/group_split_dialog_test.dart` (mới): có hai tab; tab "Nhập thủ công" trả
  bản nháp chia đều; tab "Quét hóa đơn" với `onScan` giả điền sẵn đúng và trả bản nháp; `onScan`
  ném lỗi → hiện lỗi trong dialog, vẫn còn nút quét; `onScan` trả `null` → không báo lỗi;
  chuyển tab không mất chữ đã nhập; nút "Chia tiền" tắt khi tab Quét chưa có kết quả.

### 6.2 SQL (`supabase/tests/group_qr_fund_goal_test.sql`, pgTAP qua `supabase test db`)

Chạy local với Docker; CI chưa chạy.

1. Trưởng nhóm đặt mục tiêu và hạn → hai cột đúng; `p_goal_minor = null` xóa cả hạn.
2. Thành viên thường gọi `set_group_fund_goal` → `UF001`.
3. Hạn trong quá khứ → `UF001`; mục tiêu ≤ 0 → `UF001`.
4. Đặt `fund_deadline` khi `fund_goal_minor` null bằng `update` trực tiếp → vi phạm constraint.
5. `join_expense_group` với mã không tồn tại → 0 dòng, `attempt_count` tăng; lần thứ 11 trong
   một phút → `UF001`.
6. `join_expense_group` với mã đúng → vào nhóm, `attempt_count` về 0.
7. `add_group_fund_entry` chi vượt số dư → `UF001`.
8. Bill có `payer_id` null: thành viên thường gọi `update_group_expense_custom` hoặc
   `delete_group_expense` → `42501`; trưởng nhóm làm được.
9. Dòng quỹ có `actor_id` null: thành viên thường gọi `delete_group_fund_entry` → lỗi quyền;
   trưởng nhóm xóa được.
10. Xóa user có dòng quỹ → `actor_id` thành `null`, xóa không bị chặn.

## 7. Triển khai

1. `supabase db reset` local, chạy `supabase test db`.
2. `npx supabase db push --dry-run`, rồi `npx supabase db push`.
3. Phát hành app mới. App cũ vẫn chạy với DB mới: cột mới nullable, chữ ký RPC không đổi; app
   cũ hiện câu lỗi chung thay vì câu `UF001` và nhận "Không tham gia được nhóm." khi mã sai.
