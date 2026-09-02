# Vietnamese Receipt OCR

Module độc lập để fine-tune mô hình nhận dạng dòng chữ trên hóa đơn Việt Nam.
Phiên bản đầu dùng `PP-OCRv5_mobile_rec`, giữ ML Kit trong ứng dụng làm baseline và
fallback. Module này không chứa ảnh hóa đơn, secret hoặc model weights.

## Phạm vi phiên bản 0.1

- Dataset JSONL có version và `document_id` chống data leakage.
- Crop line tự động từ ảnh toàn hóa đơn + bounding-box annotations.
- Chia train/validation/test ổn định theo hóa đơn, không chia từng dòng crop.
- Preflight decode ảnh, phát hiện duplicate xuyên split, PII warning và text dài.
- Sinh label files và charset cho PaddleOCR.
- Sinh resolved YAML rồi điều phối fine-tune/export bằng PaddleOCR source tree.
- Inference baseline/fine-tuned và đánh giá exact match, CER/WER theo field.
- Evaluation gate và ZIP release chứa provenance + SHA-256.
- Quy trình Kaggle có thể chạy bằng một GPU.

Detection/crop dòng chữ tạm dùng công cụ annotation hoặc detector có sẵn. Fine-tune
text detection và KIE trích xuất `seller/date/total/lineItems` là giai đoạn tiếp theo.

## Dữ liệu

Xem [data/README.md](data/README.md) và
[annotations.example.jsonl](examples/annotations.example.jsonl). Mốc khởi đầu thực
tế là vài trăm hóa đơn đa dạng, tạo ra vài nghìn đến vài chục nghìn line crops. Chất
lượng nhãn và độ đa dạng merchant/font/ánh sáng quan trọng hơn tăng số lượng ảnh
trùng template.

Không commit dataset thật. Chỉ sử dụng dữ liệu có quyền huấn luyện; ẩn PII và chia
test theo merchant/template nếu muốn đo khả năng tổng quát hóa thực sự.

### Import Vietnamese Receipts MC-OCR 2021

Pipeline hỗ trợ trực tiếp Kaggle dataset
`domixi1989/vietnamese-receipts-mc-ocr-2021`:

```bash
python scripts/convert_mcocr_kaggle.py \
  --dataset-root /path/to/vietnamese-receipts-mc-ocr-2021 \
  --output work/mcocr-converted
```

Converter tự tìm hai file text-recognition label, tách official train thành
train/validation theo `document_id`, và giữ official validation làm test khóa.
Ở giới hạn mặc định 64 ký tự, v17 có 11/6.585 line quá dài được loại có ghi vết
trong conversion manifest; train/export dùng cùng giới hạn để không lệch kiến trúc.
Các mẫu được gắn `metadata.field=untyped`, vì vậy dùng overall CER/exact-match;
chỉ bật field gate sau khi có mapping KIE riêng. Trang Kaggle hiện ghi license là
`Unknown`: chỉ dùng private cho nghiên cứu nội bộ và không phát hành dataset-derived
weights trước khi xác minh quyền sử dụng.

## Chạy công cụ dữ liệu và test

```bash
cd ml/receipt_ocr
python -m pip install -e .
python -m unittest discover -s tests -v
python scripts/preflight_dataset.py \
  --annotations /path/to/annotations.jsonl \
  --image-root /path/to/dataset \
  --output work/preflight.json
python scripts/prepare_dataset.py \
  --annotations /path/to/annotations.jsonl \
  --image-root /path/to/dataset \
  --output work/prepared
```

Kết quả `work/prepared` gồm:

- `train.txt`, `validation.txt`, `test.txt`: PaddleOCR SimpleDataSet labels.
- `samples.jsonl`: ground-truth kèm split để đánh giá.
- `vietnamese_receipt_charset.txt`: charset sinh từ nhãn.
- `dataset_manifest.json`: fingerprint và thống kê dataset.

Nếu validation bị rỗng do dataset quá nhỏ, gán `split` rõ ràng cho ít nhất một
hóa đơn validation. Script train từ chối validation rỗng để tránh báo cáo metric
không có ý nghĩa.

## Fine-tune PaddleOCR

Clone đúng một revision PaddleOCR và ghi revision đó vào báo cáo thí nghiệm. Cài
PaddlePaddle GPU phù hợp CUDA trước, sau đó cài dependencies trong
`requirements-kaggle.txt`.

```bash
python scripts/train_paddleocr.py \
  --paddleocr-dir /path/to/PaddleOCR \
  --prepared-dir work/prepared \
  --pretrained-model /path/to/PP-OCRv5_mobile_rec_pretrained.pdparams \
  --output outputs/experiment-001 \
  --epochs 30 \
  --train-batch-size 32
```

Nếu revision PaddleOCR đổi tên config, truyền `--base-config`. Có thể lặp
`--override Key.Nested=value` để điều chỉnh augmentation hoặc scheduler mà không
sửa source tree. Dùng `--dry-run` để kiểm tra lệnh hoàn chỉnh trước khi dùng GPU.

Export checkpoint tốt nhất:

```bash
python scripts/export_paddleocr.py \
  --paddleocr-dir /path/to/PaddleOCR \
  --prepared-dir work/prepared \
  --checkpoint outputs/experiment-001/best_accuracy \
  --output artifacts/receipt-ocr-v0.1.0
```

Sinh prediction trực tiếp từ exported model:

```bash
python scripts/predict_paddleocr.py \
  --samples work/prepared/samples.jsonl \
  --model-dir artifacts/receipt-ocr-v0.1.0 \
  --split test \
  --device gpu:0 \
  --output work/predictions.jsonl
```

## Đánh giá và version model

Prediction JSONL dùng dạng:

```json
{"id":"receipt-0002-line-001","prediction":"Ngày 31/08/2026","confidence":0.97}
```

```bash
python scripts/evaluate_predictions.py \
  --ground-truth work/prepared/samples.jsonl \
  --predictions work/predictions.jsonl \
  --split test \
  --output outputs/experiment-001/test-metrics.json \
  --max-cer 0.15 \
  --min-exact-match 0.70

python scripts/create_model_manifest.py \
  --model-version 0.1.0 \
  --model-dir artifacts/receipt-ocr-v0.1.0 \
  --dataset-manifest work/prepared/dataset_manifest.json \
  --metrics outputs/experiment-001/test-metrics.json \
  --output artifacts/receipt-ocr-v0.1.0/model-manifest.json
```

Không quảng bá một model chỉ dựa trên training loss. Gate tối thiểu cần CER/WER,
exact match, accuracy riêng cho số tiền/ngày và latency trên thiết bị tham chiếu.

## Kaggle

Kaggle T4/P100 phù hợp để bắt đầu với mobile recognition model. Đưa dataset vào
`/kaggle/input` (read-only), còn prepared data/checkpoint vào `/kaggle/working`.
Đọc [KAGGLE_RUNBOOK_VI.md](KAGGLE_RUNBOOK_VI.md), sau đó mở
[notebook end-to-end](kaggle/receipt_ocr_kaggle.ipynb). Pipeline pin PaddleOCR
`3.7.0`, PaddlePaddle GPU `3.2.0`, chạy baseline, train, export, test gate và đóng
gói release. Bật Internet để clone/tải weights, hoặc upload source/wheels/weights
thành private Kaggle Dataset để chạy offline.

Nếu hết VRAM, hạ batch size từ 32 xuống 16 hoặc 8. Luôn lưu checkpoint mỗi epoch vì
quota và thời lượng session Kaggle không được đảm bảo.
