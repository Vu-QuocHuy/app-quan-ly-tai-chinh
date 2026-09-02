#!/usr/bin/env python3
from __future__ import annotations

import argparse
from hashlib import sha256
import json
from pathlib import Path
import sys
import zipfile

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from receipt_ocr.model_manifest import create_model_manifest


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Package an exported OCR model, metrics and provenance."
    )
    parser.add_argument("--model-name", default="hoadon-ppocrv5-mobile-rec")
    parser.add_argument("--model-version", required=True)
    parser.add_argument("--base-model", default="PP-OCRv5_mobile_rec")
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--charset", type=Path, required=True)
    parser.add_argument("--dataset-manifest", type=Path, required=True)
    parser.add_argument("--metrics", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    for label, path in [
        ("charset", args.charset),
        ("dataset manifest", args.dataset_manifest),
        ("metrics", args.metrics),
    ]:
        if not path.is_file():
            raise FileNotFoundError(f"Không tìm thấy {label}: {path}")

    metrics_report = json.loads(args.metrics.read_text(encoding="utf-8"))
    if metrics_report.get("gate_passed") is not True:
        raise ValueError(
            "Metrics chưa vượt release gate; không đóng gói model production."
        )
    dataset_report = json.loads(args.dataset_manifest.read_text(encoding="utf-8"))
    source_manifest_value = dataset_report.get("source_manifest")
    source_manifest = (
        Path(source_manifest_value)
        if isinstance(source_manifest_value, str) and source_manifest_value
        else None
    )
    if source_manifest is not None and not source_manifest.is_file():
        raise FileNotFoundError(
            f"Dataset khai báo source manifest nhưng file không tồn tại: {source_manifest}"
        )

    manifest = create_model_manifest(
        model_name=args.model_name,
        model_version=args.model_version,
        base_model=args.base_model,
        model_dir=args.model_dir,
        dataset_manifest=args.dataset_manifest,
        metrics_path=args.metrics,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(
        args.output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
    ) as archive:
        archive.writestr(
            "model-manifest.json",
            json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        )
        archive.write(args.charset, "vietnamese_receipt_charset.txt")
        archive.write(args.dataset_manifest, "dataset_manifest.json")
        if source_manifest is not None:
            archive.write(source_manifest, "source_dataset_manifest.json")
        archive.write(args.metrics, "test_metrics.json")
        for path in sorted(item for item in args.model_dir.rglob("*") if item.is_file()):
            archive.write(path, Path("model") / path.relative_to(args.model_dir))

    checksum = _sha256_file(args.output)
    checksum_path = Path(f"{args.output}.sha256")
    checksum_path.write_text(f"{checksum}  {args.output.name}\n", encoding="utf-8")
    print(f"Release: {args.output.resolve()}")
    print(f"SHA-256: {checksum}")


def _sha256_file(path: Path) -> str:
    digest = sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


if __name__ == "__main__":
    main()
