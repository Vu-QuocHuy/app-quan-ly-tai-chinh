# Bàn giao Finmi: cập nhật main, Supabase và chạy app

Tài liệu dành cho teammate nhận bản tích hợp giao diện local, các chức năng từ remote main và nâng cấp FinmiAI/voice ngày 23/10/2026. Nhánh nhận code là `main`. Push Git chỉ cập nhật mã nguồn; CI hiện kiểm tra code và Supabase local, không tự triển khai migration hoặc Edge Function lên Supabase thật.

## 1. Nhận code

Lưu công việc đang sửa trước khi chuyển nhánh. Chạy tại thư mục gốc repo:

```powershell
git fetch origin
git switch main
git pull --ff-only origin main
git rev-parse HEAD
flutter pub get
```

Nếu `--ff-only` thất bại, kiểm tra các commit local trước khi tích hợp; không reset hoặc force push để bỏ qua khác biệt.

Không cần gửi riêng thư mục build, `.dart_tool`, cache SDK hoặc `node_modules`. Mã nguồn app, assets, migration, Edge Function, test và công cụ cần thiết nằm trong repo. `config/supabase.local.json` và secrets được cấu hình riêng trên máy/môi trường triển khai.

## 2. Cập nhật Supabase trước khi phát hành app

Chọn đúng project mà app sẽ kết nối. Kiểm tra bản sao lưu theo quy trình của môi trường trước khi cập nhật database đang sử dụng.

```powershell
npx supabase login
npx supabase link --project-ref <PROJECT_REF>
npx supabase migration list
npx supabase db push --dry-run
```

Đọc danh sách migration còn thiếu. Hai migration bổ sung trong đợt tích hợp này so với remote main trước đó:

| File | Mục đích |
| --- | --- |
| `20261022130000_unique_phone_rpc.sql` | Chuẩn hóa số điện thoại, xử lý trùng và cập nhật hồ sơ/thành viên qua RPC. |
| `20261023140000_update_own_group_fund_entry.sql` | Thêm RPC sửa khoản quỹ do người dùng tạo; kiểm tra quyền, trạng thái trước khi sửa và số dư quỹ. |

`db push` áp dụng tất cả migration còn thiếu theo lịch sử, không chỉ hai file trên. Các migration nhóm/quỹ trước đó cũng phải có. Nếu lịch sử remote khác repo, đối chiếu trước khi tiếp tục; không đánh dấu migration đã chạy khi chưa kiểm tra schema, không dùng `db reset` trên remote.

Sau khi duyệt danh sách:

```powershell
npx supabase db push
npx supabase functions deploy ai-api
```

Chạy deploy từ thư mục repo để CLI đóng gói các import trong `supabase/functions/_shared/`, bao gồm schema lệnh AI. Giữ `[functions.ai-api] verify_jwt = true` trong `supabase/config.toml`; không thêm `--no-verify-jwt` cho `ai-api`.

Nếu backend chưa nhận phần tích hợp 9Router từ đợt main này, deploy thêm:

```powershell
npx supabase functions deploy ai-worker
npx supabase functions deploy health
```

Các function này dùng cấu hình xác thực tương ứng trong `supabase/config.toml`. Không cần deploy lại `delete-account` chỉ vì bản nâng cấp FinmiAI này.

### Secrets và dịch vụ AI

Kiểm tra tên secrets đang có bằng `npx supabase secrets list`, cấu hình giá trị qua Supabase Dashboard hoặc quy trình quản lý secrets của nhóm:

| Secret | Yêu cầu |
| --- | --- |
| `NINER_ROUTER_API_KEY` | Key hợp lệ của 9Router. |
| `NINER_ROUTER_BASE_URL` | API base URL HTTPS tương thích OpenAI, thường kết thúc bằng `/v1`; không phải URL trang quản trị. |
| `NINER_ROUTER_MODEL` | Tùy chọn; mặc định trong code là `cx/gpt-5.6-luna[1m]`. |

Không có secret bắt buộc mới so với phần tích hợp 9Router. Router cần hỗ trợ `/audio/transcriptions` và model `openai/gpt-4o-transcribe` cho voice native/web fallback. Không đưa key AI, service-role key, access JWT hoặc mật khẩu database vào Flutter/Git.

## 3. Cấu hình và chạy web

Flutter theo CI: `3.47.1`. Tạo cấu hình local từ mẫu nếu máy chưa có file:

```powershell
Copy-Item config/supabase.example.json config/supabase.local.json
```

Điền `SUPABASE_URL` và `SUPABASE_PUBLISHABLE_KEY` của đúng project. File local được Git bỏ qua. Không ghi đè cấu hình local đã có; không dùng service-role key trong file này. Nếu dùng Google OAuth, kiểm tra provider và danh sách redirect URL trên Supabase cho URL app thực tế, gồm các port local đang dùng.

Chạy một màn web:

```powershell
flutter run -d chrome --web-port=8080 --web-hostname=localhost --dart-define=APP_ENV=dev --dart-define-from-file=config/supabase.local.json
```

Chạy hai màn trên Windows bằng launcher có sẵn:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\run_dual_instances.ps1
```

Launcher mở server và trình duyệt tại `http://localhost:8080/` và `http://localhost:8081/`. Chờ server biên dịch xong rồi tải lại nếu tab mở sớm. Dùng hai tài khoản khác nhau khi kiểm tra nhóm/quỹ. Hai port không đồng bộ dữ liệu local với nhau; nợ hiện vẫn lưu local theo tài khoản, chưa có đồng bộ nợ qua Supabase.

Voice/camera cần localhost hoặc HTTPS và quyền micro/camera trên trình duyệt. Hai màn cần được kiểm tra quyền riêng theo từng origin/port.

## 4. Kiểm tra trước khi phát hành

Kiểm tra local:

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
node tool/test_voice_web.mjs
npx deno test supabase/functions/_shared/assistant_guard_test.ts
npx deno run --node-modules-dir=none --allow-read tool/test_ai_fund_migration.mjs
```

Test migration dùng PostgreSQL PGlite cô lập, không kết nối Supabase thật. Lần đầu chạy Deno có thể tải runtime/dependency; fixture này không thay thế kiểm tra Supabase/RLS thực tế. CI còn kiểm tra code sinh tự động, build Android/web và toàn bộ migration trên Supabase local.

Kiểm tra trên môi trường test sau khi deploy backend:

- VI/EN: “Bạn là ai?” giới thiệu FinmiAI; “Tôi là ai?”/“Neural Network là gì?” bị từ chối. Câu trả lời theo ngôn ngữ giao diện, kể cả đầu vào khác ngôn ngữ.
- Nợ: “Tôi vay Nam 500k” và “Tôi cho Nam vay 500k” đúng chiều; thiếu chiều nợ phải hỏi lại, chưa ghi dữ liệu.
- Thu/chi: tạo khoản rồi “Sửa khoản vừa ghi thành 600k” sửa cùng ID; kiểm tra không tạo bản ghi dư.
- Lịch: thu định kỳ hàng tháng; chi định kỳ tạo lịch nhắc, không tự coi là khoản đã thanh toán.
- Nhóm/quỹ: tạo nhóm, thu/chi quỹ, sửa khoản quỹ vừa ghi; không chi vượt số dư hoặc sửa khoản của người khác. Tên nhóm không rõ/trùng phải hỏi lại; mở chia tiền phải đúng nhóm.
- Voice: ngừng khoảng 2,5 giây tự gửi một lần và giữ từ cuối; dừng thủ công giữ chữ để sửa; hủy, không nói hoặc từ chối quyền không tự gửi. Kiểm tra micro thật và tiếng ồn trên web/thiết bị mục tiêu. AI chỉ trả text, không phát giọng nói.
- Xem log `ai-api` nếu gặp `UNKNOWN_ACTION`, thiếu RPC, HTTP 401 hoặc lỗi cấu hình router/model. Chỉ phát hành app mới sau khi backend sẵn sàng cho `assistant_command`.

Có thể chạy bộ đánh giá 29 câu VI/EN bằng `npx deno run --allow-env --allow-net tool/eval_finmi_ai.mjs`. Cung cấp qua môi trường cục bộ: `FINMI_AI_URL` là URL đầy đủ `https://<PROJECT_REF>.supabase.co/functions/v1/ai-api`, `FINMI_AI_ACCESS_TOKEN` là access JWT của người dùng test đang đăng nhập, `FINMI_AI_PUBLISHABLE_KEY` là publishable key. Script chỉ gọi parser, không thực thi thao tác ghi; không commit các giá trị này. Đây là kiểm tra với model thật, có dùng quota/chi phí AI.

## Tài liệu liên quan

- Kiểm chứng trước khi push: 451/451 Flutter tests đạt; `flutter analyze --no-pub` không có lỗi; định dạng 298 file không phát sinh thay đổi; type check cả bốn Edge Function và script eval đạt; 3 guard tests, mô phỏng Web Speech và fixture migration PGlite đều đạt. Chưa kiểm tra model, micro hoặc Supabase/RLS thật trong bước bàn giao này.
- [Chi tiết FinmiAI, voice, guardrails và giới hạn](finmi-ai-voice-20261023.md).
- [Lịch sử tích hợp main và các kiểm chứng trước đó](main-20261023.md).
- [Checklist phát hành production](../PRODUCTION_RELEASE_CHECKLIST.md).

Các ghi chú “chưa push” trong báo cáo cũ mô tả trạng thái ở thời điểm kiểm thử đó. Việc push main không đồng nghĩa đã chạy migration, deploy function hoặc đổi secrets trên Supabase thật.
