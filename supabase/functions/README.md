# Supabase Edge Functions

`ai-api` là backend AI tối giản của Quản lý Tài chính. Function nhận ba action:

- `chat`: trả lời câu hỏi dựa trên facts local và tỷ giá bên ngoài khi cần.
- `extract`: chuyển OCR text thành hóa đơn có cấu trúc.
- `classify`: phân loại merchant bằng bộ rule nhẹ, không tốn lượt Gemini.

Chat chỉ nhận facts tổng hợp đã whitelist. Facts chứa merchant, invoice ID, dòng
hóa đơn, kết quả tìm kiếm hoặc danh mục tùy chỉnh sẽ bị loại bỏ tại Edge Function;
lịch sử chỉ giữ tối đa 4 câu hỏi gần nhất và ẩn email, số điện thoại, mã số dài.
Các truy vấn dữ liệu local được trả lời ở thiết bị và không gọi function.

## Deploy

Không ghi API key vào file hoặc Git:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase secrets set GEMINI_API_KEY=your_gemini_key
supabase functions deploy ai-api
```

`verify_jwt = true` được khai báo trong `supabase/config.toml`, vì vậy app phải
đăng nhập Supabase mới gọi được AI online. Khi chưa đăng nhập hoặc mất mạng,
OCR ML Kit, SQLite và chatbot local vẫn hoạt động.

## Local smoke test

```bash
supabase functions serve ai-api --no-verify-jwt
```

Lệnh local cần Docker theo yêu cầu của Supabase CLI. Khi test local, đặt
`GEMINI_API_KEY` trong môi trường chạy function; không commit `.env`.
