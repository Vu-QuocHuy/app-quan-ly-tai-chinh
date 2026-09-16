# Quản lý Tài chính

Ứng dụng Flutter local-first để quản lý thu chi cá nhân và nhóm: nhập hóa đơn điện tử Việt Nam từ XML, PDF có text, camera/ảnh OCR hoặc nhập tay; kiểm tra dữ liệu trước khi lưu; tự phân loại; phát hiện trùng; theo dõi chi tiêu, ngân sách và xu hướng tài chính.

## Kiến trúc

- Flutter + Material 3, Riverpod, GoRouter.
- Drift/SQLite; tiền lưu bằng số nguyên theo đơn vị nhỏ nhất.
- Adapter ingestion thống nhất cho XML, PDF text và OCR.
- ML Kit OCR chạy trên thiết bị. AI là tùy chọn và có fallback offline.
- Supabase Edge Function gọi Gemini Structured Output; secret chỉ ở backend.
- Trợ lý chi tiêu có bộ tool local read-only, chỉ gọi tool phù hợp với câu hỏi; Gemini `/v1/chat` là tùy chọn và citation cho dữ liệu nguồn.
- Câu trả lời từ dữ liệu local không gọi Gemini. Khi cần Gemini, client và Edge Function chỉ cho phép facts tổng hợp, loại bỏ invoice ID/merchant/kết quả tìm kiếm và ẩn thông tin định danh trong câu hỏi/lịch sử.
- Connector tỷ giá chỉ gọi provider allowlist ở backend, có timeout và hiển thị nguồn cập nhật.
- Nhóm chi tiêu dùng Supabase RLS: tạo/tham gia bằng mã mời, chia đều/theo số tiền/theo phần trăm, OCR hóa đơn để gán từng dòng cho thành viên và ghi nhận tất toán.

## Chạy app một lượt

Yêu cầu Flutter `3.47.1`, Dart `3.12+`, Android SDK và JDK 17.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart format lib test
flutter analyze
flutter test
flutter run --dart-define=APP_ENV=dev
```

Không truyền cấu hình cloud/AI thì app vẫn chạy đầy đủ bằng XML/PDF deterministic và OCR fallback offline.

## Bật Supabase Auth và đồng bộ

Project Supabase được quản lý bằng migration trong `supabase/migrations`. Cấu hình
dev thật nằm ở `config/supabase.local.json` và đã được gitignore; file mẫu có tại
`config/supabase.example.json`.

```bash
flutter run \
  --dart-define=APP_ENV=dev \
  --dart-define-from-file=config/supabase.local.json
```

Trong app, mở **Cài đặt → Tài khoản và đồng bộ** để đăng ký hoặc đăng nhập.
OCR và SQLite vẫn hoạt động offline; các thay đổi hóa đơn được giữ trong outbox
và đẩy lên Supabase khi người dùng đăng nhập rồi bấm **Đồng bộ ngay**. Khi mở
lại app, hệ thống tự chạy best-effort sync; dữ liệu cloud mới được tải theo
cursor delta và không tạo vòng lặp outbox. Danh mục, ngân sách và quy tắc merchant
cũng đi qua outbox, được áp dụng atomically bằng RPC riêng và tải ngược theo
cursor delta có tombstone.

Nếu hai thiết bị sửa cùng một hóa đơn ở cùng `revision`, app giữ bản local,
lưu snapshot cloud và đánh dấu `conflict` để không âm thầm ghi đè dữ liệu. Mở
**Cài đặt → Xung đột dữ liệu** để chọn bản cloud hoặc giữ bản trên máy; lựa chọn
giữ bản local sẽ tạo revision mới và xếp lại outbox.

Thay đổi schema cloud phải tạo migration mới, kiểm tra rồi mới đẩy:

```bash
npx supabase db push --dry-run
npx supabase db push
```

## Fine-tune OCR hóa đơn Việt Nam

Thư mục [`ml/receipt_ocr`](ml/receipt_ocr/README.md) chứa pipeline độc lập để chuẩn
bị dataset, fine-tune `PP-OCRv5_mobile_rec`, đo CER/WER, export và version model.
Pipeline có notebook Kaggle; không cần cấu hình model để chạy Flutter hiện tại.
ML Kit tiếp tục là baseline/fallback cho đến khi model fine-tuned vượt evaluation
gate và có artifact đã ký version.

Hướng dẫn thao tác đầy đủ: [Kaggle OCR runbook](ml/receipt_ocr/KAGGLE_RUNBOOK_VI.md).

## Bật backend AI bằng Supabase Edge Function

AI chỉ được gọi khi người dùng đã đăng nhập Supabase. Gemini API key không nằm trong APK; key được lưu trong Supabase Secrets.

Đăng nhập Supabase CLI, liên kết project và đặt secret:

```bash
supabase link --project-ref YOUR_PROJECT_REF
supabase secrets set GEMINI_API_KEY=your_gemini_key
supabase functions deploy ai-api
```

Chạy app:

```bash
flutter run --dart-define-from-file=config/supabase.local.json
```

Mặc định lệnh trên chạy flavor `dev`. Với staging hoặc production, dùng thêm
`--flavor staging`/`--flavor production` và đặt `APP_ENV` tương ứng.

Sau khi backend đã cấu hình `GEMINI_API_KEY`, app có thể hỏi bằng tiếng Việt các câu hỏi ngoài phạm vi dữ liệu local. Các câu hỏi về tổng chi, danh mục, ngân sách, so sánh tháng, hóa đơn gần đây và khoản chi định kỳ được trả lời trực tiếp từ tool local; nếu Gemini được gọi, dữ liệu hóa đơn cấp dòng không được gửi đi.

Các câu hỏi tỷ giá như “tỷ giá USD/VND hôm nay” sẽ dùng connector ExchangeRate-API ở backend và trả về citation. Provider này là dữ liệu tham khảo, cập nhật theo lịch của nhà cung cấp; không dùng làm chứng từ hoặc quyết định tài chính tự động.

Function `ai-api` bật `verify_jwt = true`; chỉ phiên Supabase hợp lệ mới được gọi Gemini.

## Nguồn nhập hỗ trợ

- XML hóa đơn: parse trực tiếp, namespace-tolerant, ưu tiên độ chính xác.
- PDF có text layer: đọc tối đa 100 trang; PDF scan được hướng sang camera/ảnh OCR.
- Ảnh/camera: ML Kit OCR on-device, sau đó AI structured extraction nếu cấu hình; lỗi mạng tự fallback offline.
- Nhập tay: luôn sẵn sàng khi không có file/ảnh.
- QR: để ở nhãn Experimental và chưa bật cho đến khi có provider hợp pháp, ổn định.

## Quản lý dữ liệu và vận hành

- Export toàn bộ dữ liệu hóa đơn ra JSON đầy đủ, CSV tương thích Excel/Google Sheets hoặc PDF báo cáo tham khảo gồm tổng quan, ngân sách, danh mục và danh sách hóa đơn.
- Có thể xuất backup mã hóa `.hdbak` bằng mật khẩu người dùng (AES-256-GCM + PBKDF2-HMAC-SHA256); khi khôi phục, ứng dụng kiểm tra checksum/integrity trước khi ghi dữ liệu.
- Có thể tải backup `.hdbak` đã mã hóa lên bucket private `invoice-backups` của Supabase; app hỗ trợ xem danh sách, tải để xem trước/khôi phục, xóa và tự dọn bản quá 90 ngày hoặc vượt 20 file. Đường dẫn được giới hạn theo user và không upload plaintext.
- Có thể chỉnh sửa danh sách hàng hóa/dịch vụ ngay trong màn hình kiểm tra trước khi xác nhận.
- Import nhiều file chạy tuần tự, có tiến độ, tiếp tục các file còn dang dở sau khi app bị đóng và có thể hủy giữa chừng.
- Dashboard cảnh báo khi đã dùng từ 80% ngân sách hoặc vượt ngân sách.
- Android/iOS có local notification cho cảnh báo ngân sách, chống gửi lặp theo tháng/mức cảnh báo; chạm notification mở thẳng màn hình Ngân sách. Quyền thông báo chỉ được xin khi người dùng bật tùy chọn.
- Merchant chưa có quy tắc local có thể được phân loại qua Supabase Edge Function khi đã đăng nhập; lỗi mạng vẫn giữ luồng offline-first.
- Supabase Auth email/password, PostgreSQL RLS theo người dùng và bucket riêng tư `receipt-images`; đồng bộ push/pull áp dụng hóa đơn, dòng hàng, evidence, danh mục, ngân sách và quy tắc merchant.
- Dữ liệu nhóm chỉ hiển thị cho thành viên nhóm; các RPC kiểm tra membership, tổng phần chia và yêu cầu user xác nhận trước khi ghi khoản chi.

## Chất lượng và bảo mật

CI chạy format, analyze, unit/widget tests, Android debug build và kiểm tra Supabase Edge Function. Xem [security baseline](docs/SECURITY.md), [implementation plan](IMPLEMENTATION_PLAN.md) và [quyết định UI](design-system/hoadon-insight/IMPLEMENTATION.md).
