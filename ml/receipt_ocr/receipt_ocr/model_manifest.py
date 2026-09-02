from __future__ import annotations

from datetime import datetime, timezone
from hashlib import sha256
import json
from pathlib import Path
from typing import Any


def create_model_manifest(
    *,
    model_name: str,
    model_version: str,
    base_model: str,
    model_dir: Path,
    dataset_manifest: Path,
    metrics_path: Path | None = None,
) -> dict[str, Any]:
    model_dir = model_dir.resolve()
    dataset_manifest = dataset_manifest.resolve()
    if not model_dir.is_dir():
        raise FileNotFoundError(f"Không tìm thấy thư mục model: {model_dir}")
    if not dataset_manifest.is_file():
        raise FileNotFoundError(
            f"Không tìm thấy dataset manifest: {dataset_manifest}"
        )
    dataset_metadata = json.loads(dataset_manifest.read_text(encoding="utf-8"))

    artifacts = []
    for path in sorted(item for item in model_dir.rglob("*") if item.is_file()):
        artifacts.append(
            {
                "path": str(path.relative_to(model_dir)),
                "bytes": path.stat().st_size,
                "sha256": _sha256_file(path),
            }
        )

    metrics: dict[str, Any] | None = None
    if metrics_path is not None:
        metrics_path = metrics_path.resolve()
        if not metrics_path.is_file():
            raise FileNotFoundError(f"Không tìm thấy metrics: {metrics_path}")
        metrics = json.loads(metrics_path.read_text(encoding="utf-8"))

    return {
        "schema_version": 1,
        "model_name": model_name,
        "model_version": model_version,
        "base_model": base_model,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "dataset_manifest": {
            "path": str(dataset_manifest),
            "sha256": _sha256_file(dataset_manifest),
            "sample_count": dataset_metadata.get("sample_count"),
            "document_count": dataset_metadata.get("document_count"),
            "source_dataset": dataset_metadata.get("source_dataset"),
            "source_dataset_version": dataset_metadata.get(
                "source_dataset_version"
            ),
            "source_license": dataset_metadata.get("source_license"),
            "redistribution_allowed": dataset_metadata.get(
                "redistribution_allowed"
            ),
        },
        "metrics": metrics,
        "artifacts": artifacts,
    }


def _sha256_file(path: Path) -> str:
    digest = sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
