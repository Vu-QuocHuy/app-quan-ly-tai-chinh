# Security baseline

Quản lý Tài chính xử lý dữ liệu thu chi theo nguyên tắc offline-first có tài
khoản bắt buộc. Lần đăng nhập đầu cần mạng; sau đó session đã lưu mở đúng cơ sở
dữ liệu local theo user khi offline, còn thao tác cloud được giữ để thử lại.
Không có Supabase config hoặc chưa có phiên đăng nhập thì mọi route dữ liệu đều
bị chặn. XML, PDF và
ảnh được xử lý trên thiết bị theo mặc định. Khi người dùng bật luồng AI online,
OCR text hoặc ảnh được chọn sẽ gửi qua HTTPS tới private Supabase Storage/Edge
Function để trích xuất; dữ liệu này không được ghi vào log và có thời hạn dọn.

## Controls đã triển khai

- Router không cho đi vào dashboard, giao dịch, QR, chat, nhóm hay cài đặt dữ liệu nếu chưa cấu hình Supabase và đăng nhập; màn hình auth là route duy nhất trước đăng nhập.
- Tác vụ nền không mở database hoặc gửi thông báo từ dữ liệu cũ khi Supabase chưa cấu hình hoặc không có session; với session đã lưu, dữ liệu local theo user vẫn có thể dùng offline.
- Không nhúng Gemini API key trong app. Key chỉ tồn tại trong Supabase Secrets.
- Edge Function yêu cầu Supabase JWT, giới hạn request theo cửa sổ thời gian và không ghi token vào log.
- Quota AI được ghi atomically theo user trong PostgreSQL; nếu RPC quota không khả dụng, request bị từ chối thay vì fallback có thể bị bypass.
- AI action dùng cost units có trọng số theo tác vụ với giới hạn ngày/tháng; async submit/retry kiểm tra cùng budget ngay trong RPC và không lưu nội dung request.
- Backend không log OCR text, merchant, mã số thuế, số hóa đơn hoặc token. Log chỉ chứa request ID và loại lỗi.
- Import giới hạn 15 MB; PDF giới hạn 100 trang; backend giới hạn 50.000 ký tự.
- XML có DTD/entity bị từ chối để giảm bề mặt entity expansion; parser không tải URL từ payload.
- PDF sai magic header, file rỗng, PDF hỏng/khóa và PDF scan không có text đều có lỗi phục hồi rõ ràng.
- Source hash hỗ trợ exact duplicate; fuzzy duplicate không tự động ghi đè dữ liệu.
- Khoản chi nhóm kiểm tra membership, giới hạn 100 phần chia và overflow tổng tiền tại RPC server-side.
- Người dùng có thể xóa hóa đơn riêng lẻ ở repository và xóa toàn bộ hóa đơn/ngân sách/quy tắc local từ Settings.
- Khi cloud được cấu hình, Drift dùng database riêng cho từng user và database cô lập
  khi đã đăng xuất; database legacy hiện hữu được gắn cho tài khoản authenticated đầu
  tiên trên thiết bị để không tự động trộn dữ liệu giữa các tài khoản.
- Manifest và file tạm của import cũng nằm trong thư mục scope theo user khi cloud bật;
  thao tác xóa tài khoản dọn cả queue hiện tại và queue legacy.
- Cloud backup chỉ nhận envelope `.hdbak` đã mã hóa, dùng bucket private và policy giới hạn thư mục theo `auth.uid()`; mọi thao tác list/download/delete phía app tiếp tục kiểm tra prefix user hiện tại.
- Cloud sync chỉ ghi dữ liệu dưới `auth.uid()` qua wrapper RPC kiểm tra identity, revision, kích thước payload và nested records; quyền gọi trực tiếp RPC ghi bị thu hồi.
- Chứng từ gốc nằm trong bucket `receipt-images` private, theo prefix user; metadata có SHA-256, MIME/size checks, RLS và chỉ hóa đơn đã tồn tại trên cloud mới nhận file. Link mở file là signed URL ngắn hạn.
- Chat cloud chỉ ghi từng tin nhắn mới sau migration, không backfill lịch sử local cũ; nội dung/citations được giới hạn, RLS theo user và có thể xóa trên cả thiết bị lẫn cloud.
- QR lưu session và event `scanned`, `bank_opened`, `user_confirmed` hoặc `user_cancelled` qua RPC owner-scoped. `user_confirmed` chỉ là lời xác nhận của người dùng, không phải xác minh từ ngân hàng; dữ liệu người nhận/tài khoản QR cũng được lưu trong session riêng tư.
- Theme, cảnh báo ngân sách và app ngân hàng QR gần nhất gắn với hồ sơ tài khoản. Ghi cài đặt chỉ qua RPC hẹp vì hồ sơ đã khóa quyền ghi trực tiếp.
- Input AI thành công được dọn ngay sau xử lý; job lỗi giữ tối đa 7 ngày để replay, job cancel tối đa 1 ngày, và cleanup chỉ xóa đường dẫn DB sau khi Storage xác nhận.
- Edge Function xóa tài khoản duyệt toàn bộ prefix user, gồm cả thư mục Storage lồng nhau, trước khi xóa Auth user.
- Kết quả và metadata của job AI terminal được giữ tối đa 30 ngày rồi worker dọn theo batch, không xóa job khi input path vẫn còn cần cleanup.
- Xóa tài khoản xác minh JWT server-side, dọn các bucket private rồi xóa Auth user để các bảng có khóa ngoại `on delete cascade` được dọn theo.
- `AppErrorReporter` bắt lỗi Flutter/async ở entrypoint; report chỉ chứa loại lỗi, thông điệp đã redact, stack trace đã lọc và timestamp, không chứa user ID, invoice hay token. Provider production phải nối qua `AppErrorReporter.configure`.
- Khi cloud đã bật, report lỗi fatal được ghi vào bảng monitoring private qua RPC server-side, giới hạn 20 report/user/phút và cleanup sau tối đa 30 ngày; user không có quyền đọc report của chính mình qua API.
- Android release không dùng debug keystore: Gradle chỉ nhận keystore từ biến môi trường hoặc `android/key.properties` bị ignore, còn workflow production fail nếu thiếu hoặc sai keystore.

## Trước production

- Cấu hình redirect URL/password recovery trong Supabase Auth và kiểm thử email trên môi trường staging.
- Đặt quota/cost alert cho Gemini và theo dõi log Edge Function trước khi mở rộng người dùng.
- Cấu hình release signing riêng; không commit keystore, `.env`, service account hay secret.
- Thay rate limiter in-memory bằng quota phân tán nếu lưu lượng vượt một Edge Function instance.
- Thực hiện dependency audit, SAST và privacy review trước mỗi release.
