# Chạy trên Kaggle

Đọc hướng dẫn đầy đủ tại
[`../KAGGLE_RUNBOOK_VI.md`](../KAGGLE_RUNBOOK_VI.md). Notebook hiện tự tìm source
và dataset MC-OCR (hoặc JSONL tùy biến) trong `/kaggle/input`, pin runtime, tự
convert annotation, chạy preflight, baseline, train,
export, inference, evaluation gate và đóng gói ZIP release.

`/kaggle/input` là read-only. Không để checkpoint ở đó; dùng `/kaggle/working` và
tải artifact về hoặc publish thành private Kaggle Dataset sau mỗi thí nghiệm.

Notebook pin `paddlepaddle-gpu==3.2.0` từ official CUDA 12.6 index và PaddleOCR
tag/package `3.7.0`. Nếu driver không phù hợp, đổi sang official CUDA 11.8 index
được ghi trong runbook; không hạ ngẫu nhiên version. Báo cáo environment lưu lại
version, GPU và source tag để thí nghiệm tái lập được.
