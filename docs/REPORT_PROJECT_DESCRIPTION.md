# Nội dung dự án để hoàn thiện báo cáo

Tài liệu này diễn giải dự án theo các mục trong file “BÁO CÁO LẬP TRÌNH ANDROID NÂNG CAO.docx”. Đây là tài liệu nền để nhóm viết và kiểm chứng báo cáo; nó không thay cho kết quả chạy thử, số liệu OCR hoặc ảnh chụp từ bản app cuối.

## 1. Thông tin đề tài và phạm vi

### Tên đề tài gợi ý

**Xây dựng ứng dụng quản lý chi tiêu cá nhân trên Android, hỗ trợ trích xuất thông tin hóa đơn bằng mô hình thị giác ngôn ngữ.**

Tên ứng dụng hiển thị là **Quản lý Tài chính**; tên package là hoadon_insight.

### Mô tả ngắn có thể dùng ở phần mở đầu

Ứng dụng Quản lý Tài chính hỗ trợ người dùng ghi lại và theo dõi chi tiêu cá nhân trên điện thoại Android. Người dùng có thể nhập khoản chi thủ công, chụp hoặc chọn ảnh hóa đơn để hệ thống dùng mô hình thị giác ngôn ngữ trích xuất dữ liệu, rồi kiểm tra và sửa kết quả trước khi lưu. Ứng dụng lưu dữ liệu trên thiết bị bằng SQLite, hỗ trợ quản lý danh mục và ngân sách, xem biểu đồ chi tiêu, quét mã VietQR để chuẩn bị thanh toán và xác nhận thủ công, đồng thời đồng bộ dữ liệu với Supabase khi tài khoản và kết nối mạng sẵn sàng.

### Phạm vi nên tuyên bố

- Sản phẩm tập trung vào quản lý chi tiêu, hóa đơn, danh mục, ngân sách và lịch sử thanh toán QR.
- Ứng dụng Android được xây dựng bằng Flutter; mã Android native chủ yếu là phần host để chạy Flutter.
- Ảnh hóa đơn được gửi tới dịch vụ AI qua Supabase Edge Function. Luồng ảnh hiện tại cần Internet; OCR không chạy hoàn toàn trên thiết bị.
- Kết quả AI chỉ là bản nháp. Người dùng xem lại, chỉnh sửa và xác nhận trước khi lưu.
- Thanh toán QR không được ngân hàng xác nhận tự động. Ứng dụng đọc thông tin VietQR; người dùng tự mở app ngân hàng và xác nhận kết quả.
- Đăng nhập Supabase là cổng vào ứng dụng. Sau khi tài khoản/phiên đã được thiết lập, một số thao tác như nhập khoản chi thủ công có thể dùng với dữ liệu local khi mất mạng; OCR ảnh và đồng bộ cloud cần mạng.

## 2. Lời nói đầu

### Các ý nên trình bày

1. Nhu cầu ghi chép các khoản chi và xem lại theo ngày, tháng, danh mục.
2. Bất tiện của việc nhập lại từng trường trên hóa đơn giấy.
3. Mục tiêu xây dựng ứng dụng Android có nhập thủ công và hỗ trợ AI đọc hóa đơn.
4. Phạm vi: quản lý hóa đơn/khoản chi, danh mục, ngân sách, thống kê, QR và đồng bộ tài khoản.
5. Cách thực hiện: phân tích yêu cầu, thiết kế dữ liệu/luồng, triển khai Flutter và backend Supabase, kiểm thử chức năng.
6. Bố cục báo cáo: tổng quan, phân tích thiết kế, triển khai và kết luận.

### Đoạn nháp để nhóm biên tập

Trong quá trình chi tiêu hằng ngày, người dùng thường phải ghi nhớ hoặc nhập lại nhiều khoản mua sắm để biết tiền đã được sử dụng vào đâu. Hóa đơn có nhiều cách trình bày khác nhau, khiến việc nhập tay tên cửa hàng, ngày, số tiền và từng mặt hàng mất thời gian. Đề tài xây dựng ứng dụng Quản lý Tài chính trên Android nhằm hỗ trợ ghi lại khoản chi, tổ chức giao dịch theo danh mục và ngân sách, đồng thời sử dụng mô hình thị giác ngôn ngữ để đề xuất dữ liệu từ ảnh hóa đơn. Do kết quả nhận dạng có thể sai, ứng dụng hiển thị màn hình kiểm tra để người dùng sửa trước khi xác nhận lưu.

Nhóm cần bổ sung thời gian thực hiện, cách phân công, môi trường thử nghiệm và mục tiêu cụ thể theo yêu cầu giảng viên.

## 3. Chương 1 — Tổng quan đề tài

### 1.1. Đặt vấn đề

#### Nội dung cần làm rõ

- Ghi chép chi tiêu thủ công dễ bị quên, thiếu thông tin và khó tổng hợp theo tháng.
- Người dùng cần xem được cả tổng chi lẫn từng giao dịch để truy lại cửa hàng, ngày, danh mục và mặt hàng.
- Hóa đơn giấy có nhiều mẫu; cách cố định theo tọa độ hoặc một mẫu hóa đơn khó áp dụng cho nhiều cửa hàng.
- VLM có thể đọc trực tiếp ảnh và trả về dữ liệu có cấu trúc, nhưng có thể đọc sai hoặc bỏ sót trường. Vì vậy ứng dụng cần bước kiểm tra của người dùng.
- Hệ thống dùng lưu trữ local cho dữ liệu đã lưu, và dùng Supabase để xác thực, đồng bộ cloud và làm cổng gọi dịch vụ AI.

#### Mục tiêu đề tài

- Xây dựng ứng dụng Android quản lý khoản chi và hóa đơn.
- Hỗ trợ tạo khoản chi thủ công khi không có hóa đơn.
- Hỗ trợ trích xuất trường chính và mặt hàng từ ảnh, sau đó cho người dùng rà soát.
- Hỗ trợ danh mục, ngân sách, lịch sử, biểu đồ và xác nhận thanh toán QR.
- Lưu dữ liệu local và đồng bộ theo tài khoản khi có dịch vụ cloud.

#### Phạm vi và đối tượng

Đối tượng sử dụng là cá nhân muốn ghi lại khoản chi và theo dõi ngân sách. Bản demo tập trung vào luồng chi tiêu cá nhân; một số chức năng nhóm/chia sẻ có trong mã nguồn nhưng chỉ đưa vào phạm vi báo cáo nếu đã kiểm thử và sẽ trình bày trong phần demo.

### 1.2. Xác định yêu cầu ứng dụng

#### 1.2.1. Yêu cầu chức năng

| Mã | Yêu cầu | Cách ứng dụng đáp ứng | Minh chứng nên có |
| --- | --- | --- | --- |
| FR-01 | Đăng ký/đăng nhập và quản lý phiên | Supabase Auth; kiểm tra trạng thái cấu hình và phiên trước khi vào phần chính | Đăng nhập, đăng xuất, trạng thái cấu hình |
| FR-02 | Ghi khoản chi không có hóa đơn | Tạo giao dịch thủ công với số tiền, ngày, danh mục và thông tin tùy chọn | Màn hình thêm và chi tiết khoản chi |
| FR-03 | Nhập ảnh hóa đơn | Chụp hoặc chọn ảnh; gửi tới Edge Function để gọi VLM và nhận JSON | Chọn ảnh, trạng thái xử lý, kết quả OCR |
| FR-04 | Kiểm tra/sửa dữ liệu trích xuất | Màn hình review cho sửa thông tin hóa đơn và dòng hàng trước khi lưu | Màn hình review trước/sau khi sửa |
| FR-05 | Quản lý hóa đơn | Lưu người bán, ngày, tiền hàng, thuế tổng, giảm giá tổng, tổng tiền, danh mục và dòng hàng | Danh sách và chi tiết hóa đơn |
| FR-06 | Quản lý danh mục | Xem/chỉnh sửa danh mục dùng để tổ chức giao dịch và ngân sách | Màn hình danh mục |
| FR-07 | Xem tổng quan chi tiêu | Xem tổng tháng, số giao dịch, so sánh, biểu đồ theo ngày và cơ cấu theo danh mục | Dashboard có dữ liệu thử |
| FR-08 | Quản lý ngân sách | Tạo ngân sách theo tháng/danh mục và xem đã chi, giới hạn, còn lại/vượt mức | Màn hình ngân sách |
| FR-09 | Quét mã VietQR | Phân tích ngân hàng, tài khoản, người nhận, nội dung và số tiền nếu QR có trường đó | Scanner và thông tin đã phân tích |
| FR-10 | Ghi lịch sử QR | Chỉ lưu là đã thanh toán sau khi người dùng tự xác nhận | Màn hình xác nhận và lịch sử |
| FR-11 | Đồng bộ dữ liệu | Outbox đẩy thay đổi local lên; tải dữ liệu cloud khi tài khoản/mạng sẵn sàng; có quản lý xung đột | Trạng thái đồng bộ/xung đột |
| FR-12 | Nhóm, chia sẻ, sao lưu, trợ lý | Có một số chức năng bổ sung trong mã nguồn | Chỉ đưa vào yêu cầu chính nếu đã kiểm thử và demo được |

#### 1.2.2. Yêu cầu phi chức năng

| Nhóm | Nội dung nên mô tả | Giới hạn cần ghi |
| --- | --- | --- |
| Bảo mật | Phiên đăng nhập; dữ liệu cloud gắn với người dùng; RLS; API key AI đặt ở backend | Xác minh cấu hình môi trường demo; không đưa secret vào báo cáo |
| Sử dụng khi offline | Dữ liệu local và nhập thủ công có thể hoạt động khi mạng gián đoạn trong điều kiện tài khoản/phiên đã thiết lập | OCR ảnh, đăng nhập lần đầu và đồng bộ cần mạng |
| Độ tin cậy dữ liệu | Kiểm tra cấu trúc và quy tắc dữ liệu, phát hiện trùng, yêu cầu xác nhận trước khi lưu | AI không bảo đảm đúng tuyệt đối; người dùng cần rà soát |
| Nhất quán | Tiền lưu dạng số nguyên theo đơn vị nhỏ nhất; revision/outbox phục vụ sync | Mô tả đúng phạm vi dữ liệu thực sự đồng bộ |
| Hiệu năng | Truy vấn local, danh sách có phân trang, giới hạn kích thước file ảnh | Chỉ đưa số đo hiệu năng nếu nhóm đã đo |
| Bảo trì | Thư mục chia theo feature và vai trò presentation/domain/data; schema có migration | Mô tả cấu trúc hiện tại, không gọi là một kiến trúc chuẩn cụ thể nếu chưa chứng minh |

### 1.3. Công nghệ sử dụng

| Công nghệ | Vai trò | Nơi đối chiếu trong repo |
| --- | --- | --- |
| Flutter, Dart | Giao diện và logic app; trọng tâm báo cáo là Android | pubspec.yaml, lib/, android/ |
| Material 3 | Thành phần UI, màu và chủ đề | lib/app/theme/ |
| Riverpod | Quản lý trạng thái và cung cấp dữ liệu cho giao diện | lib/core/providers/ và providers theo feature |
| GoRouter | Điều hướng và kiểm soát cổng đăng nhập | lib/app/router/app_router.dart |
| Drift + SQLite | Cơ sở dữ liệu quan hệ local và migration | lib/core/database/app_database.dart |
| Supabase Auth | Tài khoản và phiên đăng nhập | lib/core/security/ và lib/features/auth/ |
| Supabase PostgreSQL + RLS | Lưu cloud và giới hạn truy cập | supabase/migrations/ |
| Supabase Edge Functions | Backend trung gian cho AI và API cần xử lý phía server | supabase/functions/ |
| Groq hoặc Gemini VLM | Phân tích ảnh hóa đơn theo cấu hình backend | supabase/functions/ai-api/index.ts và secrets của môi trường |
| fl_chart | Biểu đồ tổng quan | pubspec.yaml, lib/features/dashboard/ |
| mobile_scanner | Đọc QR từ camera | pubspec.yaml, lib/features/payments/ |

**Lưu ý:** ứng dụng được viết bằng Flutter/Dart. MainActivity.kt là host Android để chạy Flutter; dự án không triển khai backend bằng Spring Boot. Không nên mô tả Kotlin là ngôn ngữ chính hoặc Spring Boot là backend. Có thể giữ tài liệu Android Developers cho phần nền tảng Android; thay tài liệu Kotlin/Spring Boot bằng Flutter, Dart, Supabase, Drift và tài liệu VLM thực tế.

## 4. Chương 2 — Phân tích và thiết kế hệ thống

### 2.1. Biểu đồ Use Case

#### 2.1.1. Use Case tổng quát

Tác nhân chính là **Người dùng**. Các hệ thống ngoài có tương tác gồm Supabase (Auth, Database, Storage, Edge Functions), nhà cung cấp VLM và ứng dụng ngân hàng người dùng tự mở.

Các nhóm use case:

- Tài khoản: đăng ký, đăng nhập, đăng xuất và quản lý tài khoản.
- Giao dịch: thêm khoản chi, xem danh sách, lọc, xem chi tiết, sửa và xóa.
- OCR: gửi ảnh, nhận đề xuất, kiểm tra/sửa và xác nhận lưu.
- Phân tích: xem tổng quan, biểu đồ và chi tiêu theo danh mục.
- Ngân sách: tạo/sửa ngân sách tháng theo danh mục, theo dõi số đã dùng.
- QR: quét VietQR, xem dữ liệu, mở app ngân hàng, tự xác nhận và xem lịch sử.
- Đồng bộ: đồng bộ dữ liệu và xử lý xung đột.
- Tính năng bổ sung: nhóm, chia sẻ hóa đơn, trợ lý, xuất/khôi phục dữ liệu nếu thuộc phạm vi demo.

Sơ đồ tổng quát nên đặt Người dùng ở trung tâm; các use case bên trong ranh giới ứng dụng; Supabase/VLM/ngân hàng nằm ngoài ranh giới là hệ thống phụ trợ.

#### 2.1.2. Phân rã use case trọng tâm

**Trích xuất hóa đơn từ ảnh**

- Tiền điều kiện: người dùng đã vào ứng dụng; dịch vụ AI và mạng khả dụng.
- Luồng chính: chụp/chọn ảnh → app kiểm tra file → gọi Edge Function → backend gọi VLM → kiểm tra cấu trúc và danh mục → app mở màn hình review → người dùng sửa nếu cần → xác nhận → lưu giao dịch.
- Luồng thay thế: thiếu cấu hình, mất mạng hoặc API lỗi thì app báo lỗi, không tạo giao dịch đã xác nhận; người dùng có thể nhập thủ công.
- Hậu điều kiện: giao dịch được lưu local và đưa vào hàng đợi đồng bộ khi cloud sẵn sàng.

**Thêm khoản chi thủ công**

- Người dùng nhập số tiền, ngày, danh mục và thông tin tùy chọn.
- App kiểm tra dữ liệu bắt buộc và lưu trên thiết bị.
- Giao dịch được đồng bộ khi có mạng và phiên đăng nhập hợp lệ.

**Thanh toán qua QR**

- Người dùng quét VietQR; app đọc người nhận, ngân hàng và số tiền/nội dung nếu mã cung cấp.
- Người dùng kiểm tra rồi tự mở app ngân hàng để chuyển khoản.
- Khi quay lại, người dùng chọn đã thanh toán, chưa thanh toán hoặc chỉnh sửa thông tin.
- Chỉ lựa chọn “đã thanh toán” mới tạo bản ghi lịch sử QR đã xác nhận. App không đọc trạng thái giao dịch từ ngân hàng.

### 2.2. Biểu đồ tuần tự

Nên vẽ ba biểu đồ cho đăng nhập, OCR và đồng bộ. Với luồng OCR, dùng các đối tượng: Người dùng, Flutter app, Supabase Edge Function, VLM, Drift/SQLite và Supabase Database.

Trình tự OCR:

1. Người dùng chụp/chọn ảnh.
2. App kiểm tra kích thước và kiểu ảnh.
3. App gửi ảnh kèm phiên xác thực tới Edge Function.
4. Backend kiểm tra request, hạn mức và dữ liệu đầu vào.
5. Backend gửi ảnh/prompt tới VLM; VLM trả JSON.
6. Backend kiểm tra và chuẩn hóa cấu trúc/danh mục.
7. App hiển thị kết quả ở màn hình kiểm tra.
8. Người dùng sửa nếu cần và xác nhận.
9. App lưu hóa đơn/dòng hàng local và ghi sự kiện vào outbox.
10. Khi có mạng, app đồng bộ lên Supabase; kết quả có thể thành công hoặc cần xử lý xung đột.

Luồng ảnh chính trong ImportCoordinator gửi ảnh trực tiếp tới AI; không có bước ML Kit bắt buộc chạy trước. PDF text và XML có parser trong source, nhưng giao diện thêm giao dịch hiện tập trung vào chụp ảnh, chọn ảnh, QR và nhập thủ công. Chỉ mô tả PDF/XML là tính năng người dùng nếu nhóm xác nhận đường vào còn bật trong bản demo.

Với luồng đồng bộ, thể hiện: thay đổi local → outbox → SyncEngine đẩy theo lô → tải thay đổi cloud theo cursor → áp dụng vào local → cập nhật trạng thái/xung đột.

Với luồng QR, thể hiện bộ phân tích VietQR và app ngân hàng, rồi nhấn rõ bước người dùng quay lại xác nhận. Không vẽ ngân hàng gửi trạng thái thanh toán về app.

### 2.3. Thiết kế cơ sở dữ liệu

#### 2.3.1. Sơ đồ kết nối các bảng

Schema local trong lib/core/database/app_database.dart có các bảng chính:

- Categories, Invoices, InvoiceLines, FieldEvidences
- MerchantRules, Budgets
- InvoiceConflicts, ExtractionAttempts
- SyncOutboxEvents, SyncCursors, ImportJobs

Quan hệ nghiệp vụ chính:

- Một hóa đơn có nhiều dòng hàng, bằng chứng trích xuất và lần thử trích xuất.
- Một danh mục có thể được dùng cho nhiều hóa đơn, dòng hàng, ngân sách và quy tắc cửa hàng.
- Ngân sách gắn với tháng và danh mục.
- Bảng outbox, cursor và import job phục vụ vận hành đồng bộ/nhập liệu, không phải quan hệ giao dịch giống hóa đơn và dòng hàng.

Cloud có các bảng lõi profiles, invoices, invoice_lines, field_evidences, categories, budgets và merchant_rules. Migration tiếp theo bổ sung nhóm chi tiêu, chia sẻ hóa đơn, job/quota AI, file đính kèm, lịch sử QR và số liệu vận hành. ERD chính chỉ nên giữ bảng liên quan trực tiếp đến chức năng báo cáo; có thể vẽ sơ đồ riêng cho nhóm/chia sẻ.

Tên bảng cloud lấy từ migrations trong repo. Trước khi khẳng định đó là schema đang chạy, kiểm tra migration đã được áp dụng trên project Supabase demo chưa.

#### 2.3.2. Mô tả các bảng

| Bảng | Ý nghĩa | Quan hệ/ghi chú |
| --- | --- | --- |
| invoices | Đầu hóa đơn/giao dịch: người bán, ngày, tiền hàng, thuế tổng, giảm giá tổng, tổng tiền, danh mục, trạng thái, revision | Có nhiều dòng hàng, bằng chứng và lần trích xuất |
| invoice_lines | Mặt hàng/dịch vụ, số lượng, đơn giá, thành tiền và danh mục dòng | Thuộc một hóa đơn |
| field_evidences | Giá trị/bằng chứng trích xuất cho các trường | Thuộc hóa đơn; mô tả chi tiết nếu logic hiện dùng |
| categories | Danh mục giao dịch | Liên kết hóa đơn, dòng hàng, ngân sách và quy tắc merchant |
| budgets | Hạn mức theo tháng và danh mục | Dùng tính đã chi/còn lại/vượt mức |
| merchant_rules | Quy tắc gán danh mục dựa trên cửa hàng | Có thể ảnh hưởng phân loại lần sau |
| extraction_attempts | Lịch sử các lần trích xuất | Hỗ trợ OCR/chẩn đoán |
| invoice_conflicts | Thông tin xung đột khi local và cloud cùng sửa | Dùng trong màn hình xử lý xung đột |
| sync_outbox_events | Thay đổi local chờ đẩy lên cloud | Được sync engine xử lý theo lô |
| sync_cursors | Mốc tải thay đổi incremental | Phân biệt nguồn/loại dữ liệu |
| import_jobs | Trạng thái tác vụ nhập liệu | Theo dõi tiến trình nếu luồng này được bật |

Phần mô tả cột, kiểu dữ liệu, khóa chính/ngoại và ràng buộc cần lấy trực tiếp từ app_database.dart và các migration SQL. Không tự suy ra schema từ tên trường giao diện.

## 5. Chương 3 — Triển khai ứng dụng

### 3.1. Triển khai hệ thống

#### 3.1.1. Kiến trúc ứng dụng Android

Ứng dụng được tổ chức theo feature. Presentation hiển thị giao diện; domain chứa mô hình/quy tắc nghiệp vụ; data chứa repository, parser, client API và truy cập dữ liệu. Riverpod cấp trạng thái/dependency; GoRouter điều khiển điều hướng và auth gate. Drift quản lý SQLite local. Trên Android, MainActivity.kt là điểm khởi chạy Flutter.

Các phần chính:

- Flutter UI: nhập dữ liệu, review AI, danh sách/chi tiết, tổng quan, ngân sách và QR.
- Domain: mô hình hóa đơn/dòng hàng, kiểm tra dữ liệu, phân loại và quy tắc.
- Drift: lưu local và cung cấp truy vấn cho giao diện.
- Supabase Auth/PostgreSQL/Storage: phiên người dùng, dữ liệu cloud và file đính kèm nếu luồng này được bật.
- Edge Function: kiểm soát request AI và giữ API key ở backend.
- VLM: đọc ảnh và sinh kết quả cấu trúc; chất lượng cần được đo thực tế.

#### 3.1.1.1. Kiến trúc backend

Backend dùng Supabase, không dùng Spring Boot. Supabase Auth quản lý tài khoản; PostgreSQL lưu cloud; RLS giới hạn truy cập; Edge Functions viết bằng TypeScript/Deno làm API trung gian. Hàm ai-api nhận yêu cầu trích xuất và gọi VLM theo cấu hình môi trường. API key phải nằm trong Supabase Secrets, không nhúng vào app hay commit.

Source có hỗ trợ lựa chọn Groq/Gemini; provider/model hiệu lực phụ thuộc secrets/config của project Supabase đang deploy. Giá trị mặc định trong source không chứng minh cấu hình thực tế. Trước khi viết báo cáo, xác minh OCR_AI_PROVIDER và model đang dùng ở project demo; chỉ ghi tên provider/model, không ghi API key.

#### 3.1.2. Môi trường triển khai

Thông tin đã đối chiếu trong repo:

- Flutter SDK: 3.47.1 theo file .fvmrc.
- Android: cấu hình Gradle trong android/; MainActivity.kt chạy Flutter engine.
- Supabase: compile-time URL và publishable key; file cấu hình local nằm ngoài Git.
- AI: Edge Function ai-api; provider/model được cấu hình tại backend.
- Internet cần cho đăng nhập lần đầu, OCR ảnh, đồng bộ và các API cloud.

Nhóm cần bổ sung thiết bị/máy ảo, phiên bản Android, JDK, môi trường Supabase (dev/staging) và ngày kiểm thử thực tế. Không ghi URL/key riêng tư hoặc thông tin tài khoản cá nhân.

### 3.2. Các giao diện chính

Chụp từ bản build sẽ nộp; dùng dữ liệu giả hoặc che email, số tài khoản, thông tin cá nhân và nội dung hóa đơn thật.

| Hình gợi ý | Màn hình | Nội dung cần chú thích |
| --- | --- | --- |
| 3.1 | Đăng nhập | Cổng Auth và trạng thái cấu hình |
| 3.2 | Tổng quan | Tháng chọn, tổng thu/chi, biểu đồ ngày, cơ cấu danh mục, ngân sách |
| 3.3 | Lịch sử giao dịch | Danh sách, tìm kiếm và bộ lọc |
| 3.4 | Thêm khoản chi | Ghi khoản chi khi không có hóa đơn |
| 3.5 | Chụp/chọn ảnh | Nguồn ảnh và trạng thái xử lý |
| 3.6 | Review OCR | Trường hóa đơn và mặt hàng có thể sửa |
| 3.7 | Chi tiết hóa đơn | Ngày, danh mục, tổng tiền, thuế/giảm giá tổng, mặt hàng, ảnh nguồn nếu có |
| 3.8 | Ngân sách | Hạn mức, số đã chi, còn lại/vượt mức |
| 3.9 | QR và lịch sử QR | Ghi chú người dùng tự xác nhận thanh toán |

Mỗi hình cần số thứ tự, chú thích dưới hình và câu dẫn trong nội dung. Dùng ảnh app đang chạy thay cho mockup nếu báo cáo trình bày kết quả triển khai.

## 6. Kết luận

### I. Kết quả đạt được

Đối chiếu kết quả với yêu cầu ở Chương 1. Có thể nêu app Flutter Android, đăng nhập, lưu local, thêm khoản chi thủ công, đọc ảnh hóa đơn qua VLM và cho sửa, quản lý danh mục/ngân sách, dashboard, lịch sử giao dịch, quét VietQR và đồng bộ Supabase. Chỉ ghi nhóm/chia sẻ, backup, trợ lý hoặc thông báo nếu đã chạy được và có minh chứng.

### II. Hạn chế

- OCR ảnh phụ thuộc mạng, quota, thời gian phản hồi và dịch vụ AI.
- Mẫu hóa đơn, chất lượng ảnh, chữ nhỏ/mờ và bố cục có thể làm sai ngày, tổng tiền hoặc dòng hàng.
- Người dùng cần rà soát; màn hình sửa không đồng nghĩa OCR luôn chính xác.
- QR chỉ đọc thông tin trong mã và dựa vào xác nhận thủ công; app chưa đối soát giao dịch ngân hàng.
- Offline có giới hạn: thao tác dữ liệu local được hỗ trợ, nhưng OCR/cloud sync và đăng nhập lần đầu cần mạng.
- Chỉ báo cáo độ chính xác sau khi thống nhất tập mẫu, nhãn chuẩn, cách đo và model.

### III. Hướng phát triển

- Đánh giá OCR định lượng trên hóa đơn đa dạng, ghi lại lỗi và số trường người dùng phải sửa.
- Cải thiện hướng dẫn chụp ảnh, phát hiện ảnh mờ/nghiêng và xử lý trường thiếu.
- Thêm đối chiếu tổng tiền với tổng các dòng hàng để người dùng thấy dữ liệu bất nhất.
- Cải thiện đồng bộ nhiều thiết bị, phục hồi sau lỗi mạng và xử lý xung đột.
- Chỉ nghiên cứu đối soát ngân hàng khi có API/ủy quyền phù hợp; hiện không tuyên bố app đã có tính năng đó.

## 7. Kiểm thử và số liệu cần bổ sung

Repository có test cho auth gate, database/migration, import/OCR client, validator, phân loại dòng hàng, review screen, dashboard/ngân sách, QR parser, nhóm/chia sẻ, export/backup và sync. Sự tồn tại của test source không chứng minh test gần nhất đã pass; báo cáo cần ghi kết quả chạy trên commit/bản build cụ thể.

### Kiểm thử chức năng

Với từng ca ghi: mã ca, điều kiện trước, bước thực hiện, dữ liệu đầu vào, kết quả mong đợi, kết quả thực tế và đạt/không đạt. Ưu tiên đăng nhập, thêm thủ công, review OCR, sửa trước lưu, xem chi tiết, lọc lịch sử, ngân sách, QR, mất mạng và đồng bộ lại.

### Đánh giá OCR

- Chọn hóa đơn từ nhiều cửa hàng/bố cục/điều kiện ảnh; tách tập thử khỏi dữ liệu dùng chỉnh prompt nếu có thể.
- Ghi số ảnh, nguồn ảnh, provider/model, ngày chạy, kích thước ảnh, số lỗi API và điều kiện mạng.
- Đo riêng ngày, tổng tiền, thuế tổng, giảm giá, tên cửa hàng và dòng hàng; chỉ chấm trường có nhãn chuẩn.
- Với ngày/tổng tiền có thể dùng exact match; với văn bản/danh sách hàng cần nêu quy tắc chuẩn hóa và cách tính.
- Có thể xem data0.7/, train_images/ và mcocr_train_df.csv là nguồn nghiên cứu sau khi xác minh ảnh khớp nhãn, quyền sử dụng và thông tin cá nhân. Đây không tự động là kết quả đánh giá đã hoàn thành.
- Không đưa một phần trăm “độ chính xác OCR” chung nếu chưa nêu cách tính và cỡ mẫu.

| Hạng mục | Số ca/mẫu | Đạt/đúng | Tỷ lệ/thời gian | Ghi chú |
| --- | ---: | ---: | ---: | --- |
| Đăng nhập/khôi phục phiên |  |  |  |  |
| Thêm khoản chi thủ công |  |  |  |  |
| OCR ngày |  |  |  |  |
| OCR tổng tiền |  |  |  |  |
| OCR dòng hàng/số lượng |  |  |  |  |
| Phân loại danh mục |  |  |  |  |
| Đồng bộ/mất mạng |  |  |  |  |
| QR và xác nhận thủ công |  |  |  |  |

## 8. Tài liệu tham khảo gợi ý

Thay các mục Kotlin/Spring Boot trong biểu mẫu nếu nhóm không dùng các công nghệ này. Chỉ đưa nguồn được viện dẫn và ghi ngày truy cập theo quy định môn học.

1. Flutter, Flutter Documentation, https://docs.flutter.dev/
2. Dart, Dart Documentation, https://dart.dev/guides
3. Riverpod, Documentation, https://riverpod.dev/docs/introduction/getting_started
4. Drift, Documentation, https://drift.simonbinder.eu/
5. Supabase, Use Supabase with Flutter, https://supabase.com/docs/guides/getting-started/quickstarts/flutter
6. Supabase, Edge Functions, https://supabase.com/docs/guides/functions
7. PostgreSQL Global Development Group, PostgreSQL Documentation, https://www.postgresql.org/docs/
8. Groq, Images and Vision, https://console.groq.com/docs/vision — chỉ giữ nếu môi trường demo dùng Groq.
9. Google AI for Developers, Gemini API, https://ai.google.dev/gemini-api/docs — chỉ giữ nếu môi trường demo dùng Gemini.
10. Android Developers, Android Developers Documentation, https://developer.android.com/docs — dùng cho phần tích hợp Android khi cần.

## 9. Phụ lục và minh chứng

- Test case và log kết quả; không chụp/dán API key.
- ERD, sequence diagram và bảng mô tả dữ liệu.
- Ảnh giao diện đã che thông tin cá nhân.
- Hướng dẫn cài/chạy bản demo và yêu cầu cấu hình; cung cấp file mẫu, không đính kèm secret.
- Phiên bản công cụ lấy từ môi trường build thật.
- Nếu đánh giá OCR: tập mẫu đã ẩn dữ liệu nhạy cảm, nhãn chuẩn, cách tính và tổng hợp lỗi.

## 10. Những điểm phải xác minh trước khi nộp

- [ ] Thống nhất tên đề tài và tên app trên bìa, nội dung, hình.
- [ ] Xác minh provider/model VLM ở Supabase của bản demo; không suy từ default trong source.
- [ ] Xác minh migrations cần cho demo đã được áp dụng.
- [ ] Xác minh chức năng nào được bật trong bản demo, đặc biệt nhóm/chia sẻ, PDF/XML, backup và trợ lý.
- [ ] Chạy test trên commit/bản build cụ thể; ghi số đạt, lỗi và môi trường.
- [ ] Ghi thiết bị Android, phiên bản OS và ngày kiểm thử.
- [ ] Số liệu OCR có nhãn chuẩn, cỡ mẫu và cách tính.
- [ ] Thông tin bìa theo mẫu: Châu Tùng Dương — CT070117; Dương Thế Duy — CT070213; Vũ Quốc Huy — CT070131; Võ Hồng An — CT070301; giảng viên TS. Lê Anh Tiến; Hà Nội, 2026.
- [ ] Cập nhật mục lục, danh mục hình và bảng sau khi hoàn thiện Word.

## 11. Mã nguồn để đối chiếu

| Nội dung | Đường dẫn |
| --- | --- |
| Khởi tạo app | lib/main.dart |
| Điều hướng và auth gate | lib/app/router/app_router.dart |
| Cấu hình Supabase | lib/core/security/supabase_bootstrap.dart |
| Schema local | lib/core/database/app_database.dart |
| Import ảnh/PDF/XML | lib/features/ingestion/application/import_coordinator.dart |
| Gọi API trích xuất | lib/features/ingestion/data/ai_extraction_client.dart |
| Kiểm tra/sửa kết quả | lib/features/review/presentation/review_invoice_screen.dart |
| Model hóa đơn/dòng hàng | lib/features/invoices/domain/invoice_models.dart |
| Dashboard | lib/features/dashboard/presentation/dashboard_screen.dart |
| Ngân sách | lib/features/budgets/presentation/budget_screen.dart |
| VietQR | lib/features/payments/data/vietqr_parser.dart và lib/features/payments/presentation/qr_payment_screen.dart |
| Lịch sử QR | lib/features/payments/presentation/qr_payment_history_screen.dart |
| Đồng bộ | lib/features/sync/application/sync_coordinator.dart và sync_engine.dart |
| Backend AI | supabase/functions/ai-api/index.ts |
| Schema cloud/RLS | supabase/migrations/ |
| Kiểm thử | test/
