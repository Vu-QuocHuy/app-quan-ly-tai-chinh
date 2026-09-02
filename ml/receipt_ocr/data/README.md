# Dataset contract

Mỗi dòng trong `annotations.jsonl` là một ảnh crop chứa một dòng chữ và nhãn
Unicode chính xác:

```json
{"id":"receipt-0001-line-001","image":"images/receipt-0001-line-001.png","text":"TỔNG CỘNG 125.000 ₫","document_id":"receipt-0001","source":"camera"}
```

Trường bắt buộc:

- `id`: duy nhất cho từng dòng chữ.
- `image`: đường dẫn tuyệt đối hoặc tương đối với `--image-root`.
- `text`: transcription chính xác, giữ nguyên dấu tiếng Việt.
- `document_id`: mã hóa đơn gốc; mọi crop cùng hóa đơn phải dùng cùng mã.

Trường tùy chọn:

- `split`: `train`, `validation` hoặc `test`. Nếu bỏ trống, script chia ổn
  định theo `document_id`.
- `source`: `camera`, `gallery`, `synthetic` hoặc nguồn tự định nghĩa.
- `metadata`: object JSON phục vụ phân tích lỗi, không đưa bí mật hoặc PII vào.

Để có metric theo trường, dùng `metadata.field`: `seller`, `date`,
`invoice_number`, `total`, `tax`, `line_item` hoặc `other`.

Không chia ngẫu nhiên từng crop. Các dòng từ cùng một hóa đơn ở nhiều split sẽ
làm metric tốt giả tạo vì font, nền và template gần như giống nhau.

Ảnh trước khi đưa vào dataset phải được ẩn số thẻ, số tài khoản, điện thoại và
thông tin định danh không cần thiết. Chỉ sử dụng hóa đơn có quyền thu thập và
huấn luyện rõ ràng.

## Dataset MC-OCR trên Kaggle

Với `domixi1989/vietnamese-receipts-mc-ocr-2021`, không cần tự viết JSONL. Chạy:

```bash
python scripts/convert_mcocr_kaggle.py \
  --dataset-root /path/to/downloaded-dataset \
  --output work/mcocr-converted
```

`text_recognition_train_data.txt` được chia ổn định theo hóa đơn thành
train/validation; `text_recognition_val_data.txt` trở thành test khóa. Converter
ghi thêm `mcocr_conversion_manifest.json`, bao gồm version nguồn và trạng thái
license. Dữ liệu này phục vụ recognition trên line crop; các bảng CSV KIE chưa
được converter này biến thành nhãn `seller/date/total`.

## Tạo line crop từ ảnh toàn hóa đơn

Nếu đang có ảnh toàn trang và bounding box, tạo `documents.jsonl` theo mẫu
[`../examples/documents.example.jsonl`](../examples/documents.example.jsonl):

```json
{"document_id":"receipt-0001","image":"receipts/receipt-0001.jpg","split":"train","lines":[{"id":"receipt-0001-line-001","bbox":[36,48,612,112],"text":"CỬA HÀNG MINH ANH","field":"seller"}]}
```

Sau đó chạy:

```bash
python scripts/crop_document_lines.py \
  --documents /path/to/documents.jsonl \
  --image-root /path/to/full-receipts \
  --output work/cropped-dataset
```

`bbox` dùng pixel theo thứ tự `[x1, y1, x2, y2]`. Output có sẵn thư mục
`images/` và `annotations.jsonl` để chạy preflight.
