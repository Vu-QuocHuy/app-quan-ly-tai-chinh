# Giao thức AI Lab: trang điều khiển ↔ hai app Flutter web

Mục tiêu: một tab điều khiển (`http://localhost:8090/`) hiển thị **hai khung điện thoại** (B0 ở `:8080`, B1 ở `:8081`) và bật/tắt **từng kỹ thuật tối ưu** trên mỗi khung khi đang chạy; một **trang số liệu realtime** (`http://localhost:8090/metrics.html`, mở ở tab/cửa sổ khác) hiển thị số đo của cả hai.

Mọi thứ chỉ hoạt động ở bản debug có `--dart-define=AI_LAB=true`. Mọi thông điệp là một object JS có `ailab: 1`.

## 1. Lệnh: trang điều khiển → app (`window.postMessage` vào iframe)

App chỉ nhận lệnh từ `http://localhost:8090` và `http://127.0.0.1:8090`. Bộ phân tích: `parseAiLabMessage` trong `lib/features/ai_lab/data/ai_lab_bridge.dart`.

| `cmd` | `value` | Tác dụng |
|---|---|---|
| `ask` | chuỗi 1..500 ký tự | gửi câu hỏi vào màn Chat |
| `fault` | `null`, `"429"`, `"500"` hoặc `"timeout"` | tiêm lỗi 9Router (`x-finmi-fault`) |
| `importAsset` | `"assets/ai_lab/receipt_normal.png"` hoặc `receipt_repeat.png` (phải bắt đầu `assets/ai_lab/`, không có `..` hay `\`) | nhập hóa đơn mẫu |
| `tamper` | `true` / `false` | bóp méo tổng hóa đơn (lỗi mô phỏng) |
| `reset` | (bỏ qua) | xóa số liệu AI Lab, telemetry, lịch sử chat cục bộ |
| **`flags`** (mới) | `"b0"`, `"b1"` hoặc object `{ "<khóa cờ>": true/false, ... }` | đặt cờ tối ưu của app **đang chạy** (xem mục 3) |
| **`hello`** (mới) | (bỏ qua) | yêu cầu app gửi ngay một thông điệp `metrics` (trang điều khiển dùng khi vừa tải xong) |

## 2. Sự kiện: app → trang điều khiển (`window.parent.postMessage`, targetOrigin `http://localhost:8090`)

Chỉ gửi khi app chạy trong iframe (`window.parent !== window`). Gửi một thông điệp `metrics` (a) ngay khi khởi động, (b) mỗi khi `AiLabStore` hoặc bộ cờ đổi, giới hạn **tối đa 4 lần/giây**, (c) khi nhận `hello`.

```json
{
  "ailab": 1,
  "event": "metrics",
  "ts": 1764300000000,
  "launchProfile": "b0",
  "profile": "b0 | b1 | custom | server",
  "enabledCount": 3,
  "flagSet": "ai.chat.local_router,ai.chat.merge_calls",
  "flags": { "ai.extract.thinking_low": false, "...": true },
  "serverFlagSet": "none | <danh sách> | null",
  "totals": {
    "llmCalls": 12, "tokens": 18450, "savedLlmCalls": 9,
    "costUsd": 0.0, "savedUsd": 0.0, "savedOcrCalls": 1
  },
  "lastExtract": {
    "inputTokens": 2094, "thinkingTokens": 0, "outputTokens": 191,
    "durationMs": 7022, "provider": "gemini"
  },
  "turns": [
    { "messageId": "…", "route": "local | cloud | fallback | degraded",
      "llmCalls": 0, "durationMs": 40, "provider": null }
  ],
  "calls": [
    { "action": "chat", "durationMs": 2100, "llmCalls": 1,
      "provider": "9router", "failover": false,
      "inputTokens": 900, "outputTokens": 120, "thinkingTokens": null }
  ]
}
```

- `lastExtract` là `null` khi chưa có lần đọc hóa đơn nào có token; mọi trường số có thể `null` (server không bật `AI_EXPOSE_USAGE_META`).
- `turns`: tối đa 20 lượt gần nhất (cũ → mới). `calls`: tối đa 30 lời gọi `ai-api` gần nhất (cũ → mới).
- `flags` luôn đủ 10 khóa của `AiOptimizationFlag`.
- `profile`: `b0` khi 0/10 cờ bật, `b1` khi 10/10, `custom` ở giữa, `server` khi chưa có ghi đè nào và `AI_FLAG_PROFILE=server`.
- `serverFlagSet` khác `flagSet` (khi đã biết) nghĩa là **lệch cờ** (ví dụ server dev chưa bật `AI_ALLOW_DEBUG_HEADERS`).

## 3. Ghi đè cờ lúc chạy

- Trong bản debug có AI Lab, app giữ một **tập cờ ghi đè** (khởi tạo từ `AI_FLAG_PROFILE`; `server` nghĩa là chưa ghi đè). Lệnh `flags` thay đổi tập này; khóa vắng mặt giữ nguyên giá trị hiện tại; `"b0"`/`"b1"` đặt tất cả.
- Cờ phía client (`local_router`, `merge_calls`, `classify.local`, `image_1600`, `precheck_dedup`, `validator`, `telemetry.upload`) có hiệu lực ngay ở thao tác kế tiếp.
- Cờ phía server (`thinking_low`, `prompt_v2`, `failover`) có hiệu lực qua header `x-finmi-flags` gắn vào **mọi** lời gọi `ai-api` (header luôn liệt kê đủ 10 cờ). Cần `AI_ALLOW_DEBUG_HEADERS=true` ở server dev; nếu không, banner báo `LỆCH CỜ`.
- Đổi cờ **không** xóa số liệu đã đo (muốn đo lại thì bấm Reset).

## 4. Tên hiển thị của 10 cờ (dùng thống nhất ở app và các trang web)

| Khóa | Nhóm | Tên hiển thị | Ở đâu |
|---|---|---|---|
| `ai.extract.thinking_low` | Đọc hóa đơn | Giảm suy luận của AI | server |
| `ai.extract.image_1600` | Đọc hóa đơn | Thu nhỏ ảnh về 1600 px | máy |
| `ai.extract.precheck_dedup` | Đọc hóa đơn | Chặn ảnh trùng trước khi gọi AI | máy |
| `ai.extract.validator` | Đọc hóa đơn | Hậu kiểm số học hóa đơn | máy |
| `ai.chat.local_router` | Chat | Trả lời câu tra cứu trên máy | máy |
| `ai.chat.merge_calls` | Chat | Gộp lượt gọi chat | máy |
| `ai.chat.prompt_v2` | Chat | Prompt chat rút gọn | server |
| `ai.classify.local` | Chat | Phân loại cửa hàng trên máy | máy |
| `ai.router.failover` | Nền tảng | Dự phòng 9Router → Gemini | server |
| `ai.telemetry.upload` | Nền tảng | Gửi telemetry lên server | máy |

Nút nhanh: **Tắt hết (B0 – GỐC)** = `"b0"`, **Bật hết (B1 – TỐI ƯU)** = `"b1"`.

## 5. Trang số liệu realtime

Trang điều khiển (`:8090`) nhận `metrics` từ hai iframe (xác định bên nào theo `event.origin`: `:8080` → B0, `:8081` → B1) rồi phát lại qua `BroadcastChannel("finmi-ailab")` (cùng origin `:8090`) để `metrics.html` ở tab khác hiển thị. Trang số liệu chỉ đọc, không gửi lệnh.

Thông điệp trên kênh: `{ "ailab": 1, "pane": "b0" | "b1", "metrics": <đối tượng metrics ở mục 2>, "receivedAt": <epoch ms> }`. Trang số liệu gửi `{ "ailab": 1, "request": "snapshot" }` khi mở để trang điều khiển phát lại thông điệp mới nhất của mỗi bên.
