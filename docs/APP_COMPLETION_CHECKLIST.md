# Checklist hoàn thiện ứng dụng quản lý thu chi

Checklist này là lộ trình chính để hoàn tất bản phát hành nội bộ Android. Các mục `[x]` chỉ xác nhận trạng thái trong repo hoặc kiểm tra local; chúng **không** chứng minh database, Auth hay Edge Functions trên Supabase hiện đang đúng. Các mục `[ ]` cần được làm và đánh dấu sau khi có bằng chứng kiểm tra.

## Phạm vi đã chốt

- Ứng dụng quản lý thu chi cá nhân, có nhóm và chia sẻ hóa đơn giữa các tài khoản.
- Đăng nhập online lần đầu; sau đó có thể dùng dữ liệu local/offline và đồng bộ khi có mạng, tự thử lại khoảng 15 phút hoặc do người dùng yêu cầu.
- Thêm giao dịch thủ công, OCR hóa đơn từ ảnh, quét QR thanh toán rồi mở app ngân hàng. Người dùng tự xác nhận thành công, hủy hoặc sửa giao dịch; app **không** xác minh giao dịch từ ngân hàng.
- Bản đầu phát hành nội bộ Android; không bao gồm tích hợp cổng thanh toán hay tự kết nối tài khoản ngân hàng. Google OAuth và iOS là tùy chọn/ngoài đợt phát hành đầu.

## A. Hiện trạng đã kiểm chứng trong repo

- [x] Có cổng đăng nhập bắt buộc trước khi vào các màn hình dữ liệu.
- [x] Có lưu local/offline, đồng bộ cloud, đồng bộ thủ công và thử lại theo chu kỳ.
- [x] Có các luồng thu chi, danh mục/ngân sách, OCR ảnh, QR, nhóm/chia sẻ, backup mã hóa và quản lý/xóa dữ liệu tài khoản.
- [x] `config/supabase.local.json` đã có URL + publishable key cho project `mjirsdljxrikuhimbkrn` và được Git bỏ qua.
- [x] Lần kiểm tra cuối: format không cần chỉnh; `flutter analyze` sạch; 231 test qua; Android debug APK và web release build đều thành công với cấu hình Supabase local.
- [x] A1. Review cuối đã hoàn tất; Android debug APK, web release, 231 test và analyzer đều đạt. Đã mở bản web trên Chromium ở viewport 390×844; các kích thước nhỏ/ngang/rộng và dark theme có widget test.

## B. Rà soát và chốt mã nguồn

- [x] B1. Review diff và các file untracked thuộc app/docs/tests/migrations; không thấy file tạm hay dữ liệu thử nghiệm cần loại khỏi release. File thiết kế QR do người dùng cung cấp ở repo root được giữ ngoài danh sách release.
- [ ] B2. Hoàn tất scan secret bằng scanner chuyên dụng trước phát hành. Pattern scan cho Supabase/OpenAI/Google key/JWT trên worktree không bị ignore và Git history không có match; không có `gitleaks` trong môi trường, và file cấu hình local bị gitignore được chủ ý không đọc.
- [x] B3. Đối chiếu giao diện thêm giao dịch: chỉ còn chụp ảnh, thư viện ảnh, QR và nhập tay; test widget xác nhận XML/PDF không hiện trong lựa chọn. Checklist F7 phân biệt giao diện hiện tại với hỗ trợ OCR ảnh và các parser XML/PDF cũ.
- [x] B4. Format không cần chỉnh file; `flutter analyze` sạch; toàn bộ 231 test qua; Android debug APK và web release build thành công.
- [ ] B5. Commit các thay đổi đã duyệt và push lên GitHub. Hiện nhánh `main` có nhiều thay đổi local chưa commit/push.

## C. Supabase: database, quyền và Storage

Project cần đối chiếu: `mjirsdljxrikuhimbkrn`. Đã kiểm tra ngày 2026-09-29: CLI link đúng project; migration list remote mới nhất khớp local đến `20260927090000`; `20260929100000_harden_group_membership_policy.sql` đang pending. `supabase db lint --linked` không có lỗi trên schema remote trước migration khắc phục mới.

- [x] C1. Xác nhận Supabase CLI đang link đúng project `mjirsdljxrikuhimbkrn`; tại thời điểm audit, local/remote khớp tới `20260927090000`. Migration mới được ghi nhận riêng ở C2.
- [ ] C2. Đối chiếu migration: bốn migration trước đó đã có trên remote:
  - `20260918150000_remove_qr_feature_flag.sql`
  - `20260918160000_bill_sharing.sql`
  - `20260920100000_group_expense_lifecycle.sql`
  - `20260927090000_demo_cloud_data_expansion.sql`
  Sau đợt rà soát, đã tạo `20260929100000_harden_group_membership_policy.sql`; CLI xác nhận migration này đang pending trên remote. Review/deploy rồi đối chiếu lại migration list và lint.
- [x] C3. `supabase db lint --linked` ngày 2026-09-29 hoàn tất, không có lỗi schema.
- [ ] C4. Kiểm tra RLS và quyền `authenticated`/`service_role` trên bảng, view, RPC; chú ý quyền đọc/chia sẻ nhóm và quyền thu hồi chia sẻ. Rà soát ngày 2026-09-29: tất cả bảng public bật RLS; không có quyền bảng trực tiếp cho `anon`; các bảng nội bộ không policy chỉ cấp quyền `service_role`; các view quản trị chỉ cấp `service_role`. Đã phát hiện RPC `is_expense_group_member(group_id,user_id)` cho phép dò membership của user tùy ý. Migration khắc phục đã tạo tại `supabase/migrations/20260929100000_harden_group_membership_policy.sql`; cần deploy rồi kiểm tra lại quyền/RLS trước khi đánh dấu hoàn tất.
- [x] C5. Đã xác nhận ngày 2026-09-29: `receipt-images` và `invoice-backups` private; Storage policy chỉ cho `authenticated` thao tác trong prefix `{auth.uid()}/`; ảnh chứng từ dùng signed URL 120 giây, còn backup tải trực tiếp qua phiên đăng nhập và policy private. Kiểm thử end-to-end giữa hai tài khoản vẫn nằm ở F16.
- [ ] C6. Xác nhận các RPC cho sync, nhóm, settlement, direct share, cài đặt hồ sơ và xóa tài khoản khớp với phiên bản app. Đã đối chiếu tên/tham số chính của sync, group CRUD/settlement, direct share và profile với remote; các hàm client cần dùng tồn tại, không cho `anon` execute. Cần recheck sau migration C4; các RPC chia bill hiện nhận `source_snapshot` từ client nên cần giữ kiểm thử provenance/đồng bộ nguồn ở F14.
- [ ] C7. Xác nhận các Edge Functions `ai-api`, `ai-worker`, `delete-account`, `health` đã deploy đúng phiên bản hiện tại. Đối chiếu lại ngày 2026-09-29: cả bốn `ACTIVE` (version lần lượt 8, 2, 4, 5); chưa chứng minh hash/version remote khớp mã nguồn local.
- [ ] C8. Đặt Supabase Secrets: `GEMINI_API_KEY`, `AI_WORKER_SECRET`, `HEALTHCHECK_SECRET`. Đối chiếu ngày 2026-09-29: `GEMINI_API_KEY` đã có; `AI_WORKER_SECRET` và `HEALTHCHECK_SECRET` chưa có. CLI chỉ trả fingerprint, không đọc giá trị secret.
- [ ] C9. Cấu hình `AI_REQUIRE_ORIGIN_ALLOWLIST=true`, `DELETE_ACCOUNT_REQUIRE_ORIGIN_ALLOWLIST=true` và allowlist `AI_ALLOWED_ORIGINS`, `DELETE_ACCOUNT_ALLOWED_ORIGINS` cho domain web thực tế. Các tên cấu hình này chưa có trong danh sách secrets ngày 2026-09-29; native app không gửi Origin như web.
- [ ] C10. Chạy kiểm tra readiness sau khi cấu hình; chỉ chấp nhận trạng thái sẵn sàng khi dependency đủ, không để lộ secret; kiểm tra endpoint cần đăng nhập từ chối request không session bằng HTTP 401. Ngày 2026-09-29: health GET trả 200, readiness chưa có secret trả 503, và `ai-api` không session trả 401; cần chạy lại readiness sau khi đặt secrets/origin allowlist.

## D. Supabase Auth và tài khoản kiểm thử

- [ ] D1. Bật email/password trong Supabase Auth.
- [ ] D2. Cấu hình email xác nhận (nếu bật), password recovery và redirect URL cho web/native.
- [ ] D3. Tạo ít nhất hai tài khoản staging riêng; không dùng tài khoản cá nhân làm dữ liệu thử xóa.
- [ ] D4. Kiểm thử đăng ký, đăng nhập, khởi động lại app/khôi phục session, đăng xuất, đổi mật khẩu và khôi phục mật khẩu.
- [ ] D5. Nếu bật Google OAuth: cấu hình provider, callback/redirect và kiểm thử liên kết/hủy liên kết. Nếu không bật, ghi rõ là ngoài phạm vi.
- [ ] D6. Kiểm thử xóa một tài khoản staging và xác nhận dữ liệu local/cloud/Storage được dọn đúng, không ảnh hưởng tài khoản khác.

## E. GitHub Actions và bản Android nội bộ

- [ ] E1. Tạo GitHub Environment `production`.
- [ ] E2. Thêm signing secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
- [ ] E3. Thêm `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`; chỉ thêm `SUPABASE_OAUTH_REDIRECT_URI` nếu bật OAuth.
- [ ] E4. Thêm GitHub Secrets cho workflow backend: `SUPABASE_FUNCTION_URL`, `AI_WORKER_SECRET`, `HEALTHCHECK_SECRET`.
- [ ] E5. Chạy workflow `Android Release` bằng `workflow_dispatch`; xác nhận tạo được AAB ký bằng keystore release, không dùng debug keystore.
- [ ] E6. Chạy workflow `ai-worker` và `production-health`; xác nhận đều thành công sau khi secrets/deployment đã sẵn sàng.
- [ ] E7. Cài AAB lên thiết bị Android sạch; kiểm tra mở app, đăng nhập và upgrade/version cơ bản.
- [ ] E8. Lưu keystore/password ở nơi an toàn ngoài repo; xác nhận không đưa signing files vào Git.

## F. Kiểm thử nghiệp vụ end-to-end

### Tài khoản, giao dịch và ngân sách

- [ ] F1. Tạo, xem, sửa, lọc và xóa giao dịch; tổng tiền/tháng/danh mục khớp dữ liệu nguồn.
- [ ] F2. Tạo/sửa/xóa danh mục; thử xóa danh mục đang được dùng và xác nhận giao dịch được chuyển sang danh mục thay thế theo thiết kế.
- [ ] F3. Đặt/sửa hạn mức ngân sách; kiểm tra ngưỡng cảnh báo, trạng thái vượt hạn mức và biểu đồ khi tháng có/không có dữ liệu.
- [ ] F4. Xác nhận các chức năng cài đặt hồ sơ, theme, app ngân hàng gần nhất và tùy chọn thông báo vẫn tách đúng theo tài khoản.

### OCR và QR thanh toán

- [ ] F5. Chụp ảnh hóa đơn và chọn ảnh từ thư viện; kiểm tra thông tin OCR, sửa kết quả rồi mới xác nhận lưu.
- [ ] F6. Thử OCR offline, lỗi, retry và mở lại app khi job đang chờ; dữ liệu lỗi phải phục hồi được và không tự tạo giao dịch sai.
- [ ] F7. Xác nhận màn hình thêm giao dịch không hiện XML/PDF; nếu giữ luồng nhập XML cũ để tương thích thì kiểm tra riêng và không đưa nó thành lựa chọn UI ngoài phạm vi.
- [ ] F8. Quét QR hợp lệ/không hợp lệ; kiểm tra người nhận/số tiền đọc được có thể sửa và danh mục có thể chọn. Unit test đã kiểm parser/checksum, nhưng camera cần kiểm trên thiết bị.
- [ ] F9. Kiểm tra chọn app ngân hàng, nhớ lựa chọn gần nhất, mở đúng ứng dụng khi có; xử lý rõ trường hợp không cài app/ngân hàng không hỗ trợ deep link. Đã thêm `ba`, `am`, `tn`, `bn` vào link VietQR khi có mã ngân hàng; chỉ một số app hỗ trợ autofill, nên phải xác nhận trên thiết bị thật.
- [ ] F10. Sau khi quay lại từ ngân hàng, thử xác nhận thành công, hủy và sửa thông tin; không ghi nhận thành công tự động chỉ vì app ngân hàng đã mở.

### Đồng bộ, nhóm và chia sẻ

- [ ] F11. Với hai tài khoản/thiết bị: đăng nhập lần đầu online, tạo dữ liệu offline, bật mạng lại và xác nhận dữ liệu đồng bộ hai chiều.
- [ ] F12. Kiểm tra thao tác sync thủ công, tự thử lại, tombstone/xóa, conflict và retry; không tạo bản ghi trùng hoặc mất dữ liệu.
- [ ] F13. Tạo nhóm, tham gia nhóm, chia đều/chia tùy chỉnh, ghi nhận thanh toán/settlement và chuyển owner.
- [ ] F14. Chia hóa đơn cho nhóm và cho tài khoản khác; thử pending/accept/decline/revoke, người nhận chưa đăng ký và quyền xem chỉ đúng phần snapshot được chia sẻ.
- [ ] F15. Kiểm thử xóa thành viên/owner và xác nhận quy tắc bảo toàn hoặc dọn dữ liệu nhóm đúng nghiệp vụ.

### Tệp, backup, trợ lý và thông báo

- [ ] F16. Tải chứng từ lên/xem/tải xuống; signed URL hết hạn và tài khoản khác không truy cập được.
- [ ] F17. Tạo backup mã hóa; upload, tải xuống, restore, xóa và kiểm tra retention; backup sai mật khẩu/tệp bị sửa phải bị từ chối.
- [ ] F18. Kiểm thử câu hỏi trợ lý local và online; xác nhận dữ liệu hóa đơn chi tiết không gửi ra ngoài nếu câu hỏi không cần.
- [ ] F19. Kiểm tra thông báo ngân sách và deep link; sau đăng xuất không còn thông báo hoặc dữ liệu của phiên trước.

## G. Theo dõi, bảo mật và đóng phát hành

- [ ] G1. Review privacy/security và dependency; pattern scan hiện không có match, nhưng cần chạy SAST/dependency audit bằng scanner chuyên dụng trước đợt phát hành rộng hơn.
- [ ] G2. Đã nối `AppErrorReporter.configure` tới RPC `record_client_error`; unit test xác nhận message/stack redacted. Cần smoke test xác nhận report được ghi trên Supabase mà không có user ID, hóa đơn, token hay secret.
- [ ] G3. Theo dõi `ai_request_slo_daily`, `sync_request_slo_daily`, `client_error_events` và chi phí Gemini trong tuần đầu.
- [ ] G4. Thiết lập cảnh báo lỗi server/fatal, latency p95, quota và chi phí vượt ngưỡng; chỉ bật luồng AI online khi readiness/secrets đã tốt.
- [ ] G5. Ghi lại phiên bản AAB, commit SHA, migration đã áp dụng và kết quả smoke test.
- [ ] G6. Phân phối AAB nội bộ cho nhóm nhỏ; thu nhận lỗi, sửa lỗi nghiêm trọng rồi mới mở rộng người dùng.

## Thứ tự nên làm tiếp

1. Review rồi áp dụng migration `20260929100000_harden_group_membership_policy.sql`; xác nhận migration list/lint và kiểm tra lại C4/C6.
2. D1–D4 — Cấu hình Auth và tạo/kiểm tra hai tài khoản staging.
3. C7–C10 — Đối chiếu đúng phiên bản Edge Functions, bổ sung secrets/origin rồi chạy health readiness.
4. F — Smoke test trên hai tài khoản và thiết bị thật.
5. E — Signing secrets, tạo AAB và cài thử.
6. B — Review cuối, commit/push và ghi nhận release.

Checklist chi tiết triển khai hiện có tại [PRODUCTION_RELEASE_CHECKLIST.md](PRODUCTION_RELEASE_CHECKLIST.md); baseline bảo mật tại [SECURITY.md](SECURITY.md).
