# Báo cáo tối ưu OCR hóa đơn — TV1

## Tóm tắt bàn giao

| Hạng mục | Thay đổi | Kết quả đã đo |
| --- | --- | --- |
| O1 — suy luận Gemini | Thử `thinkingLevel=low` | 30 cặp ảnh. Token trung bình giảm 30,8%, độ trễ trung bình ở lượt thành công giảm 51,4%. Đúng tổng 30/30 và ngày 29/30 ở cả hai bản. |
| O2 — ảnh đầu vào | Xoay EXIF, thu cạnh dài về 1600 px | 14 ảnh thật trên 1600 px giảm tổng dung lượng 54,15%. Trong 8 cặp gọi Gemini, cả hai bản đúng tổng 8/8 và ngày 7/8 sau retry. |
| O3 — trần đầu ra | Thử 4096 token, từ chối phản hồi có `MAX_TOKENS` | Hóa đơn thật 20 dòng và văn bản mô phỏng 45 dòng đều đủ dòng, đúng tổng tiền và đúng ngày. |
| O4 — ảnh trùng và retry | SHA-256 trên app, lưu kết quả theo yêu cầu ở backend | 5/5 ảnh trùng tránh gọi Gemini trong kiểm tra app. Một lần phát lại thực tế trả kết quả giống hệt trong 83 ms, lượt gốc 9.491 ms. |
| O5 — cảnh báo | So tổng, thuế, giảm giá, dòng hàng và ngày | Cảnh báo 30/30 lỗi tổng tiền được mô phỏng và 0/30 tổng tiền đúng trong phép phát lại. |

Ngày đo: 2026-11-07. Mẫu cố định gồm 30 ảnh MC-OCR có nhãn người bán, ngày và tổng tiền tại `artifacts/tv1/sample.jsonl`. Mỗi ảnh được khóa bằng SHA-256. Các con số dưới đây là kết quả đã chạy, không phải mục tiêu trong tài liệu phân công.

## Phần 0 — Baseline và khả năng đo

- Đã đo Gemini trực tiếp ngày 2026-11-16 qua Supabase local (`127.0.0.1:54321`), xem Phần 1.
- Benchmark mới cố định tập ảnh, xuất đúng payload bằng hàm Flutter, lưu từng request kể cả lỗi, và chấm tổng tiền/ngày trên toàn bộ mẫu. `ai-api` trả thêm `usageMetadata` khi Gemini xử lý thành công để đo token sau khi triển khai backend.
- 30 ảnh thật được chọn có cạnh dài 1024–1365 px, dung lượng trung bình 199,4 KB; tất cả dưới 2 MB.

## Phần 1 — Cấu hình suy luận Gemini (O1/O3)

Đã thêm `AI_EXTRACT_THINKING_LOW=true` để bật `thinkingLevel=low` và `AI_EXTRACT_MAX_OUTPUT_TOKENS` để đặt trần output. Hai cờ mặc định tắt.

**Phép đo 2026-11-16** (Supabase local + `gemini-3.6-flash`, key gói miễn phí 20 request/ngày/key, dùng nhiều key). Đo qua 6 đợt vì hạn mức. Đợt 1: B0 trên 30 ảnh chỉ 14 ảnh thành công (còn lại lỗi 429 hết hạn mức ngày hoặc 504 quá 30 giây), B1 chạy trên đúng 14 ảnh đó. Đợt 2 (key thứ hai): B0 và B1 trên 9 ảnh chưa đo, cả 18 request thành công. Các đợt sau (3–6) bổ sung nốt các ảnh còn thiếu; kết quả cuối cùng đủ **30/30 ảnh**. Bảng ngay dưới là mốc trung gian sau đợt 2, bảng cuối cùng ở cuối phần này.

Mốc trung gian: so sánh từng cặp trên 21 ảnh mà cả hai cấu hình trả kết quả ngay lần đầu:

| Chỉ số | B0 | B1 | Thay đổi |
| --- | ---: | ---: | ---: |
| Token/hóa đơn M1 (trung bình) | 3.355 | 2.302 | **−31,4%** |
| — trong đó thinking token | 1.060 | 0 | −100% |
| — output token | 198 | 205 | +3,5% |
| Độ trễ API M3 trung bình | 15.448 ms | 7.201 ms | **−53,4%** |
| Độ trễ API M3 p50 | 11.392 ms | 6.023 ms | **−47,1%** |
| Độ trễ API M3 p95 | 27.302 ms | 12.710 ms | **−53,4%** |
| Tổng tiền đúng M4 | 21/21 | 21/21 | Không suy giảm |
| Ngày đúng M4 | 20/21 | 20/21 | Không suy giảm |

- B1 tốn ít token hơn trên **21/21** ảnh và nhanh hơn trên 19/21 ảnh. Với model này, `low` loại bỏ hoàn toàn thinking token; input token giữ nguyên (khoảng 2.100), output JSON gần như không đổi.
- Ảnh sai ngày (`mcocr_public_145013rrmow.jpg`, đọc ra 2020-08-10) sai giống hệt ở cả B0 và B1, nên không do cấu hình.
- Đợt 1, B1 có 2/14 ảnh timeout 30 giây ở lần đầu; thử lại thì cả 2 thành công (6,0 s và 8,9 s; đúng tổng và ngày). B0 có 7 lần timeout trên các ảnh khác. Tính cả 2 ảnh thử lại (23 cặp): token −30,8%, độ trễ trung bình −52,2%, tổng đúng 23/23 ở cả hai.
- 14 ảnh đợt 1 được chọn từ những ảnh B0 đã thành công, nên nếu có thiên lệch thì là thiên về B0. Với 21–23 mẫu, p95 chỉ mang tính mô tả.
- 30 ảnh thật đều ≤1600 px nên ảnh gửi đi ở B0 và B1 giống hệt nhau. Mức giảm token và độ trễ **hoàn toàn đến từ O1** (`thinkingLevel=low`).
- Không đặt `maxOutputTokens` mặc định: output lớn nhất quan sát được là 628 token, chưa có hóa đơn nhiều dòng để chọn trần an toàn.

- Đợt 3 (key thứ ba, 14 request trên 7 ảnh cuối): Gemini chậm bất thường ở cả hai cấu hình. B0 hoàn tất 2/7 ảnh, B1 hoàn tất 2/7 ảnh trong mốc 30 giây; ảnh có kích thước bình thường (147–241 KB). Chỉ 1 ảnh có cặp B0–B1 (`xzfyh`): 3.534 → 2.334 token (−34%), 9,9 s → 4,2 s, cả hai đều đúng tổng và ngày, cùng xu hướng với 21 cặp ở trên. Bảng chính không gộp đợt 3 vì điều kiện mạng/dịch vụ khác. 5 ảnh (`mmnhi`, `ojewe`, `uwjom`, `wpnpe`, và `zsgzm` cho B1) cần đo lại khi Gemini ổn định.

- Đợt 4 (2026-11-17, key gốc): B0 thành công 5/6 ảnh còn thiếu, B1 chỉ được 1/6 trước khi hết hạn mức 20 request/ngày (quota reset theo giờ Thái Bình Dương, khoảng 15:00 giờ Việt Nam).

- Đợt 5 (2026-11-17, key khác): B1 thành công 3/5 ảnh còn thiếu trước khi key này cũng hết hạn mức ngày (hạn mức tính theo Google project, không theo key).
- Đợt 6 (2026-11-18, key gốc): hoàn tất 3 lần đo cuối (B0 cho `wpnpe`, B1 cho `wpnpe` và `zsgzm`), cả 3 thành công.

**Tổng hợp cuối cùng — 30/30 ảnh** (lấy lần thành công đầu tiên của mỗi ảnh, kể cả 2 ảnh B1 thử lại sau timeout):

| Chỉ số (30 cặp) | B0 | B1 | Thay đổi |
| --- | ---: | ---: | ---: |
| Token/hóa đơn M1 | 3.305 | 2.286 | **−30,8%** |
| Thinking token | 1.025 | 0 | −100% |
| Output token | 186 | 191 | +2,9% |
| Độ trễ trung bình M3 | 14.457 ms | 7.022 ms | **−51,4%** |
| Độ trễ p50 M3 | 11.252 ms | 6.020 ms | −46,5% |
| Độ trễ p95 M3 | 27.302 ms | 14.404 ms | −47,2% |
| Tổng tiền đúng M4 | 30/30 | 30/30 | Không suy giảm |
| Ngày đúng M4 | 29/30 | 29/30 | Không suy giảm |

B1 tốn ít token hơn trên 30/30 ảnh và nhanh hơn trên 27/30 ảnh. Không có ảnh nào đổi kết quả đúng/sai giữa B0 và B1; ảnh sai ngày (`rrmow`) sai giống nhau ở cả hai. Các cặp đo ở nhiều đợt, nhiều key, nhiều thời điểm khác nhau, nên độ trễ chịu ảnh hưởng của tải Gemini lúc đo; token ổn định hơn độ trễ. Chênh lệch ảnh gửi đi giữa B0 và B1 bằng 0 (ảnh đều ≤1600 px), nên toàn bộ mức giảm đến từ `thinkingLevel=low`.

Dữ liệu thô trong `artifacts/tv1/`: đợt 1 `b0_partial_run1.jsonl`, `b0.jsonl`, `b0_sub.jsonl`, `b1_sub.jsonl`, `b1_retry.jsonl`; đợt 2 `b0_k2.jsonl`, `b1_k2.jsonl`; đợt 3 `b0_k3.jsonl`, `b1_k3.jsonl`; đợt 4 `b0_k4.jsonl`, `b1_k4.jsonl`; đợt 5 `b1_k5.jsonl`; đợt 6 `b0_k6.jsonl`, `b1_k6.jsonl`.

## Phần 2 — Ảnh 1600 px và EXIF (O2)

Đã đổi ngưỡng cạnh dài từ 2048 sang 1600 px, JPEG từ chất lượng 85 sang 80, và xử lý EXIF kể cả khi file dưới 2 MB. Ảnh đã nhỏ và đúng chiều vẫn giữ nguyên byte. Bài kiểm tra gồm ảnh lớn, ảnh có cạnh >1600 nhưng file <2 MB, ảnh EXIF xoay và ảnh không giải mã được đều đạt.

| Tập ảnh | Số ảnh | B0 tổng byte | B1 tổng byte | Thay đổi |
| --- | ---: | ---: | ---: | ---: |
| Ảnh thật có nhãn trong repo | 30 | 6.126.435 | 6.126.435 | 0,00% |
| Stress: 10 ảnh có nhãn được nâng lên 2400 px | 10 | 7.106.033 | 2.169.529 | −69,47% |

Tất cả ảnh stress dưới 2 MB, vì vậy B0 gửi nguyên byte theo mã cũ. Đây là phép đo dung lượng đầu vào mô phỏng ảnh độ phân giải cao; nó chưa chứng minh OCR vẫn đúng trên ảnh camera thật. Mẫu 30 ảnh thật không kích hoạt resize, nên không được báo cáo là đã tiết kiệm 30–45% trên dữ liệu hiện có.

### Đối chứng trên ảnh hóa đơn thật trên 1600 px

Trong 32 ảnh gốc trên 1600 px của `train_images`, 14 ảnh lọt qua bộ lọc nhãn. Cả 14 file đều dưới 2 MB nên bản cũ gửi nguyên ảnh. Bản mới giảm từ **4.874.337 xuống 2.235.041 byte (−54,15%)** và 14/14 ảnh có payload nhỏ hơn. Chọn 8 ảnh đầu theo thứ tự ID để gọi Gemini ở hai cấu hình, giữ cùng backend và chế độ thinking mặc định. Số liệu token và độ trễ trong bảng lấy từ lần thành công của từng ảnh.

| Chỉ số trên 8 ảnh | Ảnh gốc | Resize 1600 px |
| --- | ---: | ---: |
| Tổng byte | 2.548.222 | 1.251.592 |
| Thành công lần đầu | 7/8 | 3/8 |
| Thành công sau thử lại | 8/8 | 8/8 |
| Tổng tiền đúng | 8/8 | 8/8 |
| Ngày đúng | 7/8 | 7/8 |
| Token trung bình | 3.200,9 | 3.128,8 |
| Độ trễ API p50 | 5.529,5 ms | 5.838,0 ms |
| Độ trễ API p95 | 8.550,8 ms | 6.868,1 ms |

Cả hai cấu hình sai ngày trên cùng ảnh `mcocr_public_145013tumhj.jpg`. Sáu lần lỗi ban đầu đều là HTTP 429. Các lượt chạy tuần tự và retry cách nhau 10 giây, nên bảng độ trễ chỉ mô tả các lần thành công và không đo tổng thời gian chờ khi có retry. Chênh lệch nhỏ về token cũng chưa đủ để kết luận resize làm giảm token Gemini. Dữ liệu gốc nằm ở `artifacts/tv1/highres-*.jsonl`, danh sách mẫu ở `highres_sample.jsonl` và `highres_live_sample.jsonl`.

## Phần 3 — Chặn ảnh trùng trước cloud (O4)

Đã chuyển tra SHA-256 lên trước `extractImage`. Với ảnh đã lưu, app dùng hóa đơn cũ; 5 ảnh trùng byte khác nhau trong bài kiểm tra dẫn đến **0/5 lượt gọi VLM**, so với đường cũ phải gọi VLM trước khi phát hiện trùng. ID của tác vụ import trên thiết bị được truyền lại khi retry.

Hash byte chỉ áp dụng cho ảnh đã lưu có nội dung byte giống hệt nhau. Ảnh chụp lại hoặc mã hóa lại có hash khác.

### Chống xử lý lặp ở backend

Migration `20261122000000_ocr_request_replay.sql` lưu kết quả JSON theo tài khoản, `requestId` và hash nội dung. Server xác thực phiên trước khi tra kết quả. Cùng ID và nội dung nhận lại kết quả đã lưu trước bước trừ quota hay gọi Gemini. Khi yêu cầu gốc còn chạy, yêu cầu thứ hai nhận HTTP 409 `OCR_IN_PROGRESS`. Cùng ID nhưng nội dung khác nhận HTTP 409 `OCR_REQUEST_CONFLICT`. Chỉ vai trò máy chủ có quyền gọi RPC và bảng không lưu ảnh hay văn bản nguồn.

Kiểm tra trên Supabase local bằng một hóa đơn thật 20 dòng. Yêu cầu đầu trả đúng tổng tiền và ngày trong 9.491 ms. Yêu cầu phát lại trả JSON giống hệt trong 83 ms. Cả hai nhánh HTTP 409 trả đúng mã. PostgreSQL ghi nhận một kết quả hoàn tất, vai trò `authenticated` không có quyền gọi RPC và vai trò `service_role` có quyền. Kết quả phép đo ở `artifacts/tv1/ocr_replay_live.json`.

Kết quả có thể được phát lại trong 24 giờ. Yêu cầu đang xử lý giữ quyền tối đa hai phút. PostgreSQL dọn dữ liệu hết hạn mỗi 15 phút nếu có `pg_cron`, hoặc khi tài khoản đó yêu cầu OCR lần tiếp theo. Supabase local chưa bật `pg_cron`. Nếu tiến trình dừng giữa lúc Gemini đã trả dữ liệu và lúc PostgreSQL lưu kết quả, một lần thử sau khi quyền hết hạn có thể gọi Gemini lại.

## Phần 4 — Cảnh báo quy tắc (O5)

Validator hiện có đã cảnh báo khi tổng dòng không khớp subtotal, hoặc subtotal + thuế − giảm giá không khớp tổng thanh toán. Đã bổ sung cảnh báo ngày hóa đơn ở tương lai.

Trước đây backend luôn trả `confidence = 0.75` cho `totalMinor`, đúng bằng ngưỡng tô vàng (`< 0.75`) của màn rà soát, nên ô **Tổng thanh toán** không bao giờ được tô. Nay `InvoiceValidator.applyRuleConfidence` chạy ngay sau `extractImage` trong `import_coordinator.dart`: nếu (a) subtotal + thuế − giảm giá ≠ tổng, hoặc (b) tổng các dòng hàng ≠ subtotal (hoặc ≠ tổng − thuế + giảm giá khi thiếu subtotal), vượt sai số cho phép, thì evidence `totalMinor` bị hạ xuống `0.50` và UI tô cảnh báo. Giá trị 0.50 là mức cờ cảnh báo theo quy tắc, không phải xác suất do AI ước lượng. Kiểm thử: ca khớp giữ 0.75, ca lệch thuế/subtotal và ca lệch dòng hàng đều hạ về 0.50.

**M5 chưa thể công bố recall/false-positive trên OCR thật:** tập 30 ảnh chỉ có nhãn ngày và tổng tiền, không có nhãn từng lỗi số học hay trường phải cảnh báo. Cần một tập lỗi gán nhãn (ví dụ ảnh có tổng bị AI đọc sai) để đo.

### Đo cảnh báo bằng cách phát lại kết quả OCR

Phát lại 30 kết quả B1 đã lưu qua parser Flutter và `InvoiceValidator.applyRuleConfidence`. Giữ cùng ngưỡng tô cảnh báo của app (< 0,75). Cả 30 tổng tiền khớp nhãn và 0/30 bị tô cảnh báo. Sau khi cố ý tăng riêng tổng tiền thêm 10.000 đồng trong mỗi kết quả, validator tô cảnh báo 30/30. Mẫu gốc có 0 tổng tiền sai, nên recall trên lỗi thực tế chưa xác định. Ca mô phỏng đánh giá lỗi riêng trường tổng tiền, với các trường khác giữ nguyên. Chạy lại bằng `flutter test tool/replay_tv1_warnings_test.dart --no-pub`.

## Kiểm tra bàn giao

- Hai lượt Flutter đều đạt 20/20 kiểm tra. Lượt đầu bao phủ resize/EXIF, import và validator. Lượt sau bao phủ import, parser và màn rà soát, gồm ca xác nhận hai lần thử gửi cùng ID. Phép phát lại M5 cũng đạt.
- Edge Function đã chạy trên Supabase local. Lịch sử migration local có phiên bản `20261020190000` không có trong repo, nên migration OCR được áp dụng trực tiếp bằng một giao dịch SQL trên DB local. Chưa triển khai lên môi trường từ xa. Khi triển khai, áp dụng migration trước bản Edge Function.

### Kiểm tra trần output

Chạy riêng `gemini-3.6-flash` với `AI_EXTRACT_THINKING_LOW=true` và `AI_EXTRACT_MAX_OUTPUT_TOKENS=4096`.

| Mẫu | Số dòng trả về | Output token | Tổng tiền và ngày | Thời gian API |
| --- | ---: | ---: | --- | ---: |
| Ảnh hóa đơn thật `mcocr_public_145013ogvmp.jpg` | 20/20 | 695 | Đúng cả hai | 5.000 ms |
| Văn bản hóa đơn mô phỏng | 45/45 | 1.514 | Đúng cả hai | 6.650 ms |

Kết quả nằm ở `artifacts/tv1/ocr_output_cap_live.json`. Giữ 4096 là cấu hình tùy chọn vì phép đo mới có một ảnh thật nhiều dòng. Nếu Gemini báo `MAX_TOKENS`, API từ chối kết quả thay vì lưu hóa đơn có thể thiếu dòng. Chưa tạo ca Gemini thực trả `MAX_TOKENS`. Tập phát lại M5 chưa có lỗi tổng tiền tự nhiên để tính recall thực tế.
