# FinmiAI: text, voice và lệnh tài chính

## Hành vi mới

- Text nhập và text nhận dạng từ voice đi qua cùng bộ phân tích ý định.
- Voice ưu tiên `vi-VN` hoặc `en-US` theo lựa chọn ngôn ngữ giao diện. AI trả lời, câu hỏi làm rõ và thông báo ghi/sửa dùng ngôn ngữ giao diện, kể cả khi ngôn ngữ đầu vào khác.
- Mọi nền tảng (kể cả web) dùng chung một luồng: ghi WAV 16 kHz mono bằng `record`, không hiển thị chữ trong lúc nói; khi đang ghi hiển thị sóng âm theo amplitude của recorder. Sau ít nhất 150 ms tiếng nói và 2,5 giây im lặng, app tự dừng. Đây là VAD theo mức âm thanh, chưa phải mô hình VAD thần kinh; môi trường ồn hoặc micro quá nhỏ cần kiểm tra thực tế.
- Dừng (chạm nút "Dừng và gửi", khoảng lặng hoặc giới hạn 30 giây) sẽ gửi bản ghi tới `ai-api/transcribe` qua 9Router, hiển thị thanh tiến trình "Đang chuyển giọng nói thành văn bản…", rồi tự gửi văn bản cho trợ lý (bước trả lời dùng chỉ báo "Đang suy nghĩ"). Hủy/chuyển nền/đóng màn hình không gửi. Phiên âm lỗi thì giữ nguyên bản nháp đã gõ và hiện thông báo lỗi.
- Đã bỏ Web Speech API; chưa có streaming transcription.
- Không có đọc câu trả lời thành tiếng.

## Các lệnh

| Ví dụ | Kết quả |
|---|---|
| Bạn là ai? / Who are you? | Giới thiệu FinmiAI theo ngôn ngữ giao diện, không gọi model |
| Tôi là ai? / Neural Network là gì? | Từ chối ngoài phạm vi |
| Tôi vay Nam 500k | Ghi khoản mình nợ Nam |
| Tôi cho Nam vay 500k / Nam owes me 500,000 VND | Ghi khoản Nam nợ mình |
| Khoản nợ giữa tôi và Nam 500k, chưa rõ ai nợ ai | Hỏi lại chiều nợ, chưa ghi |
| Ăn trưa hôm nay hết 35k / Record lunch 35,000 VND today | Ghi chi |
| Received a bonus of 2 million VND today | Ghi thu |
| Sửa khoản vừa ghi thành 600k | Giữ ID, sửa khoản cuối do chính phiên chat tạo |
| Tạo lịch thu lương 10 triệu hàng tháng bắt đầu 05/11/2026 | Tạo lịch thu định kỳ |
| Nhắc chi tiền nhà 3 triệu hàng tháng từ 05/11/2026 | Tạo lịch nhắc chi định kỳ |
| Tạo nhóm Du lịch Đà Lạt | Tạo nhóm bằng RPC hiện có |
| Thu quỹ nhóm Du lịch 500k tiền góp | Ghi thu quỹ |
| Chi quỹ nhóm Du lịch 100k tiền xe | Ghi chi quỹ, backend kiểm tra số dư |
| Mở chia tiền nhóm Du lịch | Đối chiếu tên, mở màn nhóm và dialog chia tiền |
| Hủy | Hủy lệnh thiếu thông tin/đang chờ; không xóa khoản đã lưu |

Lệnh đủ dữ liệu tự ghi. Nếu phát hiện khả năng trùng, app yêu cầu xác nhận rõ ràng (`xác nhận`, `vẫn lưu`, `yes`, `confirm`...). Tên nhóm khớp không phân biệt hoa thường/khoảng trắng; không tự chọn bằng fuzzy matching. Không tìm thấy/trùng tên thì hỏi lại. Các thao tác thực sự chuyển tiền hoặc tự lưu phép chia nhóm không được cung cấp qua model.

## Guardrails và dữ liệu

1. Bộ lọc local cho danh tính, các ví dụ ngoài phạm vi và yêu cầu bí mật/tài khoản khác.
2. Backend có kiểm tra xác thực, quota, ngân sách AI, giới hạn đầu vào và prompt phân biệt câu hỏi, giả định, ví dụ với yêu cầu ghi thực tế.
3. Cấu trúc lệnh chuẩn ở `supabase/functions/_shared/assistant_command.schema.json`. Backend và app đều kiểm tra tên lệnh, trường, enum, ngày, số nguyên VND dương và danh mục đúng loại. Model không được gửi ID bản ghi/tài khoản, SQL, đường dẫn hoặc tên RPC tùy ý.
4. App tự cấp ID, chỉ dùng repository và RPC được lập trình sẵn. Không tự đoán người, nhóm, chiều nợ, ngày định kỳ hoặc số tiền còn thiếu. Một tin nhắn chỉ có một thao tác.
5. “Sửa vừa ghi” giới hạn theo phiên chat và tài khoản; không sửa bản ghi lịch sử tùy ý. Thu/chi/nợ/lịch được đối chiếu trạng thái trước khi sửa. Nợ đã thanh toán không bị ghi đè. Sửa quỹ dùng ID server trả về và compare-and-swap trong RPC, chỉ người tạo được sửa; bảo vệ số dư bằng khóa nhóm.
6. Lỗi ghi/mạng không kích hoạt retry hay chuyển sang writer khác, không tự thông báo thành công. Nếu kết quả không rõ, người dùng được nhắc kiểm tra sổ trước khi thử lại.
7. Công cụ đọc bổ sung chỉ tổng hợp nợ của tài khoản hiện tại, lịch đã cấu hình và nhóm truy cập được; tối đa 5 dòng chi tiết kèm tổng số dòng. Không gửi số điện thoại, token, mã mời nhóm hay thông tin tài khoản khác.

Guardrails nhiều lớp giảm lỗi; không phải bảo đảm model luôn hiểu mọi câu đúng. Kiểm thử ngữ nghĩa với model thật vẫn cần chạy sau triển khai.

## Giới hạn kế thừa

- Thu định kỳ hiện hỗ trợ hàng tháng. Nếu yêu cầu tuần/năm, AI hỏi lại để chọn lịch tháng; không tự chuyển tần suất.
- Chi định kỳ tạo `RecurringBill` (lịch nhắc), không tự coi hóa đơn tương lai đã thanh toán.
- Nợ tiếp tục dùng kho local theo tài khoản; thay đổi này không bổ sung đồng bộ nợ lên cloud.
- Chưa đổi tên nhóm bằng lệnh sửa; sửa trực tiếp trong màn nhóm.
- Tiền qua lệnh AI hiện là VND. Không ngầm chuyển USD hoặc ngoại tệ thành VND.
- Khi AI online không khả dụng, chế độ English trả thông báo English; chưa có bộ trả lời phân tích offline đầy đủ bằng English.

## Triển khai và kiểm tra

Hướng dẫn teammate nhận code từ main, cấu hình Supabase và chạy web: [Bàn giao Finmi](teammate-handoff-20261023.md).

Chưa deploy function, chưa chạy migration lên database thật, chưa thay Supabase Secrets. Cần cập nhật đồng bộ backend trước khi dùng luồng `assistant_command` mới trong app:

1. Rà soát các migration chưa áp dụng bằng `npx supabase db push --dry-run`.
2. Áp dụng migration đã duyệt, gồm `20261023140000_update_own_group_fund_entry.sql`.
3. Deploy `ai-api` với thư mục `_shared` đi kèm, giữ cấu hình xác thực hiện có.
4. Chạy `tool/eval_finmi_ai.mjs` bằng Deno với biến môi trường `FINMI_AI_URL`, `FINMI_AI_ACCESS_TOKEN`, `FINMI_AI_PUBLISHABLE_KEY` của tài khoản test. Script chỉ gọi parser, không thực thi ghi sổ. Có 29 ví dụ VI/EN, nợ hai chiều, làm rõ, sửa, câu giả định, từ chối, lịch và nhóm. Không lưu các giá trị xác thực vào Git.
5. Kiểm tra mic thật trên Chrome/Edge localhost hoặc HTTPS và Android/iOS; thử nói nối câu, ngừng 2,5 giây, hủy, từ chối quyền, đổi ngôn ngữ, mạng chậm và môi trường ồn.

Kiểm thử local: toàn bộ 451 Flutter tests đã qua; 50 test tập trung chat/voice/nhóm chạy lại sau các sửa đổi cuối đều qua. `flutter analyze --no-pub` không có lỗi/cảnh báo. Build web với cấu hình dev hiện có thành công (exit 0). Deno type check/3 guard tests và test Web Speech bằng Node đã qua. Migration được chạy trên PostgreSQL PGlite cô lập, kiểm tra xác thực, quyền người tạo, xung đột và số dư; chưa thay thế kiểm thử tích hợp Supabase/RLS thực tế.
