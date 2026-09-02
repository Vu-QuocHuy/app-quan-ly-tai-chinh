#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from receipt_ocr.model_manifest import create_model_manifest


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create a reproducible manifest for an exported OCR model."
    )
    parser.add_argument("--model-name", default="hoadon-ppocrv5-mobile-rec")
    parser.add_argument("--model-version", required=True)
    parser.add_argument("--base-model", default="PP-OCRv5_mobile_rec")
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--dataset-manifest", type=Path, required=True)
    parser.add_argument("--metrics", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    manifest = create_model_manifest(
        model_name=args.model_name,
        model_version=args.model_version,
        base_model=args.base_model,
        model_dir=args.model_dir,
        dataset_manifest=args.dataset_manifest,
        metrics_path=args.metrics,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"Model manifest: {args.output.resolve()}")


if __name__ == "__main__":
    main()
