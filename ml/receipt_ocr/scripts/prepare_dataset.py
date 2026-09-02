#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from receipt_ocr.dataset import prepare_dataset


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate and prepare Vietnamese receipt line OCR data."
    )
    parser.add_argument("--annotations", type=Path, required=True)
    parser.add_argument("--image-root", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--train-ratio", type=float, default=0.8)
    parser.add_argument("--validation-ratio", type=float, default=0.1)
    parser.add_argument("--seed", default="hoadon-insight-v1")
    args = parser.parse_args()

    prepared = prepare_dataset(
        args.annotations,
        args.output,
        image_root=args.image_root,
        train_ratio=args.train_ratio,
        validation_ratio=args.validation_ratio,
        seed=args.seed,
    )
    print(f"Prepared dataset: {prepared.output_dir}")
    print(f"Manifest: {prepared.manifest_path}")
    print(f"Charset: {prepared.charset_path}")
    for split, path in sorted(prepared.split_files.items()):
        line_count = sum(1 for line in path.read_text(encoding="utf-8").splitlines() if line)
        print(f"{split}: {line_count} samples -> {path}")


if __name__ == "__main__":
    main()
