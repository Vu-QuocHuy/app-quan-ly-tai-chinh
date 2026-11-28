# Kế hoạch hoàn thiện code và demo: Tối ưu AI cho Finmi

Cập nhật ngày 25/11/2026, dựa trên ba nhánh `origin/tv2-AN` (64509a0), `origin/feat/tv3-ai-platform` (34b8959) và `origin/feat/tv1-ocr-optimization` (2264348). Cả ba nhánh đều tách từ `main` @ 69bc60a và chưa nhánh nào được merge.

---

## 1. Tổng kết hiện trạng

| Thành viên | Đã làm xong | Đã có số đo thật | Còn thiếu |
|---|---|---|---|
| TV1 (OCR) | O1 thinking low, O3 trần 4096 + từ chối `MAX_TOKENS`, O2 1600 px/q80/EXIF, O4 chặn SHA-256 trước khi gọi + bảng phát lại ở server (409 khi đang xử lý hoặc xung đột), O5 hạ confidence về 0.50 + cảnh báo ngày ở tương lai | **Có, đầy đủ nhất nhóm**: 30 cặp ảnh MC-OCR, token −30,8%, thinking −100%, độ trễ TB −51,4%, p95 −47,2%, độ chính xác không đổi (tổng 30/30, ngày 29/30). O2: −54,15% dung lượng trên 14 ảnh lớn. O4: 0/5 lượt gọi, phát lại 83 ms so với 9.491 ms. O5: 0/30 cảnh báo nhầm, 30/30 lỗi mô phỏng bị bắt | Chưa gắn vào cờ tính năng: O1 dùng biến môi trường `AI_EXTRACT_THINKING_LOW`; O2, O4, O5 chạy vô điều kiện. Chưa đo tỉ lệ bắt lỗi trên lỗi tự nhiên. Chưa deploy lên Supabase từ xa |
| TV2 (Chat) | H3 router cục bộ (11 ý định), H2+H4 gộp lượt, H5 prompt −43,6% + `max_tokens` 800, H8 phân loại cục bộ (sửa thêm lỗi chữ "đ"), telemetry riêng `ChatMetricsRecorder` | Chỉ có số đo offline: số lượt theo thiết kế (3 → 0/1/2), 473/473 test đạt, 20/20 lệnh ghi không bị định tuyến nhầm | **Chưa có số đo thật trên 40 câu** (M6, M7, M8, M9). Deno test mới chạy qua shim Node |
| TV3 (Nền tảng) | N2 ghi token, N4 10 cờ `ai.*` mặc định OFF, N3 `AiTelemetry` + bảng `ai_client_events`, N1 9Router sang HTTPS + danh sách host được phép, N5 circuit breaker (3 lỗi, nghỉ 30 s) + failover 9Router → Gemini → `AI_DEGRADED` + hoàn quota, header gỡ lỗi `x-finmi-flags`/`x-finmi-fault`, trường `_meta` | Chưa có số đo (kịch bản test failover đã viết sẵn) | Chạy kịch bản failover 429, ghi kết quả |
| TV4 | Bản nháp báo cáo v2 đã cập nhật số liệu thật của TV1 | | Bộ 40 câu chat, đo chat B0/B1, tổng hợp, demo |

**Kết luận:** luồng OCR đã có đủ bằng chứng để báo cáo. Luồng chat mới chỉ có bằng chứng theo thiết kế, đây là lỗ hổng lớn nhất cần lấp trước khi trình bày.

---

## 2. Các vấn đề khi tích hợp (phải xử lý trước khi demo)

Mình đã kiểm tra bằng `git merge-tree` (chỉ đọc, không sửa repo):

1. **Xung đột merge.** TV2 và TV3 xung đột 7 chỗ, ở các file `feature_flags.dart`, `app_providers.dart`, `chat_screen.dart`, `ai-api/index.ts` và `feature_flags_test.dart`. TV3 và TV1 xung đột 8 chỗ, đều trong `ai-api/index.ts`. Riêng TV2 và TV1 merge được tự động.

2. **Migration của TV3 sẽ lỗi khi chạy sau migration của TV2. Đây là lỗi nghiêm trọng.**
   - Migration của TV2 (`20261107100000`) đổi ràng buộc tên cờ sang dạng pattern, rồi thêm các cờ `ai.chat.skip_command`, `ai.chat.prefetch_facts`, `ai.chat.compact_prompt`.
   - Migration của TV3 (`20261112100000`) chạy sau, lại đặt ràng buộc về một danh sách cố định không có 3 cờ trên. Lệnh `ADD CONSTRAINT` sẽ báo lỗi vì trong bảng đã có dòng vi phạm, làm hỏng `supabase db push`.

3. **Tên cờ không thống nhất.**

   | Kỹ thuật | Tên TV2 đang dùng | Tên trong danh mục của TV3 |
   |---|---|---|
   | H2 + H4 | `ai.chat.skip_command` + `ai.chat.prefetch_facts` | `ai.chat.merge_calls` |
   | H5 | `ai.chat.compact_prompt` | `ai.chat.prompt_v2` |

4. **Giá trị mặc định ngược nhau.** TV2 bật cờ (`true`) ở cả `dev`, `staging` và `production`. TV3 tắt hết (`false`). Nếu giữ như hiện tại, cấu hình mặc định sẽ không còn là B0.

5. **Hai cơ chế chọn prompt.** TV2 cho client gửi `promptVersion`; chính TV2 cũng ghi rủi ro: client mới gọi server cũ sẽ bị trả lỗi 400. TV3 thì đọc cờ phía server qua `ctx.enabled("ai.chat.prompt_v2")`. Nên chọn cách của TV3.

6. **Hai hệ thống telemetry.** TV2 có `ChatMetricsRecorder`, TV3 có `AiTelemetry`. Nên giữ `AiTelemetry`, chuyển các chỗ ghi của TV2 sang đó (giữ dòng log `finmi_ai_metric` nếu muốn).

7. **TV1 không đi qua cờ.** Với O1, nên chuyển sang `ctx.enabled("ai.extract.thinking_low")` theo đúng mẫu mà tài liệu TV3 đã viết sẵn cho TV1; biến môi trường chỉ giữ làm override. O2, O4, O5 phải đọc các cờ `ai.extract.image_1600`, `ai.extract.precheck_dedup`, `ai.extract.validator`. Nếu không làm việc này thì **không thể demo B0 và B1 cạnh nhau**, và không đo lại được B0 trên bản tích hợp.

8. **Thứ tự deploy.** Migration phát lại OCR của TV1 phải được áp trước Edge Function. TV1 cũng ghi nhận lịch sử migration ở máy local có phiên bản `20261020190000` không có trong repo, cần làm sạch trên project dev.

9. **Chạy song song hai bản để demo.** `tool/run_dual_instances.ps1` chạy 2 bản web với cùng `APP_ENV=dev`, nên cả hai sẽ đọc **cùng một bộ cờ**. Cần thêm cách ghi đè cờ cho từng bản, xem mục 3, bước P0.4.

---

## 3. Kế hoạch hoàn thiện code

### P0: Tích hợp (khoảng 1,5 ngày, người làm: TV4 cùng TV3 để rà soát)

1. **Tạo nhánh `integration/ai-opt` từ `main`** và merge theo thứ tự TV3 → TV2 → TV1. TV3 vào trước vì là nền tảng, các nhánh sau sẽ thích ứng theo.

2. **Thống nhất cờ trong một migration mới** (ví dụ `20261125100000_ai_flags_unify.sql`):
   - Dùng ràng buộc pattern của TV2.
   - Danh mục 10 cờ theo TV3, tất cả mặc định OFF.
   - Xóa 3 cờ cũ của TV2 nếu đã có.
   - Sửa migration TV3 để không thêm lại ràng buộc danh sách cố định. Làm được vì cả hai migration **chưa deploy lên project từ xa**; cần xác nhận lại điều này với TV2 và TV3.
   - Đổi tên cờ trong code TV2: `skip_command` và `prefetch_facts` gộp thành `merge_calls`, `compact_prompt` thành `prompt_v2` (đọc phía server).

3. **Nối TV1 vào cờ** như mô tả ở vấn đề 7. Sửa `extractInvoice` theo chữ ký `generateGeminiJson(ctx, …)` mới của TV3.

4. **Ghi đè cờ theo từng bản app** (chỉ trong bản debug):
   - Thêm `--dart-define=AI_FLAG_PROFILE=b0|b1|server`. Client dùng profile này thay cho cờ từ server.
   - Khi profile là `b0` hoặc `b1`, client gắn thêm header `x-finmi-flags` vào mọi lời gọi `ai-api`. Server đã hỗ trợ header này khi bật `AI_ALLOW_DEBUG_HEADERS=true`.
   - Sửa `run_dual_instances.ps1` để bản cổng 8080 chạy `b0`, bản cổng 8081 chạy `b1`.

5. **Gộp telemetry** về `AiTelemetry` như mô tả ở vấn đề 6.

6. **Cổng kiểm tra:**
   - `flutter analyze` không lỗi.
   - `flutter test` đạt toàn bộ.
   - `deno test` chạy bằng **Deno thật** cho `supabase/functions/_shared/*_test.ts`.
   - Chạy thử 5 ảnh OCR trên bản tích hợp để chắc số liệu không lệch so với số của TV1.

7. **Deploy lên project dev:**
   - Thứ tự: `supabase db push` → đặt secrets theo tài liệu TV3 → deploy `ai-api`, `ai-worker`, `health`.
   - Khóa Gemini: **nên dùng key trả phí**, hoặc một project có bật billing. Key miễn phí 20 yêu cầu/ngày là nguyên nhân TV1 phải đo qua 6 đợt, và sẽ làm hỏng buổi demo.

### P1: Lấp số liệu còn thiếu (khoảng 1 ngày)

| Việc | Người | Đầu ra | Bảng trong báo cáo |
|---|---|---|---|
| Đo chat trên 40 câu: B0, chỉ `local_router`, `local_router + merge_calls`, B1 | TV2 + TV4 | CSV M6, M7, M8 (từ `ai_request_benchmark`), M9 | 3.2, 6.4, 6.7 |
| Chạy kịch bản failover 429 trên 10 câu, cờ OFF và ON | TV3 | `_meta.provider`, log mở mạch, số lần hoàn quota | 6.5 |
| **So sánh Gemini 3.8 Flash với 3.6 Flash** trên cùng 30 ảnh, thinking low (30 lượt gọi) | TV1 | Token, độ trễ, độ chính xác | 6.4, cột cuối 6.6 |
| **Thử `media_resolution` medium** trên 30 ảnh, thinking low | TV1 | Token ảnh, độ chính xác | 5.3 |
| Kiểm tra phiên bản nền tảng (xem mục 4) | TV4 | Điền Bảng 3.3 | 3.3 |

Hai thử nghiệm in đậm chỉ là đổi tham số nhưng có lợi lớn:
- **3.8 Flash** có giá bằng một nửa: chi phí OCR cho 200 người dùng dự kiến giảm từ 54,90 xuống 27,45 USD/tháng. Thử nghiệm này cũng trả lời trước câu hỏi rất có thể bị hỏi: "sao không dùng model mới nhất?"
- **`media_resolution`** là cách duy nhất thật sự giảm được token ảnh, như báo cáo đã phân tích và số đo của TV1 đã xác nhận.

Quy tắc chung: chỉ áp dụng nếu tỉ lệ đúng tổng tiền không giảm.

### P2: Điểm nhấn "tối ưu di động" (làm nếu còn thời gian, 1–2 ngày)

Thầy hay hỏi về tính mới và tính "di động", nên mục này đáng làm nếu kịp:

1. **Đo bộ nhớ và thời gian xử lý ảnh trên điện thoại thật** (Android Studio Profiler hoặc Flutter DevTools, bản profile).
   - Hiện app giải mã toàn bộ ảnh bằng thư viện `image` của Dart rồi mới thu nhỏ. Với ảnh 12 MP, riêng bộ đệm điểm ảnh đã khoảng 48 MB.
   - Android 17 (API 37) bắt đầu giới hạn bộ nhớ theo RAM thiết bị và kill tiến trình vượt ngưỡng (`MemoryLimiter:AnonSwap`).
   - Phương án O2b: giải mã có lấy mẫu giảm ở tầng native (ví dụ `ui.instantiateImageCodec` với `targetWidth`, hoặc thư viện nén native), đặt sau cờ riêng. So sánh đỉnh bộ nhớ và thời gian trên 5 ảnh camera 12 MP.
   - Đây là kỹ thuật thuần di động, có số đo thật, và gắn trực tiếp với thay đổi mới nhất của Android.

2. **Đo dung lượng mạng mỗi lượt chat**: B0 có 3 request so với 0 request ở B1. Đọc từ DevTools Network hoặc từ `payload_bytes` của TV3. Số này dễ đưa vào slide.

3. **Gemini Nano qua ML Kit GenAI Prompt API.** Chỉ làm nếu trong nhóm có máy hỗ trợ (Pixel 9/10/11, Galaxy S26, OnePlus 15…). Hạn chế: API đang beta, chưa có plugin Flutter (phải viết platform channel), tài liệu không nói gì về tiếng Việt, và không chạy được ở nền. Nếu không có máy thì chỉ trình bày ở Chương 7 như báo cáo đã viết.

---

## 4. Phiên bản nền tảng: chuẩn bị trả lời "vì sao không dùng bản mới nhất"

| Thành phần | Hiện tại | Mới nhất | Đề xuất |
|---|---|---|---|
| Flutter | 3.47.1 (FVM) | 3.50.0 (11/11/2026), Dart 3.14 | Nâng lên **3.47.8** ngay: bản vá có cập nhật BoringSSL. Chưa lên 3.50 trước buổi demo vì bản này mới ra 2 tuần và đánh dấu `package:flutter/material.dart` là deprecated. Lý do để trả lời thầy: ổn định, đã qua đủ test, có bản vá bảo mật |
| Android target/compile SDK | lấy theo `flutter.targetSdkVersion` | Android 17 / API 37 (16/6/2026) | Chạy `./gradlew :app:properties` để biết con số thật. Nên đặt cụ thể `compileSdk = 37`, `targetSdk = 37` và test trên emulator API 37. Lưu ý các thay đổi của API 37 có thể ảnh hưởng: giới hạn bộ nhớ, chặn truy cập mạng nội bộ mặc định, không được tắt xoay/đổi kích thước trên màn hình lớn |
| Model OCR | `gemini-3.6-flash` (7/2026) | `gemini-3.8-flash` (9/2026), giá ½ | Chuyển nếu thử nghiệm P1 đạt |
| Model frontier | | Gemini 4 Argon (30/9/2026), $2/$10 giá giới thiệu, chưa phát hành rộng | Không cần cho OCR, vì đắt hơn và đi ngược mục tiêu tối ưu. Nêu như một lựa chọn đã cân nhắc và loại bỏ |

---

## 5. Kế hoạch demo

### 5.1. Thứ cần làm thêm cho demo: "AI Lab overlay" (khoảng 1 ngày, TV2 hoặc TV4)

Một lớp phủ nhỏ, chỉ có ở bản debug, đặt ở góc màn hình. Dữ liệu lấy từ `AiTelemetry` và trường `_meta` của server:

- **Huy hiệu trên mỗi bong bóng chat:** `⚡ TRÊN MÁY · 0 lượt · 40 ms`, `☁ ĐÁM MÂY · 1 lượt · 2,1 s`, hoặc `↪ DỰ PHÒNG: Gemini`.
- **Thanh token của lần đọc hóa đơn gần nhất:** cột chồng 3 màu (đầu vào / suy luận / đầu ra). Ở B1, phần suy luận biến mất; đây là hình ảnh dễ nhớ nhất của cả bài.
- **Bộ đếm cộng dồn:** số lượt gọi mô hình, token, chi phí ước tính (USD và VND), và dòng "đã tiết kiệm so với B0" do bản B1 tự tính theo công thức của Bảng 6.6.
- **Nhãn cấu hình** ở đầu màn hình, chữ lớn: `B0 – GỐC` (đỏ) hoặc `B1 – TỐI ƯU` (xanh).

Không cần màn hình quản trị phức tạp. Chỉ cần 1 widget `Stack` phủ lên app shell, bật bằng `--dart-define=AI_LAB=true`.

### 5.2. Kịch bản demo (5–6 phút, hai bản chạy cạnh nhau qua `run_dual_instances.ps1`)

| # | Thao tác (làm giống nhau ở hai bên) | Người xem thấy | Ý cần nói |
|---|---|---|---|
| 1 | Hỏi "Tháng này tôi chi bao nhiêu?" | B0: 3 lượt, vài giây. B1: `⚡ 0 lượt`, gần như tức thì, cùng một con số | Câu có đáp án sẵn trong SQLite thì không cần LLM. Số liệu từ SQL còn chính xác hơn |
| 2 | Hỏi "Tại sao tháng này tôi chi nhiều?" | B0: 3 lượt. B1: 1 lượt | Gộp lượt gọi khi đoán trước được dữ liệu cần |
| 3 | Gõ "Hôm nay ăn trưa hết 35k" | Hai bên giống nhau, đều hiện thẻ xác nhận | Bộ định tuyến bảo thủ, không bao giờ coi lệnh ghi là câu hỏi |
| 4 | Chụp hoặc chọn cùng một hóa đơn | B1 xong sớm hơn khoảng một nửa thời gian; thanh token mất phần suy luận | thinkingLevel low: −30,8% token, −62,6% chi phí, độ chính xác giữ nguyên |
| 5 | Chọn lại đúng ảnh đó | B0 gọi mô hình lần nữa. B1 báo "đã nhập" ngay, 0 lượt gọi | Chặn trùng bằng SHA-256 trước khi gọi |
| 6 | Mở một hóa đơn có tổng tiền bị lệch (chuẩn bị sẵn kết quả lỗi) | B0 không cảnh báo. B1 tô vàng ô Tổng thanh toán | Hậu kiểm số học biến lỗi im lặng thành lỗi nhìn thấy được |
| 7 | Bật giả lập 9Router lỗi 429 (header `x-finmi-fault`) rồi hỏi 3 câu | B0 báo lỗi hoặc trả lời cục bộ cơ bản. B1 vẫn có câu trả lời, huy hiệu `↪ Gemini` | Circuit breaker + failover + hoàn quota |
| 8 | Chuyển sang slide chi phí | Bảng 100/200 người dùng: 147 → 55 USD/tháng (→ ~27 USD nếu dùng 3.8 Flash) | Bài toán chi phí đặt ra ban đầu đã được trả lời bằng số |

**Slide nên có sẵn:**
1. Cột chồng cơ cấu token B0 so với B1.
2. Biểu đồ hộp (box plot) độ trễ 30 ảnh B0 so với B1, có vạch đỏ ở mốc timeout 30 s. Hình này cho thấy B0 nằm sát ngưỡng timeout.
3. Sơ đồ luồng chat 3 lượt so với 0/1 lượt.
4. Bảng chi phí.

### 5.3. Rủi ro khi demo và phương án dự phòng

- **Hết quota Gemini hoặc Gemini chậm:** dùng key trả phí; quay sẵn video cả 8 cảnh; chạy thử trước buổi trình bày 1 tiếng.
- **Mạng phòng học yếu:** cảnh 1, 3 và 5 vẫn chạy được vì xử lý trên máy. Có thể phát mạng từ điện thoại.
- **Dữ liệu demo bị thay đổi:** dùng tài khoản riêng cho demo, nạp sẵn dữ liệu mẫu, không dùng tài khoản đang test.
- **Hai bản đọc nhầm bộ cờ:** kiểm tra nhãn B0/B1 trên overlay trước khi bắt đầu.

### 5.4. Câu hỏi thầy có thể hỏi và hướng trả lời

| Câu hỏi | Ý trả lời (có số liệu hoặc nguồn) |
|---|---|
| Sao dùng Gemini 3.6 mà không dùng 3.8 hay Gemini 4? | 3.8 Flash: đã thử, xem kết quả P1. Gemini 4 Argon: model frontier, đắt hơn, chưa phát hành rộng, không phù hợp cho tác vụ trích xuất |
| Sao Flutter 3.47 mà không phải 3.50, Android API bao nhiêu? | Mục 4 |
| Router bằng luật thì có gì mới? Sao không dùng router học máy như RouteLLM? | Router luật tất định chạy dưới 1 ms, không cần tải model, kiểm thử được bằng unit test và an toàn với lệnh ghi. Router học máy cần dữ liệu huấn luyện và thêm độ trễ. Nghiên cứu (Hybrid LLM, RouteLLM) chỉ ra nguyên tắc chung; nhóm áp dụng nguyên tắc đó vào ràng buộc của mobile |
| 30 ảnh có đủ không? | So sánh theo cặp, 30/30 ảnh giảm token, 27/30 ảnh nhanh hơn, không ảnh nào đổi đúng/sai. p95 chỉ mang tính mô tả (đã ghi rõ trong báo cáo) |
| thinking low có rủi ro với hóa đơn khó không? | Có hậu kiểm O5 và từ chối khi gặp `MAX_TOKENS`. Ở B0 lại có nhiều ca timeout hơn (7 so với 2) |
| Thu nhỏ ảnh có giảm token không? | Không. Đã đo được −2,3%, đúng với tài liệu Gemini (token ảnh do `media_resolution` quyết định). Đây là phát hiện nhóm chủ động báo cáo |
| Prompt caching thì sao? | Ngưỡng implicit cache của Gemini 3.6 Flash là 4.096 token, prompt hiện ngắn hơn nên chưa áp dụng được. Đã sắp xếp prompt sẵn để dùng khi đủ ngưỡng |
| Tối ưu này "di động" ở chỗ nào? | Offloading thiết bị–đám mây, giảm request mạng, giảm byte tải lên, xử lý trong isolate, (P2) bộ nhớ theo giới hạn mới của Android 17 |

---

## 6. Lịch đề xuất (tính từ hôm nay)

| Ngày | Việc |
|---|---|
| N1 | P0.1–P0.3: tích hợp nhánh, thống nhất cờ, nối cờ cho TV1 |
| N2 | P0.4–P0.7: ghi đè cờ theo profile, gộp telemetry, chạy test, deploy dev |
| N3 | P1: đo chat 40 câu, failover, 3.8 Flash, `media_resolution`; làm AI Lab overlay song song |
| N4 | TV4 điền số liệu vào báo cáo; làm slide; quay video dự phòng; (P2 nếu còn thời gian) |
| N5 | Tổng duyệt demo, các thành viên viết lại phần của mình trong báo cáo bằng giọng văn riêng |

---

## Phụ lục: Prompt giao Claude Code cho bước tích hợp (P0)

> Repo Finmi tại `D:\app-quan-ly-tai-chinh`. Tạo nhánh `integration/ai-opt` từ `main` (69bc60a), merge lần lượt `origin/feat/tv3-ai-platform`, `origin/tv2-AN`, `origin/feat/tv1-ocr-optimization`. Không push lên `main`.
>
> Khi giải quyết xung đột:
> (1) Lấy hạ tầng của TV3 (`AiCallContext`, `generateAssistantJson`, `ai_platform.ts`, `AiTelemetry`) làm chuẩn.
> (2) Thống nhất cờ theo danh mục 10 cờ của TV3 (`ai.extract.thinking_low`, `ai.extract.image_1600`, `ai.extract.precheck_dedup`, `ai.extract.validator`, `ai.chat.local_router`, `ai.chat.merge_calls`, `ai.chat.prompt_v2`, `ai.classify.local`, `ai.router.failover`, `ai.telemetry.upload`), tất cả mặc định OFF. Giữ ràng buộc tên cờ dạng pattern `^[a-z][a-z0-9_.]{1,63}$` của TV2. Sửa migration TV3 để không thêm lại danh sách cố định. Thêm một migration mới xóa các cờ `ai.chat.skip_command`, `ai.chat.prefetch_facts`, `ai.chat.compact_prompt`. Trước khi sửa migration cũ, hỏi tôi xem các migration này đã được deploy lên project từ xa chưa.
> (3) Code TV2: `skip_command` và `prefetch_facts` dùng chung cờ `ai.chat.merge_calls`; H5 đọc `ctx.enabled("ai.chat.prompt_v2")` ở server, bỏ trường `promptVersion` từ client (hoặc server bỏ qua trường này, không trả 400); chuyển ghi số liệu từ `ChatMetricsRecorder` sang `AiTelemetry`.
> (4) Code TV1: O1/O3 đọc `ctx.enabled("ai.extract.thinking_low")` theo mẫu trong `docs/ai-optimization/tv3-nen-tang-ai.md`, giữ `AI_EXTRACT_THINKING_LOW`/`AI_EXTRACT_MAX_OUTPUT_TOKENS` làm override; O2, O4, O5 đọc cờ tương ứng ở client, khi cờ OFF phải chạy đúng hành vi gốc của `main`; gọi `AiTelemetry.instance.recordDuplicateBlocked` khi chặn trùng.
> (5) Thêm `--dart-define=AI_FLAG_PROFILE=b0|b1|server`, chỉ có tác dụng ở bản debug: client ép bộ cờ tương ứng và gắn header `x-finmi-flags` vào mọi lời gọi `ai-api`. Sửa `tool/run_dual_instances.ps1` để cổng 8080 chạy `b0`, cổng 8081 chạy `b1`.
>
> Cổng chất lượng:
> - `flutter analyze` sạch.
> - `flutter test` đạt toàn bộ.
> - `deno test` (Deno thật) cho `supabase/functions/_shared/`.
> - Test riêng xác nhận khi toàn bộ cờ OFF thì luồng chat gọi 3 lượt cho câu tra cứu và luồng OCR không đặt `thinkingConfig`.
>
> Không commit secrets. Báo lại danh sách xung đột đã giải quyết và các quyết định đã chọn.
