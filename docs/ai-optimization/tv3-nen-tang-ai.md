# TV3 – Nền tảng AI: đo token, feature flags, bảo mật 9Router, failover

Bàn giao ngày 2026-11-12. Tài liệu này mô tả những gì đã làm cho các mã N1–N5, cách TV1/TV2 dùng chúng, và cách TV4 lấy số liệu B0/B1.

## 1. Tóm tắt thay đổi

| Mã | Nội dung | File chính |
| --- | --- | --- |
| N2 | Ghi token thực tế: Gemini `usageMetadata` (input, output, **thinking**, cached) và 9Router `usage` (prompt, completion, reasoning), payload bytes, số lượt gọi LLM, provider, `flag_set`, `request_id`. Có cả luồng OCR bất đồng bộ `ai-worker` (action `extract_job`). View SLO đếm thêm 4xx/429, p50, failover, hoàn quota. | `supabase/migrations/20261112100000_ai_optimization_platform.sql`, `supabase/functions/ai-api/index.ts`, `supabase/functions/ai-worker/index.ts` |
| N4 | 10 cờ `ai.*` trong `app_feature_flags`, mặc định **OFF** ở cả dev, staging và production (= B0). Server và client đánh giá rollout theo cùng một thuật toán. | migration trên, `supabase/functions/_shared/ai_platform.ts`, `lib/core/config/feature_flags.dart` |
| N3 | `AiTelemetry`: đếm lượt gọi cloud và LLM cho mỗi câu chat, tỉ lệ trả lời local, độ trễ end-to-end, số ảnh trùng bị chặn. Lưu local, xuất CSV, và upload lên `ai_client_events` khi bật `ai.telemetry.upload`. | `lib/core/monitoring/ai_telemetry.dart`, `lib/core/network/supabase_function_client.dart`, `chat_screen.dart` |
| N1 | 9Router chuyển sang `https://finmi.ddns.net/v1`. Chỉ nhận HTTPS và host trong allowlist; không còn log URL. | `ai_platform.ts`, `ai-api/index.ts`, `health/index.ts`, `docs/SECURITY.md` |
| N5 | Circuit breaker, failover 9Router → Gemini → `AI_DEGRADED` (app trả lời bằng `LocalChatAssistant`). Hoàn quota khi lỗi do nhà cung cấp. Có fault injection để test. | `ai-api/index.ts` (`generateAssistantJson`), migration (`refund_ai_quota`) |

## 2. Triển khai

```bash
supabase db push                                   # áp migration 20261112100000
supabase secrets set NINER_ROUTER_BASE_URL=https://finmi.ddns.net/v1
supabase secrets set NINER_ROUTER_ALLOWED_HOSTS=finmi.ddns.net
supabase secrets set AI_FLAG_ENVIRONMENT=dev       # khớp APP_ENV của bản app đang test (debug build = dev)
# Chỉ trên project dev/benchmark, KHÔNG bật ở production:
supabase secrets set AI_ALLOW_DEBUG_HEADERS=true   # cho phép x-finmi-flags / x-finmi-fault
supabase secrets set AI_EXPOSE_USAGE_META=true     # trả _meta (token, provider, llmCalls) trong response
supabase functions deploy ai-api
supabase functions deploy ai-worker
supabase functions deploy health
```

Các biến tùy chọn: `NINER_ROUTER_BREAKER_THRESHOLD` (mặc định 3 lỗi liên tiếp), `NINER_ROUTER_BREAKER_COOLDOWN_MS` (30000), `AI_FAILOVER_TIMEOUT_MS` (15000).

> ⚠️ `AI_FLAG_ENVIRONMENT` mặc định là `production`. Bản app debug đọc cờ ở `dev`. Nếu hai bên lệch nhau, server và client sẽ thấy hai bộ cờ khác nhau.

## 3. Bật/tắt cờ cho B0 và B1

```sql
-- B0: tắt toàn bộ
update public.app_feature_flags set enabled = false, updated_at = now()
where environment = 'dev' and key like 'ai.%';

-- B1: bật theo nhóm (ví dụ của TV3)
update public.app_feature_flags set enabled = true, updated_at = now()
where environment = 'dev' and key in ('ai.router.failover', 'ai.telemetry.upload');
```

Server cache cờ khoảng 30 giây cho mỗi isolate. App nạp lại cờ khi đăng nhập hoặc refresh.

| Cờ | Chủ | Bên đọc |
| --- | --- | --- |
| `ai.extract.thinking_low` | TV1 (O1+O3) | server |
| `ai.extract.image_1600` | TV1 (O2) | client |
| `ai.extract.precheck_dedup` | TV1 (O4) | client |
| `ai.extract.validator` | TV1 (O5) | client hoặc server |
| `ai.chat.local_router` | TV2 (H3) | client |
| `ai.chat.merge_calls` | TV2 (H2+H4) | client |
| `ai.chat.prompt_v2` | TV2 (H5) | server |
| `ai.classify.local` | TV2 (H8) | client |
| `ai.router.failover` | TV3 (N5) | server |
| `ai.telemetry.upload` | TV3 (N3) | client |

## 4. Hướng dẫn cho TV1 và TV2

**Phía server (`ai-api/index.ts`)**: mỗi hàm xử lý action đều nhận `ctx: AiCallContext`.

```ts
// TV1 – O1/O3 trong extractInvoice():
const parsed = await generateGeminiJson(ctx, prompt, invoiceSchema, 0.1, 30_000, image, {
  generationConfig: ctx.enabled("ai.extract.thinking_low")
    ? {thinkingConfig: {thinkingLevel: "low"}, maxOutputTokens: 4096}
    : {},
});

// TV2 – H5 trong answerChat():
const prompt = ctx.enabled("ai.chat.prompt_v2") ? buildChatPromptV2(request) : buildChatPromptV1(request);
```

Không cần tự ghi token: `generateGeminiJson`, `generateNinerRouterJson` và `generateAssistantJson` đã cộng dồn usage vào `ctx`. Chat, `assistant_command` và `draft_transaction` nên gọi qua `generateAssistantJson` để có failover.

**Phía client**:

```dart
final flags = ref.watch(featureFlagsProvider).value ?? FeatureFlags.defaults;
if (flags.isAiEnabled(AiOptimizationFlag.chatLocalRouter)) { ... }

AiTelemetry.instance.recordDuplicateBlocked(payloadBytes: bytes.length); // TV1 – O4, khi chặn ảnh trùng
AiTelemetry.instance.recordLocal('classify');                            // TV2 – H8, khi phân loại trên máy
```

Mọi lời gọi `ai-api` qua `SupabaseFunctionClient` đều được đếm tự động. Mỗi lần người dùng gửi chat là một `chat_turn`: số `llmCalls` (M6), `route` local/cloud/fallback (M7), `durationMs` từ lúc bấm gửi đến lúc hiện câu trả lời (M9).

## 5. Truy vấn số liệu cho TV4 (chạy bằng service role / SQL editor)

```sql
-- M1, M2, M3, M8: token, payload, độ trễ theo action và bộ cờ (B0: flag_set = 'none')
select * from public.ai_request_benchmark
where action in ('extract', 'extract_job', 'chat', 'assistant_command')
order by action, flag_set;

-- M10: tỉ lệ hoàn tất khi 9Router lỗi, số lần failover, số lần hoàn quota
select report_day, action, request_count, success_rate_percent, rate_limited_count,
       failover_count, failover_success_count, quota_refund_count
from public.ai_request_slo_daily order by report_day desc, action;

-- M6, M7, M9 phía client (khi bật ai.telemetry.upload)
select * from public.ai_client_benchmark where feature = 'chat' and event = 'chat_turn';

-- Ảnh trùng bị chặn trước khi gọi API (M10)
select flag_set, count(*) from public.ai_client_events
where event = 'dedup_blocked' group by flag_set;
```

Nếu chưa bật upload, `AiTelemetry.instance.exportCsv()` trả CSV và `AiTelemetry.instance.summarize()` trả M6, M7, M9 ngay trên thiết bị. Sự kiện cũng được ghi ra `developer.log` với name `hoadon_insight.ai_telemetry`.

Khi chạy `tool/eval_finmi_ai.mjs` trên project dev (đã bật `AI_ALLOW_DEBUG_HEADERS`), có thể đổi cấu hình theo từng request mà không phải sửa DB:

```
x-finmi-flags: ai.router.failover=1,ai.chat.prompt_v2=1
```

Đọc `response._meta` (khi bật `AI_EXPOSE_USAGE_META`) để lấy `inputTokens`, `outputTokens`, `thinkingTokens`, `llmCalls`, `provider`, `failover` cho từng request.

## 6. Kịch bản test failover 429 (M10)

1. Bật `ai.router.failover` (hoặc gửi header `x-finmi-flags: ai.router.failover=1`).
2. Gửi 10 câu chat với header `x-finmi-fault: 429` (các giá trị khác: `500`, `timeout`). Cũng có thể đặt secret `NINER_ROUTER_FAULT_INJECT=429` để giả lập cho cả app.
3. Kỳ vọng:
   - Cả 10 request trả 200, `_meta.provider = "gemini"` và `failover = true`.
   - Sau 3 lỗi liên tiếp, circuit mở: log có `niner_router_circuit_open` và request đi thẳng sang Gemini, không chờ 9Router.
4. Bỏ thêm `GEMINI_API_KEY` trên project test (hoặc để Gemini cũng lỗi). Kỳ vọng:
   - Response 503 `AI_DEGRADED`, app trả lời bằng `LocalChatAssistant`.
   - `ai_request_metrics.quota_refunded = true`, `ai_cost_usage` không tăng.
5. So sánh với B0 (cờ OFF, cùng fault): response 429 `MODEL_RATE_LIMITED`. App vẫn rơi về local nhờ catch sẵn có, nhưng **quota vẫn được hoàn** (hoàn quota không phụ thuộc cờ).

## 7. Giới hạn đã biết (đưa vào báo cáo)

- Circuit breaker chạy trong từng isolate Edge Function, không chia sẻ trạng thái giữa các isolate. Muốn breaker phân tán thì cần lưu trạng thái trong Postgres hoặc Redis (Chương 7).
- Khi failover, chat dùng `toolCall` trong JSON schema của Gemini thay cho OpenAI function calling. Chất lượng chọn tool khi failover cần đo riêng trên bộ 40 câu.
- Payload bytes phía client được ước lượng bằng tổng độ dài các trường chuỗi (base64 chiếm phần lớn), không phải số byte chính xác trên dây.
- Tỉ lệ thinking token của 9Router phụ thuộc việc router có trả `completion_tokens_details.reasoning_tokens` hay không.
