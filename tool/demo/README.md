# Tài khoản demo B0 / B1: dữ liệu mẫu và reset

> **BẢN NHÁP, CHƯA CHẠY THỬ.** Hai file SQL được viết bằng cách đọc migration và mã Dart; chưa có
> lần nào chạy trên Postgres/Supabase thật (không có DB, không có supabase CLI). Chạy thử trên
> **project nháp** trước, đọc kết quả, rồi mới dùng trên project demo.

| File | Việc |
| --- | --- |
| `seed_demo_account.sql` | Nạp dữ liệu mẫu cho **một** tài khoản `demo-*`; chạy lại không nhân đôi dòng. |
| `reset_demo_account.sql` | Xóa những gì phát sinh trong buổi demo, giữ nguyên dữ liệu mẫu. |
| `seed_expectations.json` | Khóa trong `expected_keys` của `tool/benchmark/chat_questions_40.json` → chuỗi phải có trong câu trả lời. |
| `check_seed_expectations.py`, `test_check_seed_expectations.py` | Báo lỗi nếu thiếu khóa; tính lại các giá trị kỳ vọng từ chính các dòng `VALUES` trong SQL. |

## 1. Nguyên tắc

- **Mỗi bản một tài khoản** (`demo-b0@…`, `demo-b1@…`). Dùng chung một tài khoản thì ảnh nhập ở B0 sync sang B1
  và làm cảnh 5 (chặn trùng) sai (Review Focus 1).
- **Dữ liệu giống hệt nhau:** cả hai tài khoản chạy **cùng một file** `seed_demo_account.sql`; mọi số tiền, tên cửa
  hàng, ngày trong tháng là hằng số trong file. Chỉ id của nhóm/mã mời suy ra từ user id (để không đụng khóa duy nhất).
  Sau khi nạp, dùng truy vấn ở mục 5 để so mã băm dữ liệu của hai tài khoản.
- **App là local-first.** Câu hỏi tra cứu được trả lời từ SQLite trên máy **sau khi đồng bộ**, nên dữ liệu phải nằm
  ở bảng mà app kéo về (xem mục 7), không phải bảng tùy ý.

## 2. Tạo hai tài khoản

1. Supabase Dashboard → Authentication → Users → *Add user* → *Create new user*: email `demo-b0@<miền-của-bạn>`
   và `demo-b1@<miền-của-bạn>`, đặt mật khẩu, bật **Auto Confirm User**. Email **phải bắt đầu bằng `demo-`**,
   cả hai script đều từ chối nếu không.
2. Ghi lại UUID của từng người dùng (cột *User UID*).
3. Đăng nhập một lần bằng email/mật khẩu trên mỗi bản app (B0 cổng 8080, B1 cổng 8081) và hoàn tất hồ sơ nếu app yêu cầu.

## 3. Nạp dữ liệu mẫu

1. Mở `seed_demo_account.sql`, thay UUID `0000…` ở dòng `EDIT HERE`.
2. Dán **toàn bộ** file vào SQL editor, chạy một lần (user id nằm trong một setting của phiên; chạy từng câu rời
   sẽ lỗi). Thành công thì có `NOTICE Seeded …` và một bảng `key | vnd_digits`.
3. So bảng đó với `seed_expectations.json` (các khóa MANUAL cũng có giá trị của hôm nay ở đó).
4. Đổi UUID, chạy lại cho tài khoản thứ hai.

Chạy lại bất cứ lúc nào là an toàn: id cố định `demo-seed-…`, upsert, tăng `revision` để thiết bị kéo lại; dòng mẫu
không còn thuộc cửa sổ ngày hiện tại được đánh dấu xóa (tombstone).

**Cửa sổ ngày.** Ngày tương đối so với `now()` theo múi giờ Asia/Ho_Chi_Minh, 12:00 trưa, ngày ≤ 28:
tháng này (`c`), tháng trước (`p`), hai tháng trước (`q`), cộng tháng cố định `2026-10` (`f`, bản sao của `p`, chỉ
thêm khi 2026-10 chưa là một trong ba tháng trên). **Giá trị kỳ vọng được tính cho lần chạy trong tháng 2026-11**;
chạy ở tháng khác thì script in `NOTICE`: tháng 2026-12 làm Q06 và Q12 lệch, tháng 2026-10 làm Q01/Q06/Q12 lệch, và từ
2027 câu "Tháng 10" sẽ trỏ 2027-10 (app dùng năm hiện tại).

## 4. Reset giữa các lần demo

1. Đợi cả hai bản đồng bộ xong (không còn thay đổi chờ gửi), rồi dán `reset_demo_account.sql` với UUID tài khoản.
2. Kết quả là bảng số dòng đã xử lý theo từng bảng. Dòng cuối kiểm tra dữ liệu mẫu còn nguyên.
3. Nên chạy lại `seed_demo_account.sql` ngay sau reset (khôi phục ngân sách nếu bị sửa; rẻ vì idempotent).
4. Trên mỗi bản app: kéo để đồng bộ. Nếu còn dữ liệu cũ trên máy (lịch sử chat, khoản nợ sửa tay), xóa dữ liệu site
   của cổng đó rồi đăng nhập lại.

**Dấu hiệu "tạo trong buổi demo":** id **không** bắt đầu bằng `demo-seed-`. Dữ liệu mẫu có id cố định mang tiền tố đó;
app tạo bản ghi mới bằng UUID. Không dùng mốc `created_at` vì seed chạy lại sẽ đổi mọi mốc và đồng hồ app/DB có thể lệch.

| Bảng | Xử lý | Ghi chú |
| --- | --- | --- |
| `invoices`, `income_entries`, `planning_entries` | đánh dấu xóa (tombstone) | xóa hẳn thì máy vẫn giữ bản ghi; chỉ tombstone mới lan sang thiết bị. Chỉ mục trùng `source_hash` bỏ qua dòng đã xóa, nên ảnh X nhập lại sẽ không bị chặn giả. |
| `ai_extraction_jobs` | xóa | job OCR/trích xuất của tài khoản |
| `ocr_request_replay`, `ai_client_events` | xóa nếu bảng tồn tại | bảng nằm ở nhánh TV1/TV3, chưa có trong nhánh này (`to_regclass`) |
| `chat_messages` | xóa (cờ `demo_reset.chat`, mặc định bật) | lịch sử chat đổi ngữ cảnh gửi LLM nên làm lệch phép đo |
| `ai_usage_buckets`, `ai_cost_usage`, `ai_usage_daily` | xóa chỉ khi `demo_reset.quota = true` | mặc định tắt |
| `ai_request_metrics` | **không đụng** | đó chính là số đo của buổi demo |

Không xử lý: ngân sách (id theo quy ước app `<yyyy-MM>-<danh mục>`, không phân biệt được), nhóm/quỹ (thuộc dữ liệu
mẫu), file ảnh trong Storage (xóa trên dashboard nếu cần), dữ liệu chỉ có trên thiết bị.

## 5. Kiểm tra hai tài khoản giống hệt

```sql
select u.email,
  (select md5(string_agg(i.id || '|' || i.seller_name || '|' || i.total_minor || '|' || i.category_id || '|'
     || to_char(i.issued_at at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM-DD'), ',' order by i.id))
     from public.invoices i where i.user_id = u.id and i.deleted_at is null and i.id like 'demo-seed-%') as invoices_md5,
  (select md5(string_agg(e.id || '|' || e.amount_minor || '|' || e.category_id, ',' order by e.id))
     from public.income_entries e where e.user_id = u.id and e.deleted_at is null and e.id like 'demo-seed-%') as income_md5,
  (select md5(string_agg(b.id || '|' || b.limit_minor, ',' order by b.id))
     from public.budgets b where b.user_id = u.id) as budgets_md5
from auth.users u
where lower(u.email) like 'demo-%';
```

Ba cột mã băm của `demo-b0` và `demo-b1` phải bằng nhau. Sau đó trong app, hỏi vài câu ở cả hai bản (Q01, Q03, Q05, Q10)
và so với bảng ở mục 6.

## 6. Giá trị kỳ vọng

Mỗi giá trị là **dãy chữ số có dấu chấm** (hoặc tên), không kèm ký hiệu tiền. Lý do: `MoneyFormatter` dùng
`NumberFormat.currency(locale: 'vi_VN', symbol: '₫')`, tức `10.545.000 ₫` với khoảng trắng giữa số và `₫`. Khoảng trắng này
nhiều khả năng là NBSP (U+00A0) của dữ liệu `intl`, chưa kiểm chứng bằng chạy thật; câu do LLM trả lời (B0, đường lệnh) còn có
thể viết `đ` hay `triệu`. Dãy số là chuỗi con chắc chắn nhất của cả hai. Bộ chạy 40 câu (T3.2) nên so khớp theo chuỗi con
và chuẩn hóa mọi khoảng trắng (NBSP, NNBSP) về dấu cách.

| Khóa | Giá trị | Câu | Cách tính / điều app in ra |
| --- | --- | --- | --- |
| `expense_total_current` | `10.545.000` | Q01, Q06, Q30 | tổng hóa đơn `confirmed` tháng này (18 dòng `c`) |
| `expense_total_previous` | `9.315.000` | Q06 | tổng tháng trước (14 dòng `p`) |
| `expense_total_2026_10` | `9.315.000` | Q12 | cố ý bằng tháng trước: tháng 10/2026 là `p` (chạy trong 11/2026) hoặc bản sao `f` |
| `income_total_current` | `18.500.000` | Q02, Q30, Q31, Q34 | 15.000.000 lương + 3.500.000 thưởng, tháng này |
| `budget_remaining_current` | `12.000.000` | Q03 | tổng hạn mức tháng này. **App không in số còn lại** (chỉ "Đã chi A trên tổng ngân sách B (x%)"); còn lại = 1.455.000, nhưng giá trị kỳ vọng dùng B để câu cục bộ cũng đạt |
| `top_category_current` | `4.265.000` | Q05 | Ăn uống là danh mục lớn nhất (tiếp theo Tiện ích 3.220.000, Mua sắm 1.500.000) |
| `debt_creditors` | `Anh Minh` | Q04, Q33 | **khoản nợ nằm trên thiết bị, SQL không nạp được**: tạo tay theo mục 8 |
| `recurring_list` | `Thuê nhà` | Q08 | khoản chi định kỳ lớn nhất theo engine (Thuê nhà 3.000.000, Netflix 260.000, FPT Internet 220.000; mỗi tháng cùng ngày, cùng số tiền) |
| `anomaly_summary` | `540.000` | Q09 | Highlands Coffee 540.000 ₫, "Cao hơn khoảng 9.0 lần mức trung bình trước đây" (4 lần cũ cùng 60.000); là bất thường duy nhất |
| `recent_invoices_first` | `The Pizza Company` | Q10 | dòng chèn cuối cùng nên có `updated_at` mới nhất (xem rủi ro 3 ở mục 9) |

### Khóa MANUAL và lý do

| Khóa | Lý do | Giá trị tay |
| --- | --- | --- |
| `forecast_month_end` (Q07) | `round(tổng tháng này / ngày hôm nay × số ngày trong tháng)` phụ thuộc ngày chạy demo | ngày 28/11/2026: 10.545.000/28×30 = **11.298.214** (script seed in giá trị hôm nay ở dòng `forecast_month_end (today)`) |
| `scenario_saving_500k` (Q11) | `thu nhập tháng này − dự báo + 500.000` dùng cùng dự báo trên | ngày 28/11/2026: 18.500.000 − 11.298.214 + 500.000 = **7.701.786** (dòng `scenario_saving_500k (today, 1 month)`). Phần cố định của câu: "Nếu bạn điều chỉnh 500.000 ₫ mỗi tháng" |
| `group_fund_travel_balance` (Q20) | Q20 đi đường `cloud` (LLM + công cụ nhóm), cách viết số do mô hình quyết | số dư quỹ "Du lịch Đà Lạt" = 3.000.000 + 2.000.000 − 1.250.000 = **3.750.000** |

### Hai điều lạ của app đã được dữ liệu mẫu bù sẵn

- **Q06 ("so sánh tháng này với tháng trước") trả lời cho THÁNG TRƯỚC.** `_monthFromQuestion` gặp "tháng trước" thì lùi một
  tháng, nên câu trả lời in tổng tháng trước (`9.315.000`) và tổng tháng kề trước đó, không in tổng tháng này. Seed cho
  tháng `q` có tổng đúng bằng tháng này (10.545.000) để cả hai khóa vẫn thỏa; nếu về sau sửa app để giữ tháng hiện tại thì
  vẫn thỏa. Hệ quả: dữ liệu 3 tháng `c/p/q` phải giữ đúng các tổng đó (test kiểm).
- **Q03 không in số tiền còn lại**, xem bảng trên.

## 7. Bảng nào được nạp, vì sao

| Dữ liệu | Bảng cloud | Cách app kéo về |
| --- | --- | --- |
| Hóa đơn/chi tiêu | `invoices` | RPC `pull_invoice_changes`, con trỏ `(updated_at, id)`; `updated_at` do trigger `invoices_server_updated_at` ghi đè = giờ chèn, nên thứ tự chèn quyết định "hóa đơn gần đây" |
| Khoản thu | `income_entries` | `pull_income_changes` |
| Hóa đơn định kỳ | `planning_entries` (`kind = 'bill'`) | `pull_plan_changes`. **Không** tạo thu nhập định kỳ vì AppShell tự ghi khoản thu khi đến hạn |
| Ngân sách | `budgets` **và** `reference_sync_events` | `pull_reference_changes` chỉ đọc nhật ký `reference_sync_events`, không đọc bảng `budgets`; chỉ ghi bảng thì thiết bị không thấy |
| Nhóm, quỹ | `expense_groups`, `expense_group_members`, `group_fund_entries` | app đọc trực tiếp từ Supabase |
| Danh mục | `categories` (đủ 8 mặc định để khóa ngoại của ngân sách đúng) | đã có sẵn trên máy |
| Khoản nợ | **không có bảng cloud** | `SharedPreferences`, khóa `finmi.debts.<userId>.v1` trên từng trình duyệt |

## 8. Khoản nợ (làm tay, cho cả hai bản)

Trong **mỗi** bản app, màn Khoản nợ, tạo đúng ba khoản:

| Loại | Người | Số tiền |
| --- | --- | --- |
| Mình nợ | Anh Minh | 2.000.000 |
| Mình nợ | Chị Lan | 1.200.000 |
| Người khác nợ mình | Bạn Hùng | 800.000 |

Q04/Q33 chỉ liệt kê khoản "mình nợ", lớn nhất trước: `Bạn nợ Anh Minh: 2.000.000 ₫` rồi `Bạn nợ Chị Lan: 1.200.000 ₫`.

Cách nhanh hơn (**chưa thử**): mở DevTools Console trên `http://localhost:8080` rồi `http://localhost:8081`, dán đoạn dưới
với `uid` là UUID của tài khoản đang đăng nhập ở cổng đó, tải lại trang. `shared_preferences_web` 2.4.3 ghi giá trị chuỗi
dưới dạng JSON, nên phải mã hóa hai lần.

```js
const uid = '<USER_UUID>';
const at = '2026-11-01T09:00:00.000';
const debt = (id, personName, type, amountMinor) => ({id, personName, phoneNumber: null, type,
  amountMinor, paidAmountMinor: 0, dueDate: null, createdAt: at, notes: null, status: 'active', settledAt: null});
const debts = [debt('demo-debt-1', 'Anh Minh', 'iOwe', 2000000),
               debt('demo-debt-2', 'Chị Lan', 'iOwe', 1200000),
               debt('demo-debt-3', 'Bạn Hùng', 'theyOwe', 800000)];
localStorage.setItem('flutter.finmi.debts.' + uid + '.v1', JSON.stringify(JSON.stringify(debts)));
```

Reset không xóa khoản nợ (nằm trên máy). Nếu cảnh demo tạo thêm nợ (ví dụ Q23, Q24), xóa tay hoặc xóa dữ liệu site.

## 9. Những điều dễ làm hỏng buổi demo

1. **Dùng chung một tài khoản cho B0 và B1:** ảnh nhập ở B0 sync sang B1, cảnh 5 sai. Luôn hai tài khoản.
2. **Chạy seed ở tháng khác tháng 11/2026:** xem mục 3. Nếu bắt buộc, chạy rồi đọc bảng kết quả, cập nhật `seed_expectations.json`
   và `MONTH_OF` trong test.
3. **Thứ tự "hóa đơn gần đây":** dựa vào `updated_at` do trigger đặt. Seed chèn có thứ tự và nghỉ 2 ms giữa các dòng; chạy lại
   seed hay sửa một hóa đơn mẫu trong app sẽ đổi thứ tự. Mọi hóa đơn nhập trong buổi demo cũng đứng trước hóa đơn mẫu (Q10 chỉ đúng sau reset).
4. **Lệnh ghi trong bộ 40 câu (Q21–Q28):** đừng xác nhận; nếu đã xác nhận thì tổng thay đổi và mọi phép đo sau đó sai. Chạy reset + seed.
5. **Chưa đồng bộ trước khi hỏi:** câu tra cứu đọc SQLite cục bộ; chưa kéo thì thiếu dữ liệu. Kéo để làm mới sau mỗi seed/reset.
6. **Reset khi máy còn thay đổi chưa gửi:** hàng đợi gửi có thể ghi đè tombstone. Đợi đồng bộ xong trước.
7. **Mật khẩu/UUID trong lệnh:** UUID là dữ liệu của project demo; không commit file SQL đã điền UUID.

## 10. Rủi ro schema đã gặp (cần người đọc kiểm)

- **Chưa có bản chạy thử.** Mọi tên cột lấy từ migration; các cột chưa chắc: `invoices.discount_minor` (migration `20261006100000`),
  `income_entries.note/category_id/source`, `expense_groups.fund_goal_minor` (không dùng), `profiles` (tự thêm nếu thiếu dòng).
- Khoản nợ chỉ có ở thiết bị, nên SQL không bảo đảm được `debt_creditors`.
- `reference_sync_events.event_id` có giá trị duy nhất theo người dùng; script thêm hậu tố thời gian và chỉ phát sự kiện khi hạn mức đổi.
- Hai bảng `ocr_request_replay` và `ai_client_events` chưa có trong nhánh này; reset bỏ qua nếu thiếu.
- Hóa đơn mẫu không có dòng hàng (`invoice_lines`), không có `source_hash`.

## 11. Chạy kiểm tra

```bash
cd tool/demo
python -m unittest
python check_seed_expectations.py
```
