#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from receipt_ocr.cropper import crop_document_annotations


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Crop line images from full-receipt bounding-box annotations."
    )
    parser.add_argument("--documents", type=Path, required=True)
    parser.add_argument("--image-root", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--padding", type=int, default=4)
    args = parser.parse_args()

    annotations = crop_document_annotations(
        args.documents,
        args.output,
        image_root=args.image_root,
        padding=args.padding,
    )
    print(f"Generated annotations: {annotations}")


if __name__ == "__main__":
    main()

