#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from receipt_ocr.paddle_runner import PaddleTrainJob, run_command


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fine-tune PP-OCRv5 mobile recognition on receipt lines."
    )
    parser.add_argument("--paddleocr-dir", type=Path, required=True)
    parser.add_argument("--prepared-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--base-config",
        default="configs/rec/PP-OCRv5/PP-OCRv5_mobile_rec.yml",
    )
    initialization = parser.add_mutually_exclusive_group(required=True)
    initialization.add_argument("--pretrained-model", type=Path)
    initialization.add_argument(
        "--from-scratch",
        action="store_true",
        help="Train without pretrained weights; not recommended for normal fine-tuning.",
    )
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--train-batch-size", type=int, default=32)
    parser.add_argument("--eval-batch-size", type=int, default=32)
    parser.add_argument("--learning-rate", type=float, default=0.0005)
    parser.add_argument("--max-text-length", type=int, default=64)
    parser.add_argument("--num-workers", type=int, default=2)
    parser.add_argument(
        "--eval-batch-step",
        type=int,
        default=200,
        help="Evaluate every N training iterations so best_accuracy is produced.",
    )
    parser.add_argument("--cpu", action="store_true")
    parser.add_argument(
        "--override",
        action="append",
        default=[],
        help="Additional Paddle config override; repeat for multiple values.",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    job = PaddleTrainJob(
        paddleocr_dir=args.paddleocr_dir,
        prepared_dir=args.prepared_dir,
        output_dir=args.output,
        base_config=args.base_config,
        pretrained_model=args.pretrained_model,
        epochs=args.epochs,
        train_batch_size=args.train_batch_size,
        eval_batch_size=args.eval_batch_size,
        learning_rate=args.learning_rate,
        max_text_length=args.max_text_length,
        num_workers=args.num_workers,
        eval_batch_step=args.eval_batch_step,
        use_gpu=not args.cpu,
        extra_overrides=tuple(args.override),
    )
    run_command(job.command(), dry_run=args.dry_run)


if __name__ == "__main__":
    main()
