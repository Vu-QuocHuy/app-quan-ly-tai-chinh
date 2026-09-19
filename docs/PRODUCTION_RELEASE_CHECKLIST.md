# Production release checklist

## Current verification

- Project `mjirsdljxrikuhimbkrn`: migrations đã được push đến `20260918140000` và `db lint --linked` không còn lỗi schema.
- `health` đã deploy và trả HTTP 200; readiness fail-closed với `READINESS_NOT_CONFIGURED` cho tới khi đặt đủ secrets, origin allowlist và dependency production.
- `ai-api` và `delete-account` đã smoke-test không có session, cả hai đều trả HTTP 401.

## Supabase

- [x] Link đúng project staging/production bằng `supabase link --project-ref ...`.
- [x] Chạy `supabase db push` và `supabase db lint --linked`.
- [ ] Kiểm tra toàn bộ migration mới trong SQL Editor.
- [ ] Apply và kiểm tra `20260918160000_bill_sharing.sql`: RPC chia sẻ team/direct, RLS snapshot và quyền thu hồi.
- [ ] Kiểm tra RLS, private Storage và quyền `authenticated`/`service_role` trên các bảng và RPC.
- [x] Deploy `ai-api`, `ai-worker`, `delete-account` và `health`.
- [ ] Đặt `GEMINI_API_KEY`, `AI_WORKER_SECRET` và `HEALTHCHECK_SECRET` bằng Supabase Secrets.
- [ ] Đặt `AI_REQUIRE_ORIGIN_ALLOWLIST=true` và `DELETE_ACCOUNT_REQUIRE_ORIGIN_ALLOWLIST=true` ở production.
- [ ] Đặt `AI_ALLOWED_ORIGINS` và `DELETE_ACCOUNT_ALLOWED_ORIGINS` đúng domain web; request native không cần Origin.

## Auth

- [ ] Cấu hình email/password, password recovery và Google OAuth trong Supabase Dashboard.
- [ ] Cấu hình redirect URL cho staging và production, không dùng wildcard production.
- [ ] Test đăng ký, đăng nhập, đổi mật khẩu, khôi phục mật khẩu, link/unlink Google và đăng xuất.
- [ ] Tạo tài khoản staging riêng để test xóa tài khoản; không dùng tài khoản thật.

## Worker and monitoring

- [ ] Tạo GitHub Environment `production` và secrets cho workflow `android-release`: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` và `SUPABASE_OAUTH_REDIRECT_URI`.
- [ ] Chạy `Android Release` bằng `workflow_dispatch`; xác nhận artifact là production AAB đã ký, không dùng debug keystore.
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
- [ ] Đăng nhập hai tài khoản staging trên hai thiết bị và kiểm tra sync, tombstone, conflict.
- [ ] Gửi câu hỏi chatbot local và online; xác nhận dữ liệu invoice-level không bị gửi ra ngoài khi không cần.
- [ ] Kiểm tra notification ngân sách, deep link và không còn notification sau sign-out.
