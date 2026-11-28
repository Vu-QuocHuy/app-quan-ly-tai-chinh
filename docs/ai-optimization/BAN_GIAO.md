# Bàn giao tích hợp tối ưu AI Finmi (28/11/2026)

Nhánh `integration/ai-opt` gộp ba nhánh **TV3 (nền tảng) → TV2 (chat) → TV1 (OCR)** và thêm bộ công cụ demo/đo của TV4. Tài liệu này nói rõ: đã có gì, mỗi người cần làm gì tiếp, kiểm bằng cách nào, và những điểm cần quyết định.

> **Trạng thái nhánh:** `integration/ai-opt` hiện chỉ có trên máy của TV4. Cần TV4 đẩy lên remote (hoặc mở PR draft) thì mọi người mới lấy được. Mọi lệnh bên dưới giả định đã `git switch integration/ai-opt`.

Kế hoạch gốc: [`docs/superpowers/plans/2026-11-27-ai-optimization-finalization-demo.md`](../superpowers/plans/2026-11-27-ai-optimization-finalization-demo.md) (có bảng tiến độ và mục "Quyết định"). Kịch bản demo: [`demo-runbook.md`](demo-runbook.md).

---

## 1. Chạy thử trong 5 phút

```bash
flutter pub get
flutter analyze                       # phải "No issues found"
flutter test                          # phải đạt toàn bộ
deno test --allow-env supabase/functions/_shared/
deno test --allow-read tool/benchmark/failover_test.ts
python -m unittest discover -s tool/benchmark
python -m unittest discover -s tool/demo
```

Chạy hai bản cạnh nhau (cần `config/supabase.local.json`, không commit file này):

```powershell
powershell tool/run_dual_instances.ps1   # 8080 = B0 (gốc), 8081 = B1 (tối ưu)
```

Hai bản khác nhau **chỉ** ở `--dart-define=AI_FLAG_PROFILE=b0|b1`. Banner trên cùng hiện `B0 – GỐC` (đỏ) hoặc `B1 – TỐI ƯU` (xanh). Nếu hiện **`LỆCH CỜ`** (vàng) nghĩa là bộ cờ client khác bộ cờ server đã đánh giá: kiểm `AI_FLAG_ENVIRONMENT` (phải là `dev`) và `AI_ALLOW_DEBUG_HEADERS=true`.

Các giá trị `AI_FLAG_PROFILE`: `server` (mặc định, dùng cờ trong DB), `b0` (tắt hết), `b1` (bật hết 10 cờ), `only:ai.chat.local_router,ai.chat.merge_calls` (chỉ bật các cờ liệt kê). Chỉ có tác dụng ở bản debug.

---

## 2. Cái gì đã thay đổi trong phần của bạn

### TV3 (nền tảng)
- `generateGeminiJson(ctx, …)` giữ nguyên hợp đồng (trả `JsonObject`). Thêm `ctx.geminiUsageMetadata` (usage thô của Gemini) để benchmark của TV1 vẫn đọc được `usageMetadata`.
- `generateAssistantJson`/`generateNinerRouterJson` nhận thêm tham số cuối `maxTokens?` (của TV2) và `retryServerErrors` (của bạn): chữ ký cuối `(ctx, prompt, schema, temperature, timeoutMs, image?, tools?, retryServerErrors = true, maxTokens?)`.
- **Migration:** file `20261112100000_ai_optimization_platform.sql` đã sửa: ràng buộc tên cờ dùng pattern thay vì danh sách cố định. Thêm `20261128100000_ai_flags_unify.sql` (xóa 3 cờ cũ của TV2, ép **cả 10 cờ về TẮT**). Lý do: TV2 chèn `ai.chat.local_router` và `ai.classify.local` ở trạng thái BẬT, TV3 chèn lại bằng `on conflict do nothing` nên hai cờ này vẫn BẬT, và mặc định không còn là B0. Đã kiểm trên Postgres 16: DB sạch, chạy hai lần, và TV3 deploy trước TV2.
- `AiTelemetry.stream` (luồng sự kiện) mới. `ai-worker` (đường job) **chưa gate bằng cờ** (app hiện không dùng đường job; OCR đi qua `extract` đồng bộ).

### TV2 (chat)
- Cờ của bạn đổi tên theo danh mục TV3: `skip_command` + `prefetch_facts` → `ai.chat.merge_calls`; `compact_prompt` → `ai.chat.prompt_v2`; `local_router`, `classify.local` giữ tên. **Mặc định giờ là TẮT** (B0).
- Prompt chọn ở **server** theo `ctx.enabled("ai.chat.prompt_v2")`. Client không còn gửi `promptVersion` (server vẫn chấp nhận và bỏ qua, không trả 400). Đã kiểm: prompt `legacy` giống `main` 24/24 dòng đầu, dòng cuối chỉ khác cách viết.
- Các test chat của bạn giờ bật cờ tường minh (`_chatOptimized` trong `chat_screen_test.dart`); test B0 dùng `FeatureFlags()`.
- `ChatMetricsRecorder` **được giữ** (nhãn đường đi `ChatRoute`), thêm `turns` (stream) và chuyển phần H8 sang `AiTelemetry`.

### TV1 (OCR)
- O1: `thinking_low` giờ đọc `ctx.enabled("ai.extract.thinking_low")` **hoặc** biến `AI_EXTRACT_THINKING_LOW` (override). Bật chỉ thêm `thinkingLevel: low`, **không có trần output** (đúng cấu hình bạn đã đo −30,8%). Trần là tùy chọn qua `AI_EXTRACT_MAX_OUTPUT_TOKENS`. Từ chối `MAX_TOKENS` giờ áp cho mọi lời gọi Gemini.
- O2 `ai.extract.image_1600`, O4 `ai.extract.precheck_dedup`, O5 `ai.extract.validator` đều **sau cờ**; tắt = hành vi `main` (có test cả hai chiều trong `receipt_image_optimizer_test.dart` và `import_coordinator_test.dart`).
- `extract` đi qua `extractOnce(ctx, input)` của bạn: claim theo `requestId` → quota → Gemini. **Server luôn gọi RPC `ocr_replay` kể cả B0** (thêm 2 lời gọi nhỏ) và trả 503 `OCR_REPLAY_UNAVAILABLE` nếu migration `20261122000000` chưa áp.
- Mới: `GEMINI_MODEL` (mặc định `gemini-3.6-flash`) và `AI_EXTRACT_MEDIA_RESOLUTION` (`low|medium|high`, mặc định không đặt = request giống `main`).

---

## 3. Việc của từng người

### TV3 — nền tảng, deploy, failover
- [ ] **Xác nhận migration đã deploy chưa** (`supabase migration list`) và đồng ý với migration `20261128100000_ai_flags_unify.sql`. Nếu vẫn có phiên bản lạ `20261020190000` (TV1 báo): `supabase migration repair --status reverted 20261020190000`.
- [ ] **Deploy project dev, đúng thứ tự:**
  1. `supabase db push` (migration TV1 `20261122000000` phải lên **trước** function, nếu không OCR 503).
  2. Secrets: `AI_FLAG_ENVIRONMENT=dev`, `AI_ALLOW_DEBUG_HEADERS=true`, `AI_EXPOSE_USAGE_META=true`, `NINER_ROUTER_BASE_URL`, `NINER_ROUTER_ALLOWED_HOSTS`, `GEMINI_API_KEY` (**key trả phí**, key miễn phí 20 request/ngày sẽ làm hỏng cả đo lẫn demo).
  3. `supabase functions deploy ai-api ai-worker health`.
  4. Kiểm: SQL `select environment, count(*) filter (where enabled) from app_feature_flags where key like 'ai.%' group by 1;` → mỗi môi trường **0 cờ bật**; `GET health` = 200; gọi `chat` với header `x-finmi-flags: ai.chat.prompt_v2=1` thì `_meta.flagSet` chứa `ai.chat.prompt_v2`.
- [ ] **Chạy kịch bản failover (T3.4):**
  ```bash
  FINMI_AI_URL=<ai-api> FINMI_AI_ACCESS_TOKEN=<jwt tài khoản test> FINMI_AI_PUBLISHABLE_KEY=<anon key> \
  deno run --allow-env --allow-net --allow-read --allow-write \
    tool/benchmark/failover.ts --out docs/ai-optimization/data/failover.csv
  ```
  Kỳ vọng: cờ OFF → 10/10 trả 429 `MODEL_RATE_LIMITED`; cờ ON → 10/10 trả 200 với `provider=gemini`, `failover=true`, và các request từ thứ 4 nhanh hơn 3 request đầu (mạch mở). Script thoát mã ≠ 0 nếu sai. Sau đó thử Gemini cũng lỗi (đặt `GEMINI_API_KEY` sai **trên project nháp, không phải project demo**): kỳ vọng 503 `AI_DEGRADED`, `quota_refunded = true`; ghi lại cả huy hiệu `⚠ CỤC BỘ (AI_DEGRADED)` trong app.
- [ ] **Review phần merge ở `ai-api/index.ts`** (nhất là `extractOnce`, `ctx.geminiUsageMetadata`, `maxTokens`); quyết định có gate `ai-worker` bằng cờ không.
- [ ] Giúp TV4 tạo **hai tài khoản demo** `demo-b0`, `demo-b1` và chạy `tool/demo/seed_demo_account.sql` (xem `tool/demo/README.md`; SQL **chưa được chạy thử trên DB thật**, hãy chạy trên project nháp trước).
- **Xong khi:** dev deploy chạy, `failover.csv` có 20 dòng và script báo `failover check passed`, số liệu đưa vào Bảng 6.5.

### TV1 — OCR
- [ ] **Review nhánh tích hợp** (mục 2) và xác nhận B0 = `main`: với `AI_FLAG_PROFILE=b0` ảnh gửi lên giữ ≤2 MB nguyên, >2 MB resize 2048 px, và request Gemini **không** có `thinkingConfig`.
- [ ] **Chạy lại 5 ảnh trên bản tích hợp** (profile `b1`, dev đã deploy) và so với số cũ: tổng 30/30, ngày 29/30. Báo nếu lệch.
- [ ] **T3.5 — Gemini 3.8 Flash so với 3.6 Flash.** Server: đặt secret `GEMINI_MODEL=gemini-3.8-flash`, deploy lại, giữ `thinking_low` bật, chạy lại 30 ảnh bằng `tool/benchmark_tv1_receipts.py` như `tool/README_tv1_benchmark.md` (đặt `--variant` rõ ràng, file output mới). **Quy tắc chấp nhận:** tổng đúng không dưới 30/30 và ngày không dưới 29/30, chi phí/ảnh thấp hơn. Lưu `docs/ai-optimization/data/ocr_model_compare.csv`; nếu chấp nhận, tính lại chi phí 200 người dùng (kỳ vọng ≈ 27 USD/tháng, ghi số thật).
- [ ] **T3.6 — `media_resolution`.** **Trước hết kiểm tài liệu Gemini hiện hành** xem tham số nằm ở `generationConfig.mediaResolution` hay ở từng phần ảnh (model 3.x); code hiện đặt ở `generationConfig` dưới dạng `MEDIA_RESOLUTION_MEDIUM`. Nếu sai chỗ, sửa trong `supabase/functions/_shared/extract_config.ts` (có test Deno). Đặt `AI_EXTRACT_MEDIA_RESOLUTION=medium`, chạy 30 ảnh với thinking low, so token ảnh và độ chính xác.
- [ ] **Gửi TV4 dữ liệu độ trễ từng ảnh** (`b0.jsonl`, `b1.jsonl` trong `artifacts/tv1/`, thư mục này bị gitignore nên không có trong repo) để vẽ box plot: `python tool/benchmark/make_charts.py --latency-b0 <file> --latency-b1 <file>`.
- [ ] (P2, nếu còn thời gian) đo bộ nhớ và thời gian `ReceiptImageOptimizer` trên 5 ảnh camera 12 MP bằng bản profile.
- **Xong khi:** hai thử nghiệm có CSV, quyết định (giữ 3.6 hay 3.8; có dùng `media_resolution` không) được ghi vào mục "Quyết định" của plan, và đã gửi dữ liệu độ trễ.

### TV2 — chat
- [ ] **Sửa lỗi router "thu nhập".** `ChatRoutingRules._writeMarkers` có ` nhap ` (nghĩa "nhập"), nên "Thu nhập tháng này bao nhiêu?" bị coi là lệnh ghi và **không bao giờ đi đường cục bộ** (B1 mất tối ưu, và demo hỏi đúng câu này sẽ thấy B1 vẫn gọi mô hình). Gợi ý: che cụm "thu nhập" trước khi so từ khóa ghi. Sau khi sửa: đổi Q34 trong `tool/benchmark/chat_questions_40.json` thành `expected_route_b1: "local"` (và copy sang `assets/ai_lab/chat_questions_40.json`); test `test/features/chat/chat_questions_routing_test.dart` sẽ báo đúng chỗ cần đổi.
- [ ] **Kiểm nhóm "từ chối" ở B1** (Q35–Q40). Phần lớn bị `ChatPrivacyPolicy` chặn ở client trước khi định tuyến, nhưng "Neural Network là gì?" và các câu tương tự có thể đi thẳng vào `chat` mà không qua `assistant_command` (nơi B0 trả `reject`). Cả 6 câu phải bị từ chối và không lộ khóa/prompt; nếu không, đây là hồi quy an toàn cần sửa trước khi đưa số vào báo cáo.
- [ ] **T3.3 — Đo 40 câu × 4 cấu hình.** Giao thức:
  1. Dev đã deploy (TV3), đăng nhập **tài khoản demo đã seed và reset** (`tool/demo/README.md`), nhập tay 3 khoản nợ (Q04/Q33 phụ thuộc, nợ chỉ lưu trên máy).
  2. Chạy lần lượt bốn lệnh (mỗi lần mở app, **mở màn Chat**, vào bảng AI Lab, mục "Chạy 40 câu", chọn "3 lần", bấm "Chạy", chờ đủ, "Sao chép CSV", lưu vào `docs/ai-optimization/data/chat_<tên>.csv`):
     ```
     --dart-define=AI_FLAG_PROFILE=b0
     --dart-define=AI_FLAG_PROFILE=only:ai.chat.local_router
     --dart-define=AI_FLAG_PROFILE=only:ai.chat.local_router,ai.chat.merge_calls
     --dart-define=AI_FLAG_PROFILE=b1
     ```
     (kèm `--dart-define=AI_LAB=true --dart-define=APP_ENV=dev --dart-define-from-file=config/supabase.local.json`). Chờ ~30 giây giữa các cấu hình để cache cờ server hết hạn.
  3. Tổng hợp: `python tool/benchmark/summarize_chat.py docs/ai-optimization/data/chat_*.csv`.
  4. M8 (token mỗi câu) từ SQL: `select * from public.ai_request_benchmark where action in ('chat','assistant_command') order by action, flag_set;` → `docs/ai-optimization/data/chat_tokens.csv`.
  5. **Điều kiện dừng:** nếu `Lệnh ghi bị định tuyến nhầm` > 0, hoặc tỉ lệ `Trả lời đúng` ở B1 thấp hơn B0, **dừng và sửa**, không đưa số vào báo cáo.
- [ ] Sau khi có dữ liệu thật, điền `assets/ai_lab/pricing.json` mục `chat_baseline_b0` (token trung bình mỗi lượt gọi LLM ở B0) để overlay tính tiền tiết kiệm của chat.
- **Xong khi:** 4 file CSV + bảng tổng hợp M6/M7/M9 + M8, router đã sửa, và 6 câu từ chối đã kiểm.

### Trang điều khiển một-màn-hình (tùy chọn)

`powershell tool/run_dual_instances.ps1` còn bật một máy chủ tĩnh ở cổng 8090 và mở `http://localhost:8090/`: một tab chứa **hai iframe** (B0 trái, B1 phải) và một thanh nút gửi cùng một lệnh cho cả hai (câu hỏi có sẵn, lỗi giả lập 429/500/timeout, bóp méo tổng, hóa đơn mẫu 1/2, reset; mục "Gửi cho" chọn cả hai hoặc một bên). Nếu không dùng được, hai tab 8080/8081 vẫn chạy bình thường.

Giao tiếp bằng `postMessage` (chỉ nhận từ `http://localhost:8090`), cùng 5 lệnh `ask|fault|importAsset|tamper|reset`; test hợp đồng `python tool/demo/controller/test_controller_contract.py` bảo đảm trang HTML và bộ phân tích Dart không lệch nhau. **Chưa thử trong trình duyệt thật**: người đầu tiên chạy hãy kiểm các điểm sau và ghi lại kết quả:
- iframe có hiển thị được app Flutter không (dev server có thể chặn nhúng);
- bấm "Gửi cho: Cả hai" thật sự làm cả hai bản trả lời;
- sau khi tải lại một bản, công tắc lỗi giả lập/bóp méo của bản đó trở về mặc định trong khi radio của trang điều khiển giữ giá trị cũ (cần bấm lại).

### Bảng điều khiển AI Lab trong app

Bật bằng `--dart-define=AI_LAB=true` (bản debug). Hiện ở góc màn hình: banner cấu hình, huy hiệu dưới mỗi câu trả lời của chat (`⚡ TRÊN MÁY · 0 lượt · 40 ms`, `☁ ĐÁM MÂY`, `↪ DỰ PHÒNG: Gemini`, `⚠ CỤC BỘ (AI_DEGRADED)`), thanh token OCR (đầu vào / suy luận / đầu ra), bộ đếm lượt gọi/token/tiết kiệm, rồi bảng điều khiển: 3 câu hỏi có sẵn, "Lỗi giả lập" (Không/429/500/timeout), công tắc "Bóp méo tổng hóa đơn (lỗi mô phỏng)", "Hóa đơn mẫu 1/2", "Reset", và mục "Chạy 40 câu". Hai hóa đơn mẫu là ảnh tổng hợp (`assets/ai_lab/receipt_normal.png`, `receipt_repeat.png`, sinh bằng `tool/ai_lab/make_sample_receipts.py`), không chứa dữ liệu cá nhân. "Reset" chỉ xóa số liệu AI Lab, telemetry và lịch sử chat cục bộ; **không** xóa hóa đơn hay thu nhập.

Chưa kiểm trực tiếp trong app (chỉ có test đơn vị/widget): nút "Hóa đơn mẫu" đi qua đường nhập ảnh của `AppShell`, bố cục overlay trên màn hình nhỏ, và bộ chạy 40 câu với màn Chat thật (thứ tự sự kiện: số liệu lượt chat → telemetry `chat_turn` → câu trả lời; nếu lệch thứ tự thì `contains_expected` sẽ ra `false`).

---

## 4. Việc còn lại của TV4 (không giao cho người khác)

- Đẩy `integration/ai-opt` lên remote / mở PR draft (cần quyết định của TV4; chưa làm vì là việc hướng ra ngoài).
- Điền `assets/ai_lab/pricing.json` từ **Bảng 6.6** của báo cáo (`vnd_per_usd`, `usd_per_million_tokens.input/output`). Để `null` thì AI Lab ẩn dòng chi phí.
- Chạy 8 cảnh bằng tay (T2.7) sau khi TV3 deploy dev; làm `fvm`/Flutter 3.47.8 (T4.1) và Android API (T4.2); điền báo cáo, slide, video dự phòng (T5.3–T5.6).

---

## 5. Ghi chú và rủi ro đã biết

| Vấn đề | Chi tiết |
|---|---|
| Nợ không có trong cloud | Lưu trong SharedPreferences theo trình duyệt. Hai bản demo phải **nhập tay cùng 3 khoản nợ**. |
| Hai tài khoản demo | Mỗi bản một tài khoản riêng (`demo-b0`, `demo-b1`) với dữ liệu giống hệt; dùng chung một tài khoản thì ảnh nhập ở B0 sync sang B1 và cảnh "chặn trùng" sai. |
| Cảnh 6 (tổng lệch) | Là **lỗi mô phỏng**: công tắc "Bóp méo tổng hóa đơn" tăng 10% tổng sau khi mô hình đọc. Phải nói rõ khi demo. Dùng ảnh chưa nhập trong buổi (ảnh ở cảnh 4–5 bị chặn trùng ở B1 nên không có kết quả để bóp méo). |
| SQL seed/reset | Viết từ migration và code, **chưa chạy trên DB thật**. Chạy trên project nháp trước. |
| Số `forecast`/`scenario` | Phụ thuộc ngày chạy; trong `tool/demo/seed_expectations.json` đánh dấu `MANUAL`. Seed chỉ đúng khi chạy trong tháng 11/2026 (xem README của seed). |
| `ai-worker` | Có `generationConfig` riêng, không gate bằng cờ; chỉ ảnh hưởng nếu sau này app dùng đường job. |
| Cờ B1 | `b1` bật cả `ai.telemetry.upload` và `ai.router.failover` (10/10 cờ). |
| Việc đã kiểm | `flutter analyze` sạch; test Flutter, Deno, Python đạt; `deno check` cả 3 function; migration cờ trên Postgres 16. **Chưa chạy** trên project Supabase thật hay trình duyệt thật. |
