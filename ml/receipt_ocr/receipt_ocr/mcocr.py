from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
import json
from pathlib import Path
import re
from typing import Iterable

from .schema import normalize_transcription


_GENERIC_IMAGE_DIRECTORIES = {
    "images",
    "train",
    "train_images",
    "val",
    "val_images",
    "validation",
}
_TRAILING_LINE_INDEX = re.compile(
    r"(?:[_-](?:line|crop|text|word)[_-]?\d+|[_-]\d+)$", re.IGNORECASE
)


@dataclass(frozen=True, slots=True)
class McOcrLabel:
    image_path: Path
    text: str
    source_line: int


def convert_mcocr_dataset(
    dataset_root: Path,
    output_dir: Path,
    *,
    train_labels: Path | None = None,
    validation_labels: Path | None = None,
    validation_fraction: float = 0.1,
    seed: str = "mcocr-2021-hoadon-v1",
    max_text_length: int = 64,
) -> Path:
    if not 0 < validation_fraction < 0.5:
        raise ValueError("validation_fraction phải nằm trong (0, 0.5).")
    if max_text_length <= 0:
        raise ValueError("max_text_length phải lớn hơn 0.")
    dataset_root = dataset_root.resolve()
    output_dir = output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    train_labels = train_labels or _find_unique(
        dataset_root, "text_recognition_train_data.txt"
    )
    validation_labels = validation_labels or _find_unique(
        dataset_root, "text_recognition_val_data.txt"
    )
    image_index: dict[str, list[Path]] | None = None

    def load(path: Path) -> list[McOcrLabel]:
        nonlocal image_index
        parsed = _parse_label_file(path)
        resolved: list[McOcrLabel] = []
        for item in parsed:
            image_path = _resolve_image(
                item.image_path,
                label_file=path,
                dataset_root=dataset_root,
            )
            if image_path is None:
                if image_index is None:
                    image_index = _index_images(dataset_root)
                matches = image_index.get(item.image_path.name, [])
                if len(matches) != 1:
                    raise FileNotFoundError(
                        f"Không resolve được ảnh {item.image_path!s} tại dòng "
                        f"{item.source_line} của {path}; basename có {len(matches)} "
                        "kết quả."
                    )
                image_path = matches[0]
            resolved.append(
                McOcrLabel(
                    image_path=image_path.resolve(),
                    text=item.text,
                    source_line=item.source_line,
                )
            )
        return resolved

    loaded_train_rows = load(train_labels.resolve())
    loaded_official_validation_rows = load(validation_labels.resolve())
    excluded_too_long = [
        {
            "original_split": split,
            "source_line": item.source_line,
            "image": str(item.image_path),
            "text_length": len(item.text),
        }
        for split, rows in (
            ("train", loaded_train_rows),
            ("validation", loaded_official_validation_rows),
        )
        for item in rows
        if len(item.text) > max_text_length
    ]
    train_rows = [
        item for item in loaded_train_rows if len(item.text) <= max_text_length
    ]
    official_validation_rows = [
        item
        for item in loaded_official_validation_rows
        if len(item.text) <= max_text_length
    ]
    seen_images: set[Path] = set()
    output_rows: list[dict] = []

    train_documents = {
        _derive_document_id(item.image_path, dataset_root) for item in train_rows
    }
    if len(train_documents) < 2:
        raise ValueError(
            "MC-OCR official train cần ít nhất 2 document để tạo train/validation "
            "không rò rỉ dữ liệu."
        )
    validation_documents = {
        document_id
        for document_id in train_documents
        if _stable_bucket(seed, document_id) < validation_fraction
    }
    if not validation_documents:
        validation_documents.add(
            min(train_documents, key=lambda value: _stable_bucket(seed, value))
        )
    if validation_documents == train_documents:
        validation_documents.remove(
            max(train_documents, key=lambda value: _stable_bucket(seed, value))
        )

    for item in train_rows:
        document_id = _derive_document_id(item.image_path, dataset_root)
        split = (
            "validation" if document_id in validation_documents else "train"
        )
        output_rows.append(
            _to_annotation(
                item,
                dataset_root=dataset_root,
                document_id=document_id,
                split=split,
                original_split="train",
                seen_images=seen_images,
            )
        )
    for item in official_validation_rows:
        document_id = _derive_document_id(item.image_path, dataset_root)
        if document_id in train_documents:
            raise ValueError(
                "Document xuất hiện ở cả official train và official validation: "
                f"{document_id}."
            )
        output_rows.append(
            _to_annotation(
                item,
                dataset_root=dataset_root,
                document_id=document_id,
                split="test",
                original_split="validation",
                seen_images=seen_images,
            )
        )

    annotations = output_dir / "annotations.jsonl"
    with annotations.open("w", encoding="utf-8", newline="\n") as handle:
        for row in sorted(output_rows, key=lambda value: value["id"]):
            handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")
    conversion_manifest = {
        "format_version": 1,
        "source": "domixi1989/vietnamese-receipts-mc-ocr-2021",
        "source_version": 17,
        "source_license": "Unknown",
        "redistribution_allowed": False,
        "seed": seed,
        "validation_fraction_from_official_train": validation_fraction,
        "max_text_length": max_text_length,
        "excluded_too_long_count": len(excluded_too_long),
        "excluded_too_long": excluded_too_long,
        "official_train_labels": str(train_labels.resolve()),
        "official_validation_labels_used_as": "test",
        "official_validation_labels": str(validation_labels.resolve()),
        "sample_count": len(output_rows),
        "document_count": len(
            {row["document_id"] for row in output_rows}
        ),
        "split_sample_counts": {
            split: sum(row["split"] == split for row in output_rows)
            for split in ("train", "validation", "test")
        },
        "split_document_counts": {
            split: len(
                {
                    row["document_id"]
                    for row in output_rows
                    if row["split"] == split
                }
            )
            for split in ("train", "validation", "test")
        },
        "document_id_strategy": "parent-directory-or-trailing-line-index",
    }
    (output_dir / "mcocr_conversion_manifest.json").write_text(
        json.dumps(conversion_manifest, ensure_ascii=False, indent=2, sort_keys=True)
        + "\n",
        encoding="utf-8",
    )
    return annotations


def _parse_label_file(path: Path) -> list[McOcrLabel]:
    rows: list[McOcrLabel] = []
    with path.open("r", encoding="utf-8-sig") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            line = raw_line.rstrip("\r\n")
            if not line.strip():
                continue
            if "\t" in line:
                image, text = line.split("\t", 1)
            else:
                parts = line.split(maxsplit=1)
                if len(parts) != 2:
                    raise ValueError(
                        f"Nhãn MC-OCR dòng {line_number} không có path + text: {line!r}"
                    )
                image, text = parts
            normalized = normalize_transcription(text)
            if not image.strip() or not normalized:
                raise ValueError(f"Nhãn MC-OCR rỗng tại dòng {line_number}.")
            rows.append(
                McOcrLabel(
                    image_path=Path(image.strip().replace("\\", "/")),
                    text=normalized,
                    source_line=line_number,
                )
            )
    if not rows:
        raise ValueError(f"Label file rỗng: {path}")
    return rows


def _resolve_image(
    path: Path,
    *,
    label_file: Path,
    dataset_root: Path,
) -> Path | None:
    candidates: Iterable[Path] = (
        path,
        label_file.parent / path,
        dataset_root / path,
        dataset_root / "text_recognition_mcocr_data" / path,
        dataset_root / "train_images" / path.name,
        dataset_root / "val_images" / path.name,
        dataset_root / "text_recognition_mcocr_data" / "train_images" / path.name,
        dataset_root / "text_recognition_mcocr_data" / "val_images" / path.name,
    )
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    return None


def _index_images(dataset_root: Path) -> dict[str, list[Path]]:
    index: dict[str, list[Path]] = {}
    for path in dataset_root.rglob("*"):
        if path.is_file() and path.suffix.lower() in {
            ".bmp",
            ".jpeg",
            ".jpg",
            ".png",
            ".tif",
            ".tiff",
            ".webp",
        }:
            index.setdefault(path.name, []).append(path)
    return index


def _derive_document_id(image_path: Path, dataset_root: Path) -> str:
    parent_name = image_path.parent.name.lower()
    stem = image_path.stem
    if parent_name not in _GENERIC_IMAGE_DIRECTORIES:
        raw = image_path.parent.name
    else:
        raw = _TRAILING_LINE_INDEX.sub("", stem) or stem
    prefix = re.sub(r"[^A-Za-z0-9._-]+", "-", raw).strip("-._") or "receipt"
    digest = sha256(raw.encode("utf-8")).hexdigest()[:12]
    return f"mcocr-{prefix[:80]}-{digest}"


def _to_annotation(
    item: McOcrLabel,
    *,
    dataset_root: Path,
    document_id: str,
    split: str,
    original_split: str,
    seen_images: set[Path],
) -> dict:
    if item.image_path in seen_images:
        raise ValueError(f"Ảnh xuất hiện nhiều lần trong label files: {item.image_path}")
    seen_images.add(item.image_path)
    relative = _safe_relative(item.image_path, dataset_root)
    digest = sha256(str(relative).encode("utf-8")).hexdigest()[:16]
    return {
        "id": f"mcocr-line-{digest}",
        "image": str(item.image_path),
        "text": item.text,
        "document_id": document_id,
        "split": split,
        "source": "mcocr-2021-kaggle-v17",
        "metadata": {
            "field": "untyped",
            "original_split": original_split,
            "original_path": str(relative),
        },
    }


def _safe_relative(path: Path, root: Path) -> Path:
    try:
        return path.resolve().relative_to(root.resolve())
    except ValueError:
        return Path(path.name)


def _stable_bucket(seed: str, document_id: str) -> float:
    digest = sha256(f"{seed}:{document_id}".encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big") / float(1 << 64)


def _find_unique(root: Path, name: str) -> Path:
    matches = list(root.rglob(name))
    if len(matches) != 1:
        raise FileNotFoundError(
            f"Cần đúng một {name!r} trong {root}, tìm thấy {len(matches)}: {matches[:5]}"
        )
    return matches[0]
