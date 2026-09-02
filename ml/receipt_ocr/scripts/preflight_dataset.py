#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from receipt_ocr.preflight import inspect_dataset


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run fail-fast checks before uploading/training receipt OCR data."
    )
    parser.add_argument("--annotations", type=Path, required=True)
    parser.add_argument("--image-root", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--train-ratio", type=float, default=0.8)
    parser.add_argument("--validation-ratio", type=float, default=0.1)
    parser.add_argument("--seed", default="hoadon-insight-v1")
    parser.add_argument("--max-text-length", type=int, default=64)
    parser.add_argument("--minimum-documents", type=int, default=20)
    parser.add_argument("--skip-image-decode", action="store_true")
    parser.add_argument("--strict-warnings", action="store_true")
    args = parser.parse_args()

    report = inspect_dataset(
        args.annotations,
        image_root=args.image_root,
        train_ratio=args.train_ratio,
        validation_ratio=args.validation_ratio,
        seed=args.seed,
        model_max_text_length=args.max_text_length,
        minimum_documents=args.minimum_documents,
        decode_images=not args.skip_image_decode,
    )
    output = json.dumps(report.to_dict(), ensure_ascii=False, indent=2, sort_keys=True)
    print(output)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output + "\n", encoding="utf-8")
    if not report.ok:
        raise SystemExit(2)
    if args.strict_warnings and report.issues:
        raise SystemExit(3)


if __name__ == "__main__":
    main()

