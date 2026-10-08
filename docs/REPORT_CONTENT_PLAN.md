# Kế hoạch triển khai nội dung báo cáo

## 1. Mục tiêu

Hoàn thiện báo cáo môn học **Lập trình Android nâng cao** theo khung trong
`BÁO CÁO LẬP TRÌNH ANDROID NÂNG CAO.docx`, mô tả đúng ứng dụng hiện có, có sơ đồ,
hình minh họa và kết quả kiểm thử có thể kiểm chứng.

Tên đề tài dự kiến:

> **Xây dựng ứng dụng quản lý chi tiêu cá nhân trên Android, hỗ trợ trích xuất
> thông tin hóa đơn bằng mô hình thị giác ngôn ngữ**

Tên cuối cùng cần được cả nhóm thống nhất trước khi viết bìa và lời nói đầu.

## 2. Nguyên tắc thực hiện

- Phân biệt rõ tính năng **đã hoàn thành**, **đang hoàn thiện** và **hướng phát triển**.
- Đối chiếu mô tả kiến trúc, luồng xử lý và cơ sở dữ liệu với mã nguồn, migration
  và cấu hình thật.
- Chỉ công bố số liệu OCR sau khi chạy kiểm thử có dữ liệu đối chiếu; không tự ước
  lượng hoặc suy diễn độ chính xác.
- Trong bản báo cáo, mô tả nhà cung cấp VLM đang dùng trong bản demo. Nếu app hỗ trợ
  nhiều nhà cung cấp, nêu rõ nhà cung cấp được chọn cho lần đánh giá.
- Không đưa API key, thông tin đăng nhập, dữ liệu cá nhân hoặc ảnh hóa đơn có thông
  tin nhạy cảm vào báo cáo và phụ lục.
- Giữ cấu trúc chính của biểu mẫu; sửa các mục tham khảo không khớp với sản phẩm
  (ví dụ Kotlin/Spring Boot nếu không được dùng trong app).

## 3. Tiến độ đề xuất

Kế hoạch dưới đây tính theo ngày làm việc; nhóm có thể điều chỉnh theo hạn nộp.

| Ngày | Công việc | Đầu ra / tiêu chí hoàn thành |
| --- | --- | --- |
| 1 | Kiểm kê tính năng, công nghệ, trạng thái triển khai; thống nhất tên đề tài và phạm vi | Bảng tính năng đã xác minh; phạm vi và thuật ngữ thống nhất |
| 2 | Chạy kiểm thử chức năng và đánh giá OCR; chụp màn hình các luồng chính | Bảng test case, dữ liệu đo OCR, thư mục ảnh minh họa |
| 3 | Vẽ use case, kiến trúc, sequence diagram và ERD | Bộ sơ đồ có tên, chú giải và nội dung nhất quán |
| 4 | Viết Lời nói đầu và Chương 1; viết use case/yêu cầu Chương 2 | Bản nháp phần mở đầu, tổng quan và yêu cầu |
| 5 | Hoàn thành thiết kế Chương 2; viết kiến trúc, triển khai và giao diện Chương 3 | Bản nháp các chương chính có sơ đồ và ảnh |
| 6 | Viết kết luận, rà soát số liệu/trích dẫn, cập nhật mục lục và định dạng | Bản báo cáo hoàn chỉnh để cả nhóm duyệt |

## 4. Kế hoạch nội dung theo cấu trúc báo cáo

### Phần đầu báo cáo

- Hoàn thiện tên đề tài, tên nhóm, mã sinh viên và giảng viên theo biểu mẫu.
- Viết **Lời nói đầu** gồm bối cảnh quản lý chi tiêu, vấn đề cần giải quyết, mục
  tiêu, phạm vi, phương pháp thực hiện và bố cục báo cáo.
- Sau khi nội dung ổn định, cập nhật tự động mục lục, danh mục hình và danh mục
  bảng trong Word.

### Chương 1 — Tổng quan đề tài

#### 1.1. Đặt vấn đề

Giải thích khó khăn khi ghi chép chi tiêu thủ công, nhu cầu quản lý hóa đơn và lý
do chọn trích xuất thông tin hóa đơn bằng AI. Nêu giới hạn thực tế: quét hóa đơn
bằng VLM cần mạng và người dùng cần kiểm tra, sửa kết quả trước khi lưu.

#### 1.2. Yêu cầu ứng dụng

- **Yêu cầu chức năng:** đăng ký/đăng nhập; nhập hóa đơn thủ công hoặc từ ảnh; xem
  và sửa kết quả trích xuất; quản lý danh mục/ngân sách; xem tổng quan; đồng bộ dữ
  liệu; các chức năng nhóm, chia sẻ, sao lưu hoặc trợ lý nếu chúng nằm trong phạm
  vi bản demo.
- **Yêu cầu phi chức năng:** bảo vệ phiên và dữ liệu người dùng; phản hồi lỗi mạng
  và API; giữ dữ liệu đã lưu khi offline; dễ sử dụng; kiểm tra được kết quả OCR.
- Đánh dấu mỗi yêu cầu là hoàn thành, một phần hoặc chưa triển khai để tránh mô tả
  chức năng dự kiến như chức năng đã có.

#### 1.3. Công nghệ

Lập bảng công nghệ, vai trò và lý do lựa chọn. Dự kiến gồm Flutter/Dart cho ứng
dụng Android, quản lý trạng thái và điều hướng đang dùng trong mã nguồn, SQLite/
Drift cho dữ liệu local, Supabase cho xác thực/backend và PostgreSQL, Edge Function
làm cổng gọi AI, cùng API VLM được cấu hình cho bản demo.

### Chương 2 — Phân tích và thiết kế hệ thống

#### 2.1. Use case

- Vẽ use case tổng quát với người dùng và các dịch vụ ngoài có tương tác trực tiếp.
- Phân rã các nhóm chức năng chính: tài khoản, hóa đơn/OCR, ngân sách và báo cáo,
  đồng bộ, nhóm chia sẻ và sao lưu nếu có trong phạm vi.
- Viết mô tả ngắn cho các use case trọng tâm: mục tiêu, điều kiện trước, luồng
  chính, luồng lỗi và kết quả.

#### 2.2. Sequence diagram

Ưu tiên ba luồng sau:

1. Đăng nhập và khôi phục phiên bằng Supabase Auth.
2. Chọn ảnh hóa đơn → gửi yêu cầu có xác thực tới backend → VLM trả dữ liệu có cấu
   trúc → người dùng kiểm tra/sửa → lưu hóa đơn.
3. Lưu dữ liệu local khi offline → đưa thay đổi vào hàng đợi → đồng bộ khi có mạng
   và xử lý xung đột nếu phát sinh.

Chỉ thể hiện các bước đúng với implementation hiện tại; nếu luồng OCR dùng job bất
đồng bộ thì sơ đồ phải thể hiện submit, kiểm tra trạng thái và retry tương ứng.

#### 2.3. Thiết kế cơ sở dữ liệu

- Vẽ riêng hoặc phân biệt rõ cơ sở dữ liệu local SQLite và dữ liệu cloud PostgreSQL.
- Lấy bảng, khóa, quan hệ và ràng buộc từ schema/migration đang có; không tự đặt tên
  bảng dựa trên tên tính năng.
- Với mỗi bảng trong phạm vi, lập bảng mô tả: tên trường, kiểu dữ liệu, khóa/ràng
  buộc và ý nghĩa.
- Nêu cách dữ liệu gắn với tài khoản và đồng bộ giữa thiết bị với cloud.

### Chương 3 — Triển khai ứng dụng

#### 3.1. Kiến trúc và môi trường

- Vẽ kiến trúc tổng thể: app Flutter, lưu trữ local, Supabase Auth/Database/Storage
  (nếu luồng dùng), Edge Functions, nhà cung cấp VLM và dịch vụ đồng bộ.
- Mô tả trách nhiệm từng phần và luồng dữ liệu; phân biệt xử lý trên thiết bị với
  xử lý trên backend.
- Ghi môi trường phát triển, phiên bản công cụ và bước cấu hình/chạy app. Không ghi
  giá trị bí mật vào tài liệu.
- Điều chỉnh phân cấp tiêu đề để phần Android và backend ngang hàng nếu cấu trúc
  hiện tại làm backend bị lồng dưới Android.

#### 3.2. Giao diện chính

Chụp ảnh từ bản app đang chạy, che dữ liệu nhạy cảm và thêm chú thích ngắn. Ưu tiên
các màn hình:

1. Đăng nhập/quản lý tài khoản.
2. Tổng quan chi tiêu và biểu đồ.
3. Danh sách hóa đơn.
4. Quét hóa đơn và màn hình kiểm tra/sửa kết quả OCR.
5. Ngân sách hoặc thống kê theo danh mục.
6. Đồng bộ/trạng thái lỗi hoặc nhóm chia sẻ nếu tính năng đó được đưa vào phạm vi.

Mỗi ảnh cần có số hình, tiêu đề và được nhắc tới trong phần mô tả.

#### 3.3. Kiểm thử và đánh giá

Bổ sung mục này vào Chương 3. Với kiểm thử chức năng, ghi bước thực hiện và kết quả
mong đợi/thực tế. Với OCR, chọn khoảng **30–50 hóa đơn đa dạng bố cục** để tiết
kiệm thời gian và lượt gọi API; tách tập đánh giá khỏi dữ liệu dùng để phát triển
prompt nếu có thể.

Các chỉ số đề xuất:

- Tỷ lệ đọc chính xác tổng tiền và ngày.
- Tỷ lệ đọc đúng tên cửa hàng và số dòng mặt hàng trên các trường hợp có nhãn chuẩn.
- Độ chính xác phân loại mặt hàng nếu có đáp án chuẩn.
- Thời gian xử lý trung vị, tỷ lệ lỗi API và số trường người dùng phải sửa.

Lập bảng kết quả thực đo, ghi rõ cỡ mẫu, cách tính và nhà cung cấp/model đã dùng.
Nếu chưa có dữ liệu nhãn chuẩn cho một trường thì ghi nhận xét định tính, không
đưa phần trăm chính xác cho trường đó.

### Kết luận

- **Kết quả đạt được:** đối chiếu lần lượt với yêu cầu Chương 1.
- **Hạn chế:** ghi giới hạn đã kiểm chứng, ví dụ cần kết nối mạng cho VLM, chịu hạn
  mức/độ trễ của dịch vụ ngoài và cần người dùng rà soát kết quả.
- **Hướng phát triển:** tối ưu quy trình OCR, mở rộng đánh giá, cải thiện đồng bộ
  hoặc bổ sung tính năng ngoài phạm vi hiện tại.

### Tài liệu tham khảo và phụ lục

- Thay tài liệu không liên quan bằng tài liệu chính thức của Flutter, Dart,
  Supabase, PostgreSQL, Drift và API VLM thực sự sử dụng.
- Ghi ngày truy cập tài liệu trực tuyến theo quy định của môn học.
- Phụ lục có thể chứa test case, hướng dẫn chạy, sơ đồ lớn và liên kết repository;
  không chép toàn bộ mã nguồn vào báo cáo.

## 5. Bộ minh chứng cần thu thập

- [ ] Bảng yêu cầu chức năng/phi chức năng và trạng thái triển khai.
- [ ] Use case tổng quát và use case phân rã.
- [ ] Sequence diagram cho đăng nhập, OCR và đồng bộ.
- [ ] ERD/schema local và cloud, kèm bảng mô tả dữ liệu.
- [ ] Ảnh chụp các màn hình chính từ bản app chạy thật.
- [ ] Test case và kết quả chạy.
- [ ] Tập hóa đơn đánh giá đã loại thông tin cá nhân, nhãn chuẩn và bảng số liệu OCR.
- [ ] Danh sách tài liệu tham khảo khớp công nghệ thực dùng.

## 6. Rà soát trước khi nộp

- [ ] Tên đề tài và tên ứng dụng nhất quán trên bìa, nội dung và hình ảnh.
- [ ] Không mô tả tính năng chưa triển khai như kết quả đã đạt.
- [ ] Sơ đồ khớp luồng app và schema thực tế.
- [ ] Số liệu có cỡ mẫu và cách tính; không có số liệu tự ước lượng.
- [ ] Mọi hình/bảng đều có số thứ tự, chú thích và được dẫn trong nội dung.
- [ ] Tài liệu Kotlin/Spring Boot đã được thay nếu không dùng trong dự án.
- [ ] Đã cập nhật mục lục và danh mục hình/bảng sau lần sửa cuối.
- [ ] Đã kiểm tra chính tả, định dạng tiêu đề, số trang và thông tin sinh viên.

## 7. Phân công nhóm

Nhóm tự điền người phụ trách theo năng lực và thời gian; mỗi chương cần có một
người chịu trách nhiệm biên tập cuối, nhưng cả nhóm cùng xác nhận tính chính xác
của mô tả tính năng và số liệu.

| Đầu việc | Người phụ trách | Người rà soát |
| --- | --- | --- |
| Kiểm kê tính năng, yêu cầu và công nghệ |  |  |
| Use case, sequence diagram |  |  |
| Kiến trúc, database/ERD |  |  |
| Kiểm thử OCR, số liệu và ảnh minh họa |  |  |
| Biên tập, tham khảo và định dạng Word |  |  |
