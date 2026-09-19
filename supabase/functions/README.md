# Supabase Edge Functions

`ai-api` là backend AI tối giản của Quản lý Tài chính. Function nhận các action:

- `chat`: trả lời câu hỏi dựa trên facts local và tỷ giá bên ngoài khi cần.
- `extract`: chuyển OCR text thành hóa đơn có cấu trúc.
- `classify`: phân loại merchant bằng bộ rule nhẹ, không tốn lượt Gemini.
- `extract_submit`, `extract_status`, `extract_cancel`, `extract_retry`: quản lý job trích xuất bất đồng bộ.

`delete-account` xác minh JWT, xóa các tệp theo thư mục user trong các bucket
private rồi xóa tài khoản Auth bằng `SUPABASE_SERVICE_ROLE_KEY` của môi trường
Edge Function. Secret này không được đưa vào app hoặc Git.

`ai-worker` là worker nội bộ cho hàng đợi trích xuất bất đồng bộ. Worker không
dùng JWT của người dùng; endpoint chỉ nhận `X-Worker-Secret` và phải được gọi
bởi scheduler/worker server tin cậy. Worker dùng service role để claim job
atomically, retry tối đa 3 lần, chuyển lỗi cuối vào trạng thái `failed`; input
thành công bị xóa ngay, input lỗi giữ tối đa 7 ngày để replay trước khi bị dọn,
input cancel giữ tối đa 1 ngày để cleanup orphan rồi được dọn tự động. Job hết
hạn không thể retry.
Cleanup chỉ xóa đường dẫn input khỏi DB sau khi Storage xác nhận đã xóa hoặc
object không còn tồn tại; lỗi mạng sẽ được thử lại ở lần cleanup kế tiếp.
Worker cũng dọn metrics AI quá 30 ngày theo từng batch để giới hạn dữ liệu vận
hành lưu trữ lâu dài.
Kết quả và metadata của job terminal cũng được worker dọn sau 30 ngày theo batch
tối đa 500 bản; job chỉ được xóa sau khi input path đã được cleanup thành công.

`health` là endpoint GET/HEAD công khai, chỉ trả trạng thái sống tối giản và
không kiểm tra hay tiết lộ secret. Khi đặt `HEALTHCHECK_SECRET` tối thiểu 32 ký
tự, thêm `?check=readiness` cùng header `X-Health-Secret` để kiểm tra migration
metrics, bucket `ai-inputs`, Gemini key, worker secret và Supabase anon key;
readiness cũng kiểm tra bảng job AI, sync metrics, feature flags, cost budget/usage,
ba private Storage bucket và telemetry lỗi client; readiness production bắt buộc
bật origin allowlist cho AI và xóa tài khoản kèm danh sách origin không rỗng.
Readiness không trả secret. Workflow production luôn gọi readiness và sẽ fail
nếu GitHub Secret này chưa được cấu hình.
Workflow `.github/workflows/production-health.yml` dùng endpoint này làm smoke
check production định kỳ sau khi cấu hình `SUPABASE_FUNCTION_URL`.

Chat chỉ nhận facts tổng hợp đã whitelist. Facts chứa merchant, invoice ID, dòng
hóa đơn, kết quả tìm kiếm hoặc danh mục tùy chỉnh sẽ bị loại bỏ tại Edge Function;
lịch sử chỉ giữ tối đa 4 câu hỏi gần nhất và ẩn email, số điện thoại, mã số dài.
Các truy vấn dữ liệu local được trả lời ở thiết bị và không gọi function.

## Deploy

Không ghi API key vào file hoặc Git:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase secrets set GEMINI_API_KEY=your_gemini_key
supabase secrets set AI_WORKER_SECRET=at-least-32-random-characters
supabase secrets set HEALTHCHECK_SECRET=another-at-least-32-random-characters
supabase functions deploy ai-api
supabase functions deploy delete-account
supabase functions deploy ai-worker
supabase functions deploy health
```

Đặt `DELETE_ACCOUNT_ALLOWED_ORIGINS` thành danh sách origin web production phân
tách bằng dấu phẩy để khóa CORS riêng cho endpoint xóa tài khoản. Khi bỏ trống,
mobile và môi trường local vẫn được phép như mặc định. Khi production đã có
allowlist, đặt thêm `DELETE_ACCOUNT_REQUIRE_ORIGIN_ALLOWLIST=true`; native request
không có `Origin` vẫn được phép, còn browser origin không nằm trong allowlist sẽ
bị từ chối.

`verify_jwt = true` được khai báo trong `supabase/config.toml`, vì vậy app phải
đăng nhập Supabase mới gọi được AI online và mở các route dữ liệu khi cloud đã
cấu hình. Bản build không có cloud vẫn giữ OCR ML Kit, SQLite và chatbot local
theo chế độ local-first.

Giới hạn mặc định là 30 yêu cầu AI mỗi user mỗi phút. Sau khi deploy migration,
quota được ghi atomically trong bảng Supabase và có thể thay đổi bằng Secret
`AI_MAX_REQUESTS_PER_MINUTE` với giá trị từ 1 đến 120 và
`AI_MAX_REQUESTS_PER_DAY` với giá trị từ 1 đến 5000. Nếu môi trường local
chưa có bảng quota hoặc RPC tương ứng, AI request sẽ bị từ chối an toàn; cần
deploy đầy đủ migration trước khi đưa lên production.
`AI_MAX_BODY_BYTES` giới hạn tổng JSON request (mặc định 16 MB, tối đa 25 MB),
còn `AI_ALLOWED_ORIGINS` nhận danh sách origin web phân tách bằng dấu phẩy để
khóa CORS theo domain production. Đặt `AI_REQUIRE_ORIGIN_ALLOWLIST=true` ở
production để fail-closed nếu allowlist bị bỏ quên; request mobile không có
`Origin` vẫn được phép.
Job `extract_submit` cũng tiêu thụ quota atomically trong database, nên không thể
né giới hạn bằng cách gọi RPC trực tiếp thay vì đi qua Edge Function.
Retry job cũng tiêu thụ quota ngay trong RPC và giữ giới hạn riêng mặc định 30
lượt/phút, 500 lượt/ngày.
Các action online dùng thêm cost units để phản ánh chi phí tương đối:
`classify=1`, `chat=2`, `extract=5`. Mặc định mỗi user được tối đa 1.000
units/ngày và 10.000 units/tháng; có thể đổi mặc định bằng
giá trị server-side trong migration, hoặc override riêng user bằng quyền
quản trị trong bảng private `ai_cost_budgets`. Async submit/retry áp dụng
cost budget ngay trong RPC để không thể bypass bằng gọi RPC trực tiếp.
Các Edge Function log chỉ ghi action, mã lỗi, trạng thái và thời gian xử lý;
không ghi câu hỏi, token, ảnh hoặc dữ liệu hóa đơn.

Sau khi deploy migration `20260917110000_ai_request_metrics.sql`, `ai-api` ghi
best-effort các metric `action`, `status_code`, `duration_ms`, model và mã lỗi
vào bảng private `ai_request_metrics`. Bảng chỉ cho Edge Function ghi qua RPC,
RLS không cho client đọc trực tiếp và dữ liệu cũ hơn 30 ngày được dọn định kỳ
qua worker theo từng batch giới hạn. Có thể dùng Supabase Dashboard/SQL Editor với quyền quản trị để
theo dõi p95 latency, tỷ lệ lỗi và phân bổ action; nội dung prompt, OCR, ảnh và
response không được lưu.

View `ai_request_metrics_hourly` chỉ tổng hợp số request, lỗi và p95 theo giờ;
view này cũng không cấp quyền cho client.
View `ai_request_slo_daily` tổng hợp theo ngày và action, gồm số request, lỗi
server, tỷ lệ lỗi và p95 latency; view chỉ dành cho `service_role` để theo dõi
SLO mà không lộ dữ liệu từng người dùng.

View `ai_cost_usage_summary` chỉ tổng hợp số user hoạt động và cost units theo
ngày/tháng, không chứa user ID và chỉ cấp cho `service_role`.

View `sync_request_slo_daily` tổng hợp push/pull theo aggregate, còn bảng
`sync_request_metrics` chỉ giữ trạng thái, latency và batch size. Cả bảng và
view đều private; worker dọn metrics sync sau 30 ngày và cost usage sau 400 ngày.
Input AI hết hạn được chọn tối đa 20 bản mỗi lượt để tránh worker bị quá thời
gian khi backlog tăng; các bản còn lại sẽ được xử lý ở lượt scheduler tiếp theo.

Migration `20260918090000_client_error_monitoring.sql` nhận report lỗi fatal đã
redact từ app qua RPC `record_client_error`; migration `20260918130000` lặp lại
redaction ở server trước khi lưu. Report không chứa user ID, prompt, invoice hay
token; client không có quyền đọc bảng `client_error_events`, mỗi user
bị giới hạn 20 report/phút và worker dọn report quá 30 ngày. Dashboard vận hành
có thể đọc view `client_error_events_daily` bằng `service_role` để đặt cảnh báo
lỗi crash mà không cần truy cập event theo user.

Tỷ giá được cache trong memory của từng Edge Function instance theo cặp tiền;
TTL mặc định 5 phút, cấu hình qua `EXTERNAL_RATES_CACHE_TTL_SECONDS` trong
khoảng 30–3.600 giây. Function thử ExchangeRate-API trước và Frankfurter cho
các cặp tiền được hỗ trợ khi nguồn chính lỗi. Cache chỉ chứa tỷ giá/citation
public, không chứa câu hỏi.

Feature flags nằm trong bảng `app_feature_flags`, chỉ cho role `authenticated`
đọc và được cache trên thiết bị tối đa 24 giờ. Các key hiện có là
`online_ai`, `cloud_sync`, `external_rates`; rollout được tính ổn
định theo user ID. Khi bảng chưa được deploy hoặc mạng lỗi, ứng dụng dùng cấu
hình mặc định và vẫn giữ luồng offline.

RPC tham gia nhóm giới hạn 10 lần thử mỗi user trong một phút; bảng rate limit
không cho client đọc. Các group security-definer function dùng `search_path`
cố định để tránh shadowing object khi chạy quyền cao.
RPC tạo khoản chi nhóm giới hạn 100 thành viên/phần chia và kiểm tra kiểu JSON,
UUID, tổng tiền cùng overflow ngay trên server; giới hạn này không phụ thuộc
validation ở Flutter.

Sau migration `20260917130000_sync_write_guard.sql`, role `authenticated` chỉ
đọc các bảng dữ liệu đồng bộ; mọi ghi cloud phải đi qua RPC đã kiểm tra user,
revision và outbox. Các constraint giới hạn độ dài, số tiền và số lượng tag giúp
chặn payload bất thường ngay tại PostgreSQL.

Migration `20260917290000_sync_identity_guard.sql` thêm wrapper kiểm tra
`expected_user_id` ngay trong cùng request với RPC ghi dữ liệu. Gateway Flutter
dùng wrapper này để từ chối request nếu phiên đăng nhập đổi giữa lúc bắt đầu và
kết thúc sync.

Migration `20260918040000_sync_rpc_payload_hardening.sql` buộc wrapper chạy với
quyền server, giới hạn kích thước payload và số lượng line/evidence/tag, kiểm tra
kiểu nested record rồi thu hồi quyền gọi trực tiếp RPC ghi dữ liệu. Client chỉ
được gọi wrapper đã kiểm tra.

Migration `20260918000000_sync_request_metrics.sql` ghi metric sync tối giản gồm
hướng push/pull, loại aggregate, trạng thái, thời gian và kích thước batch. Metric
không chứa payload hoặc dữ liệu hóa đơn, chỉ ghi qua RPC theo phiên hiện tại và
được worker dọn sau 30 ngày. View `sync_request_slo_daily` chỉ cấp cho
`service_role` để theo dõi lỗi và p95 theo ngày.

Migration `20260917170000_server_owned_sync_timestamp.sql` dùng thời gian server
cho `invoices.updated_at`, tránh đồng hồ thiết bị lệch làm mất delta khi pull.

Khi một thành viên xóa tài khoản, phần chia của họ trong nhóm được giữ lại với
nhãn `Tài khoản đã xóa` thay vì xóa số tiền khỏi khoản chi; dữ liệu nhận diện
tài khoản vẫn bị xóa theo khóa ngoại. Nếu họ từng là người trả một khoản chi,
khoản chi vẫn giữ nguyên nhưng `payer_id` được đặt rỗng để không chặn xóa
tài khoản.

Nếu tài khoản là chủ nhóm, migration `20260917150000_group_owner_deletion_safety.sql`
tự chuyển quyền cho thành viên tham gia sớm nhất để không xóa dữ liệu chung của
cả nhóm. Nhóm không còn thành viên sẽ được xóa cùng dữ liệu của nhóm đó.

## Local smoke test

```bash
supabase functions serve ai-api --no-verify-jwt
```

Lệnh local cần Docker theo yêu cầu của Supabase CLI. Khi test local, đặt
`GEMINI_API_KEY` trong môi trường chạy function; không commit `.env`.
