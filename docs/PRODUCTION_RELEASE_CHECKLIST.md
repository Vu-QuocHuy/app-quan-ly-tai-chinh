# Production release checklist

## Mục tiêu bản phát hành hiện tại

Bản đầu là phát hành nội bộ, không phải dịch vụ tài chính công khai. Tuy vậy,
mọi route dữ liệu vẫn yêu cầu đăng nhập Supabase; lần đăng nhập đầu cần mạng,
còn session đã lưu cho phép làm việc offline và đồng bộ lại khi online. Không
được phát hành APK/AAB chưa cấu hình Supabase vì màn hình đăng nhập sẽ chặn app.

- [x] Cổng auth chặn mọi route dữ liệu khi chưa cấu hình hoặc chưa đăng nhập.
- [x] Đồng bộ foreground lúc khởi động/mở lại và thử lại theo chu kỳ 15 phút.
- [x] Tác vụ nền yêu cầu có session và điều kiện network do hệ điều hành quản lý.
- [ ] Cấu hình Supabase Auth và build internal Android với URL + publishable key.
- [ ] Chạy toàn bộ smoke test bằng ít nhất hai tài khoản kiểm thử.
- [ ] Ký AAB nội bộ, cài trên thiết bị sạch và xác nhận offline → online sync.

## Current verification

- Project `mjirsdljxrikuhimbkrn`: lần ghi nhận gần nhất cho biết migrations đã được push đến `20260918140000` và `db lint --linked` không còn lỗi schema. Chưa xác minh trạng thái remote hiện tại.
- Repo hiện có các migration mới hơn mốc đã xác minh: `20260918150000_remove_qr_feature_flag.sql`, `20260918160000_bill_sharing.sql`, `20260920100000_group_expense_lifecycle.sql` và `20260927090000_demo_cloud_data_expansion.sql`. Cần đối chiếu trạng thái linked project trước khi phát hành; không coi chúng là đã apply.
- Lần kiểm tra được ghi nhận: `health` trả HTTP 200; readiness fail-closed với `READINESS_NOT_CONFIGURED` cho tới khi đặt đủ secrets, origin allowlist và dependency. Chưa chạy lại trong lượt hoàn thiện này.
- Lần smoke test được ghi nhận: `ai-api` và `delete-account` không có session đều trả HTTP 401. Chưa chạy lại trên remote trong lượt này.

## Supabase

- [x] Link đúng project staging/production bằng `supabase link --project-ref ...`.
- [x] Chạy `supabase db push` và `supabase db lint --linked`.
- [ ] So sánh danh sách migration local/remote; review rồi apply các migration mới hơn mốc đã xác minh, sau đó chạy `db lint --linked`.
- [ ] Kiểm tra `20260918160000_bill_sharing.sql`, `20260920100000_group_expense_lifecycle.sql` và `20260927090000_demo_cloud_data_expansion.sql`: RPC, RLS, snapshot và quyền thu hồi.
- [ ] Kiểm tra RLS, private Storage và quyền `authenticated`/`service_role` trên các bảng và RPC.
- [x] Deploy `ai-api`, `ai-worker`, `delete-account` và `health`.
- [ ] Đặt `GEMINI_API_KEY`, `AI_WORKER_SECRET` và `HEALTHCHECK_SECRET` bằng Supabase Secrets.
- [ ] Đặt `AI_REQUIRE_ORIGIN_ALLOWLIST=true` và `DELETE_ACCOUNT_REQUIRE_ORIGIN_ALLOWLIST=true` ở production.
- [ ] Đặt `AI_ALLOWED_ORIGINS` và `DELETE_ACCOUNT_ALLOWED_ORIGINS` đúng domain web; request native không cần Origin.

## Auth

- [ ] Cấu hình email/password, password recovery và redirect URL trong Supabase Dashboard; Google OAuth là tùy chọn cho bản nội bộ.
- [ ] Test đăng ký, đăng nhập, đổi mật khẩu, khôi phục mật khẩu, link/unlink Google và đăng xuất.
- [ ] Tạo tài khoản kiểm thử riêng để test xóa tài khoản; không dùng tài khoản cá nhân.

## Worker and monitoring

- [ ] Tạo GitHub Environment `production` và secrets cho workflow `android-release`: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `SUPABASE_URL` và `SUPABASE_PUBLISHABLE_KEY`; `SUPABASE_OAUTH_REDIRECT_URI` chỉ cần nếu bật OAuth.
- [ ] Chạy `Android Release` bằng `workflow_dispatch`; xác nhận artifact là AAB đã ký để phân phối nội bộ, không dùng debug keystore.
- [ ] Tạo GitHub Secrets `SUPABASE_FUNCTION_URL`, `AI_WORKER_SECRET` và `HEALTHCHECK_SECRET`.
- [ ] Chạy workflow `ai-worker` và `production-health` thành công sau khi deploy.
- [ ] Kiểm tra readiness trả đủ dependency mà không lộ secret hoặc response body nhạy cảm.
- [ ] Theo dõi `ai_request_slo_daily`, `sync_request_slo_daily` và chi phí Gemini trong tuần đầu.
- [ ] Theo dõi `client_error_events` cùng AI/sync SLO; báo động khi lỗi fatal hoặc tỷ lệ lỗi tăng bất thường.
- [ ] Thiết lập cảnh báo khi lỗi server, latency p95, quota hoặc cost vượt ngưỡng.
- [ ] Kết nối provider crash monitoring vào `AppErrorReporter.configure`; sink chỉ nhận report đã redact trước khi bật production rollout.

## Smoke test

- [ ] Import XML cũ và hai schema variant, kiểm tra seller/date/total/items rồi xác nhận review.
- [ ] Import ảnh OCR offline trên Android/iOS; kiểm tra job lỗi, retry và process restart.
- [ ] Tạo backup mã hóa, upload/download/restore/delete và kiểm tra retention.
- [ ] Tạo nhóm, chia đều/chia tùy chỉnh, settle, chuyển owner rồi xóa tài khoản owner.
- [ ] Tạo chia sẻ hóa đơn vào team; kiểm tra thành viên chỉ thấy snapshot đã chia sẻ và phần chia khớp tổng tiền.
- [ ] Gửi direct share tới tài khoản staging khác; kiểm tra pending/accept/decline/revoke và email chưa đăng ký.
- [ ] Đăng nhập hai tài khoản kiểm thử trên hai thiết bị và kiểm tra sync, tombstone, conflict.
- [ ] Gửi câu hỏi chatbot local và online; xác nhận dữ liệu invoice-level không bị gửi ra ngoài khi không cần.
- [ ] Kiểm tra notification ngân sách, deep link và không còn notification sau sign-out.
