#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from receipt_ocr.mcocr import convert_mcocr_dataset


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert Kaggle Vietnamese Receipts MC-OCR 2021 to project JSONL."
    )
    parser.add_argument("--dataset-root", type=Path, required=True)
    parser.add_argument("--train-labels", type=Path)
    parser.add_argument("--validation-labels", type=Path)
    parser.add_argument("--validation-fraction", type=float, default=0.1)
    parser.add_argument("--seed", default="mcocr-2021-hoadon-v1")
    parser.add_argument("--max-text-length", type=int, default=64)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    annotations = convert_mcocr_dataset(
        args.dataset_root,
        args.output,
        train_labels=args.train_labels,
        validation_labels=args.validation_labels,
        validation_fraction=args.validation_fraction,
        seed=args.seed,
        max_text_length=args.max_text_length,
    )
    print(f"Converted MC-OCR annotations: {annotations}")


if __name__ == "__main__":
    main()
