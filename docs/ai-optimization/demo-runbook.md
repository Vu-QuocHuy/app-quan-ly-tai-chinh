# Runbook demo: Tối ưu AI cho Finmi (B0 so với B1)

> **Trạng thái: bản nháp (T5.2).** Chưa chạy thử đủ 8 cảnh trên bản tích hợp (T2.7). Mọi chỗ ghi `⏳` là số chưa đo; **không** đọc số thay thế khi trình bày. Danh sách đầy đủ ở mục "Số liệu còn thiếu" cuối tài liệu.
>
> Quy ước số liệu: chỉ dùng số đã có trong `docs/TV1_OPTIMIZATION_REPORT.md` (nhánh TV1, mục "Tổng hợp cuối cùng — 30/30 ảnh"). Số lượt gọi chat "theo thiết kế" (B0 = 3 lượt; B1 = 0 hoặc 1 lượt) là hành vi được thiết kế, chưa phải số đo, đến khi T3.3 chạy xong.

Hai bản chạy cạnh nhau (`run_dual_instances.ps1`): **B0 – GỐC** (nhãn đỏ, toàn bộ cờ OFF) bên trái, **B1 – TỐI ƯU** (nhãn xanh, `AI_FLAG_PROFILE=b1`) bên phải. Mỗi bản dùng **một tài khoản riêng** (`demo-b0`, `demo-b1`) với dữ liệu mẫu giống hệt nhau.

Tổng thời lượng: **5 phút 30 giây** (330 giây), xem bảng chuyển cảnh ở Phần B.

---

## Phần A. Kiểm tra trước buổi demo 1 tiếng

Làm theo thứ tự, tick từng ô. Nếu một ô không đạt, xử lý ở Phần C trước khi sang ô tiếp.

**Hạ tầng và khóa**

- [ ] Khóa Gemini trả phí còn hạn mức (không dùng khóa gói miễn phí 20 request/ngày).
- [ ] Project dev/benchmark: `AI_FLAG_ENVIRONMENT=dev`, khớp `APP_ENV` của cả hai bản app.
- [ ] `AI_ALLOW_DEBUG_HEADERS` và `AI_EXPOSE_USAGE_META` đang **bật** (chỉ ở project dev/benchmark, tuyệt đối không bật ở production).
- [ ] 9Router `GET health` trả OK.
- [ ] Mạng dự phòng sẵn sàng: điện thoại bật phát Wi-Fi, đã thử kết nối từ laptop demo.

**Tài khoản và dữ liệu**

- [ ] Chạy `reset_demo_account.sql` cho **cả hai** tài khoản `demo-b0` và `demo-b1` (xóa `ocr_request_replay`, job OCR, sự kiện `ai_client_events`, giao dịch phát sinh trong buổi trước).
- [ ] Bản B0 đăng nhập `demo-b0`; bản B1 đăng nhập `demo-b1`. Không dùng chung tài khoản (nếu dùng chung, ảnh nhập ở B0 sẽ làm cảnh 5 chặn trùng sai).
- [ ] Dữ liệu giao dịch của hai tài khoản giống hệt nhau (so tổng chi tháng này ở hai bên).
- [ ] Nút **reset** trong bảng điều khiển đã bấm ở cả hai bản (xóa bộ đếm, telemetry, lịch sử chat cục bộ; không xóa giao dịch).

**Giao diện AI Lab (cả hai bản)**

- [ ] Banner đầu màn hình đúng chữ: `B0 – GỐC` (đỏ) ở bản trái, `B1 – TỐI ƯU` (xanh) ở bản phải.
- [ ] **Không** có cảnh báo vàng "LỆCH CỜ". Nếu có: Phần C, mục 4.
- [ ] Radio lỗi giả lập đang ở **Không**; công tắc "Bóp méo tổng hóa đơn (lỗi mô phỏng)" đang **tắt**.
- [ ] Ảnh mẫu `receipt_normal.jpg` và `receipt_repeat.jpg` có trong nút chọn hóa đơn mẫu; hai ảnh chưa nhập vào tài khoản nào.

**Dự phòng**

- [ ] Video quay sẵn đủ 8 cảnh mở sẵn trong một cửa sổ riêng (T5.5).
- [ ] Slide đã mở đến cảnh 8; ba hình đã chèn: cột chồng token, box plot độ trễ, sơ đồ luồng chat.
- [ ] Chạy thử trọn kịch bản một lượt (rồi reset lại hai tài khoản).

---

## Phần B. Kịch bản 8 cảnh

### Bảng chuyển cảnh

| # | Cảnh | Thời lượng | Cộng dồn |
|---|---|---:|---:|
| 1 | Câu hỏi tra cứu có đáp án sẵn | 40 s | 0:40 |
| 2 | Câu hỏi cần suy luận | 40 s | 1:20 |
| 3 | Lệnh ghi không bị coi là câu hỏi | 30 s | 1:50 |
| 4 | OCR hóa đơn: thanh token | 60 s | 2:50 |
| 5 | Chọn lại đúng ảnh cũ | 30 s | 3:20 |
| 6 | Hóa đơn có tổng bị lệch (lỗi mô phỏng) | 50 s | 4:10 |
| 7 | Giả lập 9Router lỗi 429 | 50 s | 5:00 |
| 8 | Slide chi phí | 30 s | **5:30** |

Mọi thao tác làm **giống nhau ở hai bên**, B0 trước rồi B1, trừ khi ghi khác.

---

### Cảnh 1. Câu hỏi tra cứu có đáp án sẵn (40 s)

**Thao tác:** ở cả hai bản, mở bảng điều khiển (ngăn kéo cạnh dưới) và bấm nút câu hỏi có sẵn **"Tháng này tôi chi bao nhiêu?"**.

| | B0 – GỐC | B1 – TỐI ƯU |
|---|---|---|
| Số lượt gọi mô hình | 3 lượt (`assistant_command`, chat gọi công cụ, chat trả lời), theo thiết kế; ⏳ chờ số đo T3.3 | 0 lượt, theo thiết kế; ⏳ chờ số đo T3.3 |
| Huy hiệu | `☁ ĐÁM MÂY · 3 lượt · …` (số lượt, thời gian: ⏳ chờ số đo T3.3) | `⚡ TRÊN MÁY · 0 lượt · …` (thời gian: ⏳ chờ số đo T3.3) |
| Con số trả lời | Một con số tổng chi | **Cùng con số**, đến từ truy vấn SQLite |

**Lời nói:** "Câu này có đáp án sẵn trong SQLite thì không cần gọi mô hình. Bên trái phải đi ba lượt qua đám mây, bên phải trả lời ngay trên máy, và con số giống nhau. Số liệu từ SQL còn chính xác hơn để mô hình tự tính."

**Nếu sai:** hai bên khác con số, hoặc B1 hiện `☁`: dừng, kiểm tra banner và dữ liệu mẫu (Phần C, mục 4 và 5).

---

### Cảnh 2. Câu hỏi cần suy luận (40 s)

**Thao tác:** bấm nút **"Tại sao tháng này tôi chi nhiều?"** ở cả hai bản.

| | B0 – GỐC | B1 – TỐI ƯU |
|---|---|---|
| Số lượt gọi mô hình | 3 lượt, theo thiết kế; ⏳ chờ số đo T3.3 | 1 lượt, theo thiết kế; ⏳ chờ số đo T3.3 |
| Huy hiệu | `☁ ĐÁM MÂY · 3 lượt · …` | `☁ ĐÁM MÂY · 1 lượt · …` (thời gian: ⏳ chờ số đo T3.3) |
| Nội dung | Câu giải thích chi tiêu | Câu giải thích tương đương |

**Lời nói:** "Câu này cần mô hình suy luận nên không thể xử lý cục bộ. Nhưng dữ liệu cần dùng đoán trước được, nên bên phải nạp sẵn vào prompt và chỉ gọi một lượt thay vì ba."

---

### Cảnh 3. Lệnh ghi không bị coi là câu hỏi (30 s)

**Thao tác:** bấm nút **"Hôm nay ăn trưa hết 35k"** ở cả hai bản.

| | B0 – GỐC | B1 – TỐI ƯU |
|---|---|---|
| Kết quả | Hiện thẻ xác nhận giao dịch | Hiện thẻ xác nhận giao dịch, **giống hệt** B0 |
| Số lượt gọi | Số lượt đúng theo đường gốc (⏳ chờ số đo T3.3) | Số lượt đúng theo đường gốc (⏳ chờ số đo T3.3); **không** định tuyến sang `local` |

Chọn **Hủy** trên thẻ xác nhận (không ghi giao dịch vào tài khoản demo).

**Lời nói:** "Bộ định tuyến của nhóm bảo thủ: lệnh ghi không bao giờ bị coi là câu hỏi, nên hai bên cho kết quả giống nhau. Tối ưu không được phép làm sai dữ liệu của người dùng."

**Nếu sai:** B1 trả lời bằng văn bản thay vì thẻ xác nhận là lỗi định tuyến (Review Focus 4): bỏ qua cảnh này, mở lỗi cho TV2 sau buổi demo.

---

### Cảnh 4. OCR hóa đơn: thanh token (60 s)

**Thao tác:** bấm nút chọn hóa đơn mẫu, chọn `receipt_normal.jpg`, ở cả hai bản (B1 bấm ngay sau B0, hoặc đồng thời nếu hai người thao tác). Chỉ vào **thanh token** (cột chồng đầu vào / suy luận / đầu ra) và đồng hồ thời gian.

| | B0 – GỐC | B1 – TỐI ƯU |
|---|---|---|
| Thanh token | Có phần **suy luận** (thinking) rõ rệt | Phần suy luận **biến mất** (0) |
| Thời gian | Lâu hơn | Nhanh hơn; trên 30 ảnh, độ trễ trung bình giảm **51,4%** |
| Độ chính xác | Đọc đúng tổng tiền | Đọc đúng tổng tiền |

**Số liệu đã đo (TV1, 30 ảnh hóa đơn):**

- Token trung bình mỗi hóa đơn: 3.305 (B0) giảm còn 2.286 (B1), tức **−30,8%**.
- Token suy luận: 1.025 giảm về 0, tức **−100%**.
- Độ trễ trung bình: 14.457 ms giảm còn 7.022 ms, tức **−51,4%**.
- Tổng tiền đúng **30/30** ở cả hai bản; không ảnh nào đổi đúng/sai.
- Chi phí mỗi hóa đơn giảm: ⏳ chờ số đo T3.5 / Bảng 6.6 (spec nêu −62,6% nhưng con số này chưa có trong báo cáo TV1).

Lưu ý khi nói: một ảnh đơn lẻ trên màn hình có thể nhanh/chậm khác trung bình vì độ trễ phụ thuộc tải Gemini lúc đó. Chuyển sang slide box plot **chỉ khi** đã có dữ liệu độ trễ từng ảnh (⏳ chờ dữ liệu thô từ TV1); nếu chưa có thì dùng slide cột chồng token (`figures/token_stack_b0_b1.png`).

**Lời nói:** "Cùng một hóa đơn, bên phải mất cả phần suy luận: giảm ba mươi phẩy tám phần trăm token và nhanh hơn khoảng một nửa trên 30 ảnh nhóm đã đo. Độ chính xác tổng tiền giữ nguyên, ba mươi trên ba mươi."

---

### Cảnh 5. Chọn lại đúng ảnh cũ (30 s)

**Thao tác:** bấm lại nút chọn hóa đơn mẫu, chọn **lại `receipt_normal.jpg`** ở cả hai bản. (Tài khoản B0 và B1 tách riêng nên mỗi bên đã nhập ảnh này đúng một lần ở cảnh 4.)

| | B0 – GỐC | B1 – TỐI ƯU |
|---|---|---|
| Kết quả | Gọi mô hình lần nữa (thanh token xuất hiện lại) | Báo "đã nhập" ngay, **0 lượt gọi** |
| Số liệu đã đo | | 5/5 ảnh trùng tránh được lượt gọi VLM (kiểm tra app) |

**Lời nói:** "App tính SHA-256 của ảnh trước khi gửi. Ảnh đã nhập thì dùng lại kết quả cũ, không tốn một lượt gọi mô hình nào. Trong kiểm tra của nhóm, năm trên năm ảnh trùng đều tránh được lượt gọi."

Nếu thầy hỏi thêm về lớp phía server: kết quả OCR được lưu theo `requestId` và hash nội dung, phát lại trong **83 ms** so với **9.491 ms** của lượt gốc (đo trên Supabase local, một hóa đơn thật 20 dòng).

Lưu ý: cảnh này chạy được cả khi mạng yếu vì việc chặn trùng nằm trên máy.

---

### Cảnh 6. Hóa đơn có tổng bị lệch (lỗi mô phỏng) (50 s)

**Thao tác:**

1. Bật công tắc **"Bóp méo tổng hóa đơn (lỗi mô phỏng)"** ở cả hai bản.
2. Bấm nút chọn hóa đơn mẫu và chọn **ảnh chưa nhập trong buổi** (đề xuất `receipt_repeat.jpg`). Không dùng lại `receipt_normal.jpg`: ở B1 ảnh đó đã bị chặn trùng từ cảnh 4 nên sẽ không sinh kết quả OCR để bóp méo. ⚠ Cần xác nhận khi chạy T2.7; nếu chỉ có một ảnh thì bấm **reset** trước cảnh này.
3. Mở màn hình rà soát kết quả ở cả hai bản.
4. Sau cảnh, **tắt** công tắc.

| | B0 – GỐC | B1 – TỐI ƯU |
|---|---|---|
| Ô **Tổng thanh toán** | Không cảnh báo, hiển thị số bị lệch như số thật | **Tô vàng** (cảnh báo) |

**Phải nói rõ trong lời nói:** lỗi này là **mô phỏng**. Công tắc đổi riêng tổng tiền của kết quả OCR (+10%, theo T2.6) trước bước hậu kiểm; mô hình Gemini không thực sự đọc sai.

**Số liệu đã đo (TV1, phát lại 30 kết quả OCR):** 0/30 tổng tiền đúng bị tô cảnh báo; sau khi cố ý tăng tổng thêm 10.000 đồng, validator tô cảnh báo **30/30** lỗi mô phỏng. Chưa đo được recall trên lỗi OCR tự nhiên vì tập 30 ảnh không có ca tổng bị đọc sai.

**Lời nói:** "Đây là một lỗi **mô phỏng**: chúng em cố ý bóp méo tổng tiền để minh họa. Bên trái, số sai trôi qua im lặng. Bên phải, hậu kiểm số học so tổng dòng hàng, thuế và giảm giá nên ô Tổng bị tô vàng. Trên phép phát lại 30 hóa đơn, không có cảnh báo giả nào, và cả 30 lỗi mô phỏng đều bị bắt. Chúng em chưa dám nói về tỉ lệ bắt được lỗi OCR tự nhiên."

---

### Cảnh 7. Giả lập 9Router lỗi 429 (50 s)

**Thao tác:**

1. Ở cả hai bản, trong nhóm radio lỗi giả lập chọn **429**. (Bảng điều khiển gắn header `x-finmi-fault: 429`; công tắc này chỉ có hiệu lực ở bản debug.)
2. Hỏi 3 câu cần đám mây: bấm nút **"Tại sao tháng này tôi chi nhiều?"** rồi gõ thêm 2 câu thuộc nhóm suy luận trong bộ 40 câu (⏳ chốt hai câu cụ thể ở T2.7). Không dùng câu của cảnh 1: ở B1 câu đó trả lời trên máy nên không chạm 9Router.
3. Sau cảnh, chọn lại radio **Không**.

| | B0 – GỐC | B1 – TỐI ƯU |
|---|---|---|
| Kết quả | Báo lỗi, hoặc trả lời cục bộ cơ bản | Vẫn có câu trả lời, huy hiệu `↪ DỰ PHÒNG: Gemini` |
| Số liệu | ⏳ chờ số đo T3.4 | ⏳ chờ số đo T3.4 (10/10 câu 200 OK, từ lần thứ 4 không còn chờ 9Router: **kỳ vọng thiết kế**, chưa đo) |

Nếu cả 9Router lẫn Gemini lỗi (`AI_DEGRADED`): câu trả lời vẫn hiện từ trợ lý cục bộ, huy hiệu `⚠ CỤC BỘ (AI_DEGRADED)`, quota được hoàn (kỳ vọng thiết kế; ⏳ chờ số đo T3.4).

**Lời nói:** "Khi nhà cung cấp chính trả 429, bên trái thất bại. Bên phải ngắt mạch, chuyển sang Gemini dự phòng và hoàn lại quota, người dùng vẫn nhận được câu trả lời, huy hiệu ghi rõ đã dùng dự phòng."

---

### Cảnh 8. Slide chi phí (30 s)

**Thao tác:** chuyển sang slide bảng chi phí.

- Theo spec (§5.2): chi phí hằng tháng giảm từ **147 xuống 55 USD** (và khoảng **27 USD** nếu chuyển sang Gemini 3.8 Flash). Đây là số của spec, **chưa** được kiểm lại bằng số đo: ⏳ chờ số đo T3.5 (3.8 Flash) và Bảng 6.6 / T5.3 (bảng 100 và 200 người dùng).
- Phần giảm đã đo chắc chắn: token OCR −30,8% (mục cảnh 4). Phần giảm lượt gọi chat: ⏳ chờ số đo T3.3.

**Lời nói:** "Bài toán chi phí đặt ra ban đầu đã được trả lời bằng số: giảm token OCR, bỏ lượt gọi thừa ở chat, và chặn ảnh trùng. Bảng này tính cho 100 và 200 người dùng." (Chỉ đọc con số trên slide nếu đã được điền từ Bảng 6.6.)

---

## Phần C. Xử lý sự cố

| # | Sự cố | Dấu hiệu | Cách xử lý |
|---|---|---|---|
| 1 | Gemini chậm hoặc hết quota | OCR quay quá ~10 giây, hoặc lỗi 429/504 | Nói "Gemini đang chậm" và **chuyển sang video quay sẵn** cho cảnh 4 trở đi. Không đợi quá 30 giây (mốc timeout). Cảnh 1, 3, 5 không phụ thuộc Gemini nên vẫn chạy trực tiếp |
| 2 | Mất mạng hoặc mạng phòng yếu | App không kết nối được | Chuyển sang điện thoại phát Wi-Fi. Nếu vẫn không được: chỉ chạy cảnh **1, 3, 5** (xử lý trên máy), phần còn lại chiếu slide và video |
| 3 | Lỗi giả lập kẹt (radio 429 chưa trả về "Không") | Mọi câu hỏi ở cả hai bản đều lỗi | Chọn radio **Không**, bấm **reset**, hỏi lại |
| 4 | Hai bản lệch cờ | Banner vàng "LỆCH CỜ", hoặc B1 hiện `☁` ở cảnh 1 | Kiểm `AI_FLAG_ENVIRONMENT` khớp `APP_ENV` và `AI_ALLOW_DEBUG_HEADERS` đang bật. **Reload** cả hai bản, kiểm banner `B0 – GỐC` / `B1 – TỐI ƯU` rồi mới tiếp tục |
| 5 | Ai đó nhập dữ liệu vào tài khoản demo, hoặc hai bản có số liệu khác nhau | Con số cảnh 1 khác nhau giữa hai bên; cảnh 5 báo "đã nhập" ở B0 | Chạy `reset_demo_account.sql` cho hai tài khoản, bấm **reset**, đăng nhập lại đúng tài khoản |
| 6 | Cảnh 5 không chặn trùng ở B1 | B1 gọi mô hình lần nữa | Kiểm B1 có đang dùng chung tài khoản với B0 không; kiểm cờ `ai.extract.precheck_dedup` đang bật ở B1. Nếu không sửa kịp: chuyển sang video cảnh 5 |
| 7 | Cảnh 6 không tô vàng ở B1 | Ô Tổng không đổi màu | Kiểm công tắc "Bóp méo tổng hóa đơn (lỗi mô phỏng)" đã bật và ảnh chưa bị chặn trùng (dùng ảnh khác hoặc **reset**). Nếu vẫn không: chuyển sang video cảnh 6 |
| 8 | Overlay không hiện số (ô hiển thị "—") | Thiếu `_meta` | Kiểm `AI_EXPOSE_USAGE_META` đang bật; ô "—" là hành vi đúng khi server không trả `_meta`, vẫn tiếp tục kịch bản |

Nguyên tắc chung: **không sửa cấu hình giữa chừng khi đang trước khán giả**. Nếu quá 20 giây không khắc phục được, chuyển sang video và nói "để đảm bảo thời gian, em xin chiếu phần quay sẵn".

---

## Phần D. Câu hỏi thầy có thể hỏi

Số đo lấy từ báo cáo TV1 hoặc ghi rõ chưa đo. Phần "chưa đo" sẽ được điền sau khi hoàn tất giai đoạn 3.

| Câu hỏi | Ý trả lời (số liệu hoặc nguồn) |
|---|---|
| Sao dùng Gemini 3.6 mà không dùng 3.8 hay Gemini 4? | 3.8 Flash: đã thử với bộ 30 ảnh, kết quả ⏳ chờ số đo T3.5 (quyết định đổi mặc định chỉ khi tổng tiền không kém 3.6, tức 30/30). Gemini 4 Argon là model frontier, đắt hơn, chưa phát hành rộng, không phù hợp cho tác vụ trích xuất: đã cân nhắc và loại bỏ |
| Sao Flutter 3.47 mà không phải 3.50? Android API bao nhiêu? | Nâng lên 3.47.8 (bản vá có cập nhật BoringSSL); chưa lên 3.50 vì bản này mới ra khoảng hai tuần và đánh dấu `package:flutter/material.dart` là deprecated. Chi tiết trong spec §4. Kết quả nâng Flutter và API 37: ⏳ chờ số đo T4.1 / T4.2 |
| Router bằng luật thì có gì mới? Sao không dùng router học máy như RouteLLM? | Router luật tất định: không cần tải model, kiểm thử được bằng unit test, an toàn với lệnh ghi (0 lệnh ghi bị định tuyến nhầm là điều kiện chấp nhận, kết quả ⏳ chờ số đo T3.3). Thời gian định tuyến: ⏳ chờ số đo T3.3 (M9 p50). Router học máy cần dữ liệu huấn luyện và thêm độ trễ. Hybrid LLM và RouteLLM đưa ra nguyên tắc chung; nhóm áp dụng vào ràng buộc của mobile |
| 30 ảnh có đủ không? | So sánh theo cặp trên cùng 30 ảnh: token giảm trên 30/30 ảnh, nhanh hơn trên 27/30 ảnh, tổng tiền đúng 30/30 ở cả hai bản, không ảnh nào đổi đúng/sai. Ngày đúng 29/30 ở cả hai (cùng một ảnh sai). p95 chỉ mang tính mô tả (đã ghi trong báo cáo TV1); độ trễ đo ở nhiều đợt, nhiều khóa, nên chịu ảnh hưởng tải Gemini lúc đó, token ổn định hơn độ trễ |
| `thinkingLevel=low` có rủi ro với hóa đơn khó không? | Có hậu kiểm số học (O5) và từ chối kết quả khi gặp `MAX_TOKENS`. Trong đợt 1 (14 ảnh), B0 có 7 lần timeout 30 giây trên các ảnh khác nhau, B1 có 2 lần (cả hai thử lại đều thành công). Mẫu nhỏ nên chỉ mang tính mô tả |
| Thu nhỏ ảnh có giảm token không? | Chưa kết luận được. 30 ảnh thật đều ≤ 1600 px nên ảnh gửi đi ở B0 và B1 giống hệt nhau: toàn bộ mức giảm 30,8% đến từ `thinkingLevel=low`. Thu nhỏ giảm dung lượng upload (14 ảnh thật trên 1600 px: −54,15% byte) nhưng chênh lệch token Gemini trên 8 cặp quá nhỏ để kết luận. Đây là phát hiện nhóm chủ động báo cáo. Thử `media_resolution` medium: ⏳ chờ số đo T3.6 |
| Prompt caching thì sao? | Ngưỡng implicit cache của Gemini 3.6 Flash là 4.096 token (theo spec §5.4), prompt hiện ngắn hơn nên chưa áp dụng được. Prompt đã sắp xếp sẵn để dùng khi đủ ngưỡng |
| Chặn ảnh trùng hoạt động thế nào, có sai không? | Hash SHA-256 trên app, 5/5 ảnh trùng tránh được lượt gọi VLM; backend lưu kết quả theo `requestId` + hash, phát lại 83 ms so với 9.491 ms. Giới hạn: chỉ áp dụng cho ảnh có byte giống hệt, ảnh chụp lại hoặc mã hóa lại có hash khác |
| Cảnh báo lệch tổng có báo nhầm nhiều không? Có bắt được lỗi thật không? | 0/30 hóa đơn đúng bị tô cảnh báo; 30/30 lỗi mô phỏng (+10.000 đồng vào tổng) bị bắt. Recall trên lỗi OCR tự nhiên **chưa xác định** vì chưa có tập lỗi gán nhãn |
| Chat tối ưu bớt được bao nhiêu lượt gọi? Có làm câu trả lời kém đi không? | Thiết kế: tra cứu 3 → 0 lượt (local router), câu suy luận 3 → 1 lượt (gộp lượt). Số đo trên bộ 40 câu: ⏳ chờ số đo T3.3 (M6, M7, M9, `contains_expected`; điều kiện chấp nhận: `misrouted_write` = 0 và tỉ lệ trả lời đúng ở B1 không thấp hơn B0) |
| Khi nhà cung cấp chính lỗi thì sao? | Circuit breaker + failover sang Gemini + hoàn quota; nếu cả hai lỗi thì trả lời cục bộ, huy hiệu `⚠ CỤC BỘ (AI_DEGRADED)`. Số đo kịch bản 429 (10 câu): ⏳ chờ số đo T3.4 |
| Chi phí giảm bao nhiêu với 100/200 người dùng? | Theo spec: 147 → 55 USD/tháng, khoảng 27 USD nếu dùng 3.8 Flash. Bảng chi tiết 100/200 người dùng và số đo chính thức: ⏳ chờ số đo T3.5 và T5.3 (Bảng 6.6) |
| Tối ưu này "di động" ở chỗ nào? | Offloading thiết bị – đám mây (0 lượt gọi với câu tra cứu), giảm request mạng, giảm byte tải lên (ảnh 1600 px, chặn ảnh trùng), xử lý trong isolate; (P2) bộ nhớ và thời gian xử lý ảnh theo giới hạn Android 17: ⏳ chờ số đo T6.1 nếu làm |

---

## Số liệu còn thiếu

Mỗi dòng là một chỗ `⏳` trong tài liệu này. Khi task tương ứng xong, thay marker bằng số thật rồi xóa dòng khỏi danh sách.

| # | Số còn thiếu | Xuất hiện ở | Task điền |
|---|---|---|---|
| 1 | Số lượt gọi chat thực đo của B0 (kỳ vọng thiết kế 3) và B1 (0 hoặc 1) trên bộ 40 câu (M6) | Cảnh 1, 2, 3; Q&A | T3.3 |
| 2 | Thời gian phản hồi chat B0 và B1 (M9 p50/p95), nội dung huy hiệu `· … ·` | Cảnh 1, 2; Q&A (thời gian định tuyến) | T3.3 |
| 3 | Tỉ lệ cục bộ (M7), `misrouted_write` = 0, tỉ lệ trả lời đúng B1 so với B0 | Cảnh 3; Q&A | T3.3 |
| 4 | Số đo failover 429 (10 câu 200 OK, `provider = gemini`, `failover = true`, circuit mở từ lần thứ 4), kịch bản `AI_DEGRADED` và quota hoàn | Cảnh 7; Q&A | T3.4 |
| 5 | Kết quả Gemini 3.8 Flash so với 3.6 Flash (token, độ trễ, đúng tổng/ngày) và chi phí tính lại | Cảnh 8; Q&A | T3.5 |
| 6 | Kết quả thử `media_resolution` medium | Q&A (thu nhỏ ảnh) | T3.6 |
| 7 | Mức giảm chi phí mỗi hóa đơn OCR (spec nêu −62,6%, chưa có trong báo cáo TV1) | Cảnh 4 | T3.5 và Bảng 6.6 (T5.3) |
| 8 | Bảng chi phí 100 và 200 người dùng (spec nêu 147 → 55 USD, khoảng 27 USD với 3.8; chưa kiểm lại bằng số đo) | Cảnh 8; Q&A | T3.5, T5.3 |
| 9 | Độ trễ từng ảnh (dữ liệu thô 30 ảnh) để vẽ box plot có vạch timeout 30 s; cho đến lúc đó chỉ dùng hình cột chồng token | Cảnh 4 | TV1 cung cấp, rồi chạy `make_charts.py --latency-b0 … --latency-b1 …` (T3.7) |
| 10 | Hai câu suy luận cụ thể dùng ở cảnh 7 và ảnh mẫu dùng ở cảnh 6 | Cảnh 6, 7 | T2.7 |
| 11 | Kết quả nâng Flutter 3.47.8 và target SDK 37 | Q&A (Flutter, Android) | T4.1, T4.2 |
| 12 | Bộ nhớ và thời gian xử lý ảnh trên điện thoại thật (chỉ nếu làm) | Q&A ("di động") | T6.1 |
| 13 | Thời lượng từng cảnh khi chạy thật (bảng 330 s là dự kiến) | Phần B | T2.7, T5.6 |
