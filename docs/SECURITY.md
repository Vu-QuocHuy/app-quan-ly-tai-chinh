# Security baseline

Quản lý Tài chính xử lý dữ liệu thu chi theo nguyên tắc local-first. XML, PDF và ảnh gốc không được gửi lên backend; khi AI được cấu hình, chỉ text đã trích xuất được gửi qua HTTPS.

## Controls đã triển khai

- Không nhúng Gemini API key trong app. Key chỉ tồn tại trong Supabase Secrets.
- Edge Function yêu cầu Supabase JWT, giới hạn request theo cửa sổ thời gian và không ghi token vào log.
- Backend không log OCR text, merchant, mã số thuế, số hóa đơn hoặc token. Log chỉ chứa request ID và loại lỗi.
- Import giới hạn 15 MB; PDF giới hạn 100 trang; backend giới hạn 50.000 ký tự.
- XML có DTD/entity bị từ chối để giảm bề mặt entity expansion; parser không tải URL từ payload.
- PDF sai magic header, file rỗng, PDF hỏng/khóa và PDF scan không có text đều có lỗi phục hồi rõ ràng.
- Source hash hỗ trợ exact duplicate; fuzzy duplicate không tự động ghi đè dữ liệu.
- Người dùng có thể xóa hóa đơn riêng lẻ ở repository và xóa toàn bộ hóa đơn/ngân sách/quy tắc local từ Settings.
- Cloud backup chỉ nhận envelope `.hdbak` đã mã hóa, dùng bucket private và policy giới hạn thư mục theo `auth.uid()`; mọi thao tác list/download/delete phía app tiếp tục kiểm tra prefix user hiện tại.
- QR provider chưa bật; vì vậy chưa có backend URL fetch và không phát sinh bề mặt SSRF.

## Trước production

- Cấu hình redirect URL/password recovery trong Supabase Auth và kiểm thử email trên môi trường staging.
- Đặt quota/cost alert cho Gemini và theo dõi log Edge Function trước khi mở rộng người dùng.
- Cấu hình release signing riêng; không commit keystore, `.env`, service account hay secret.
- Thay rate limiter in-memory bằng quota phân tán nếu lưu lượng vượt một Edge Function instance.
- Thực hiện dependency audit, SAST và privacy review trước mỗi release.
