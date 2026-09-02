# Hướng dẫn fine-tune OCR hóa đơn trên Kaggle

Tài liệu này chạy pipeline `PP-OCRv5_mobile_rec` từ dataset line-crop đến model
artifact. App Flutter không cần thay đổi để chạy trong lúc model đang được huấn
luyện; ML Kit vẫn là fallback.

## 1. Những gì Kaggle cần

Tạo hai Kaggle Dataset dạng private:

1. **Source dataset**: chứa thư mục `ml/receipt_ocr` của repository này. Notebook
   tự tìm file `receipt_ocr/pyproject.toml` bên dưới `/kaggle/input` rồi copy source
   sang `/kaggle/working`.
2. **OCR dataset**: attach dataset
   `domixi1989/vietnamese-receipts-mc-ocr-2021`. Notebook tự tìm
   `text_recognition_train_data.txt` và `text_recognition_val_data.txt`, không cần
   copy hay đổi tên file.

Dataset MC-OCR hiện được Kaggle ghi license là `Unknown`. Có thể dùng để thử
pipeline trong notebook private, nhưng cần xin/xác minh quyền huấn luyện và phát
hành trước khi công khai model hoặc dữ liệu dẫn xuất.

### Dataset này phù hợp đến đâu?

Đã kiểm tra trực tiếp hai label file của version 17:

- Official train: 5.285 line crop thuộc 922 hóa đơn.
- Official validation: 1.300 line crop thuộc 231 hóa đơn.
- Hai tập không trùng receipt ID theo tên file
  `mcocr_public_<receipt-id>_<line-index>.jpg`.

Nhãn tập trung vào các dòng quan trọng như cửa hàng, địa chỉ, thời gian và tổng
tiền. Vì vậy đây là nguồn khởi đầu tốt để fine-tune **text recognition cho key
lines**, nhưng chưa đủ để huấn luyện toàn bộ detector trên ảnh hóa đơn, đọc mọi
line item, hoặc xuất trực tiếp JSON `seller/date/total`. Các bài toán đó cần ảnh
toàn trang + polygon/bbox và adapter KIE riêng.

Notebook vẫn hỗ trợ dataset riêng chứa đúng một `annotations.jsonl` và thư mục
ảnh line-crop. Layout khuyến nghị:

```text
vietnamese-receipt-ocr/
  annotations.jsonl
  images/
    receipt-0001-line-001.png
    receipt-0001-line-002.png
    ...
```

Mỗi dòng annotation:

```json
{"id":"receipt-0001-line-001","image":"images/receipt-0001-line-001.png","text":"TỔNG CỘNG 125.000 ₫","document_id":"receipt-0001","split":"train","metadata":{"field":"total"}}
```

`metadata.field` của dataset riêng nên dùng một trong `seller`, `date`,
`invoice_number`, `total`, `tax`, `line_item`, `other`. Trường này giúp report
riêng độ chính xác dữ liệu quan trọng; không ảnh hưởng trực tiếp loss OCR.

Ảnh ở đây phải là **crop một dòng chữ**, không phải cả trang hóa đơn. Text
recognition model nhận đầu vào từ text detector/công cụ annotation. Fine-tune
detector trên ảnh toàn trang là một thí nghiệm khác.

## 2. Cấu hình Kaggle Notebook

Tạo notebook, attach hai dataset trên, rồi chọn:

- Accelerator: `GPU T4 x1` hoặc `GPU P100`.
- Internet: `On` cho lần đầu clone source/tải pretrained weights.
- Persistence: output quan trọng phải nằm trong `/kaggle/working`.

Mở notebook
[`kaggle/receipt_ocr_kaggle.ipynb`](kaggle/receipt_ocr_kaggle.ipynb) và chạy từ
trên xuống. Notebook đang pin:

| Thành phần | Version |
|---|---|
| PaddleOCR package/source | `3.7.0` / tag `v3.7.0` |
| PaddlePaddle GPU | `3.2.0` |
| Paddle wheel index mặc định | CUDA 12.6 |
| Base config | `PP-OCRv5_mobile_rec.yml` |
| Max text length | 64 |

Nếu driver hiển thị bởi `nvidia-smi` thấp hơn yêu cầu CUDA 12.6, đổi
`PADDLE_INDEX_URL` trong cell Configuration thành:

```text
https://www.paddlepaddle.org.cn/packages/stable/cu118/
```

Không cài nhiều bản `paddlepaddle`/`paddlepaddle-gpu` cùng lúc.

## 3. Thứ tự notebook

Notebook thực hiện:

1. Tự tìm và copy source module vào `/kaggle/working`.
2. Cài PaddlePaddle/PaddleOCR đã pin.
3. Clone PaddleOCR tag `v3.7.0`, tải pretrained `.pdparams`.
4. Nếu thấy MC-OCR, chuyển official train thành train/validation theo hóa đơn và
   giữ official validation làm test khóa. Với `MAX_TEXT_LENGTH=64`, converter loại
   có ghi vết 11/6.585 nhãn v17 dài hơn giới hạn (10 train, 1 test).
5. Chạy `check_kaggle_environment.py` để xác nhận GPU, CUDA build và đường dẫn.
6. Chạy `preflight_dataset.py`: decode ảnh, kiểm tra split, ảnh trùng, text quá
   dài và chuỗi số có thể nhạy cảm.
7. Chuẩn bị Paddle label files, charset và dataset manifest.
8. Chạy baseline official model trên test set.
9. Fine-tune, lưu checkpoint mỗi epoch và evaluate định kỳ để tạo `best_accuracy`.
10. Export `best_accuracy` thành inference model.
11. Smoke inference 8 ảnh validation, sau đó inference toàn bộ test.
12. Tính exact match, CER/WER và metric theo field nếu dataset có field label.
13. Chạy evaluation gate rồi đóng gói ZIP + SHA-256.

Các ngưỡng mặc định trong notebook là điểm bắt đầu, không phải kết quả bảo đảm:

```text
overall CER <= 0.15
overall exact match >= 0.70
prediction coverage = 1.00
```

MC-OCR converter gắn các line là `untyped`, nên notebook không đặt gate riêng cho
`total`. Muốn đánh giá `seller/date/total`, cần bổ sung adapter KIE từ CSV và xác
minh cách liên kết field với line ảnh trước khi bật field gate.

Không tăng `MAX_TEXT_LENGTH` chỉ để giữ 11 dòng dài: base model dùng chiều rộng
ảnh nhận dạng 320 và mặc định upstream chỉ 25 ký tự. Nếu muốn giữ các dòng đó,
cần một thí nghiệm riêng tăng width/multi-scale, đo VRAM và xác nhận CTC sequence
đủ dài; train và export phải dùng cùng giá trị.

Chỉ thay ngưỡng sau khi chốt test set. Không hạ ngưỡng để “làm đẹp” một lần train.

## 4. Output cần tải về

Trong `/kaggle/working/receipt-ocr-work`:

```text
prepared/dataset_manifest.json
mcocr-converted/mcocr_conversion_manifest.json
training/best_accuracy.pdparams
inference-model/
predictions/baseline-test.jsonl
predictions/fine-tuned-test.jsonl
reports/baseline-test-metrics.json
reports/fine-tuned-test-metrics.json
releases/hoadon-receipt-ocr-0.1.0.zip
releases/hoadon-receipt-ocr-0.1.0.zip.sha256
```

ZIP release chứa inference model, charset, test metrics, dataset/source manifest
(gồm license flag), dataset fingerprint và hash từng artifact. Tải cả ZIP và
`.sha256`, hoặc publish thư mục `releases/` thành private Kaggle Dataset trước khi
session hết hạn.

## 5. Lỗi thường gặp

### `PaddlePaddle không nhìn thấy GPU`

- Kiểm tra notebook đã bật GPU.
- Chỉ giữ `paddlepaddle-gpu`, gỡ bản CPU nếu image đã cài sẵn.
- Chọn `cu126` hoặc `cu118` theo driver, sau đó restart kernel và chạy lại từ đầu.

### Hết VRAM

Hạ `TRAIN_BATCH_SIZE` từ 32 xuống 16 hoặc 8. Pipeline đồng thời cập nhật
`Train.loader.batch_size_per_card` và `Train.sampler.first_bs` trong resolved YAML.

### `validation.txt` hoặc `test` rỗng

Gán `split` thủ công theo `document_id`. Cần ít nhất một hóa đơn khác nhau cho
train, validation và test. Không để các line crop cùng hóa đơn nằm ở nhiều split.

### Checkpoint không tồn tại

Mở log training và tìm lỗi trước epoch đầu. Export chỉ chấp nhận
`best_accuracy` hoặc file `.pdparams` thực sự tồn tại.

### Model đọc sai dấu tiếng Việt

- Kiểm tra annotation là Unicode NFC và đúng dấu.
- Tăng merchant/font/điều kiện ánh sáng, không nhân bản cùng template.
- Xem `largest_errors` và `field_metrics` trong report.
- Không trộn ảnh toàn trang với line crop.

### API inference thay đổi

Notebook pin `paddleocr==3.7.0` và source tag `v3.7.0`. Nếu nâng version, chạy lại
unit tests và smoke inference trước khi dùng toàn bộ test set.

## 6. Khi nào đủ để tích hợp app

Chỉ chuyển sang `OCR-007` khi:

- Fine-tuned model tốt hơn baseline trên test set khóa trước.
- Coverage 100%, không có ảnh test bị bỏ qua.
- Overall CER/exact-match đạt ngưỡng và tốt hơn baseline trên MC-OCR.
- Nếu đã bổ sung nhãn KIE, metric `total`, `date`, `seller` đạt ngưỡng đã chốt.
- Artifact có model manifest và SHA-256.
- Đã benchmark latency/memory trên thiết bị Android tham chiếu.
- ML Kit fallback vẫn hoạt động nếu model lỗi hoặc không tương thích thiết bị.
