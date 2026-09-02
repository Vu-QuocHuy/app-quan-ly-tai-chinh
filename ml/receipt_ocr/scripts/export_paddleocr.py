#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from receipt_ocr.paddle_runner import PaddleExportJob, run_command


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Export a fine-tuned PaddleOCR checkpoint for inference."
    )
    parser.add_argument("--paddleocr-dir", type=Path, required=True)
    parser.add_argument("--prepared-dir", type=Path, required=True)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--base-config",
        default="configs/rec/PP-OCRv5/PP-OCRv5_mobile_rec.yml",
    )
    parser.add_argument("--max-text-length", type=int, default=64)
    parser.add_argument("--override", action="append", default=[])
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    job = PaddleExportJob(
        paddleocr_dir=args.paddleocr_dir,
        prepared_dir=args.prepared_dir,
        checkpoint=args.checkpoint,
        output_dir=args.output,
        base_config=args.base_config,
        max_text_length=args.max_text_length,
        extra_overrides=tuple(args.override),
    )
    run_command(job.command(), dry_run=args.dry_run)


if __name__ == "__main__":
    main()
