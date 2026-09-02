from __future__ import annotations

from collections import Counter, defaultdict
from dataclasses import dataclass
from hashlib import sha256
import json
from pathlib import Path
from typing import Iterable, Mapping, Sequence

from .charset import training_charset
from .schema import ReceiptLineSample, VALID_SPLITS


@dataclass(frozen=True, slots=True)
class PreparedDataset:
    output_dir: Path
    manifest_path: Path
    charset_path: Path
    split_files: Mapping[str, Path]
    split_samples_path: Path


def load_jsonl(
    annotations_path: Path,
    *,
    image_root: Path | None = None,
    require_images: bool = True,
) -> list[ReceiptLineSample]:
    annotations_path = annotations_path.resolve()
    root = image_root.resolve() if image_root else annotations_path.parent
    samples: list[ReceiptLineSample] = []
    seen_ids: set[str] = set()

    with annotations_path.open("r", encoding="utf-8") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            line = raw_line.strip()
            if not line:
                continue
            try:
                value = json.loads(line)
            except json.JSONDecodeError as error:
                raise ValueError(
                    f"JSONL không hợp lệ tại dòng {line_number}: {error.msg}."
                ) from error
            if not isinstance(value, dict):
                raise ValueError(f"Dòng {line_number} phải là một object JSON.")
            sample = ReceiptLineSample.from_mapping(value)
            if sample.sample_id in seen_ids:
                raise ValueError(f"Trùng id mẫu: {sample.sample_id!r}.")
            seen_ids.add(sample.sample_id)
            if require_images and not sample.image_path(root).is_file():
                raise FileNotFoundError(
                    f"Không tìm thấy ảnh của mẫu {sample.sample_id!r}: "
                    f"{sample.image_path(root)}"
                )
            samples.append(sample)

    if not samples:
        raise ValueError("Tệp annotation không có mẫu hợp lệ.")
    return samples


def assign_document_splits(
    samples: Sequence[ReceiptLineSample],
    *,
    train_ratio: float = 0.8,
    validation_ratio: float = 0.1,
    seed: str = "hoadon-insight-v1",
) -> dict[str, str]:
    if train_ratio <= 0 or validation_ratio < 0:
        raise ValueError("Tỉ lệ train phải > 0 và validation phải >= 0.")
    if train_ratio + validation_ratio >= 1:
        raise ValueError("Tổng tỉ lệ train và validation phải nhỏ hơn 1.")

    explicit: dict[str, str] = {}
    for sample in samples:
        if sample.split is None:
            continue
        previous = explicit.get(sample.document_id)
        if previous is not None and previous != sample.split:
            raise ValueError(
                f"Hóa đơn {sample.document_id!r} xuất hiện ở nhiều split: "
                f"{previous!r} và {sample.split!r}."
            )
        explicit[sample.document_id] = sample.split

    assignments = dict(explicit)
    for document_id in sorted({sample.document_id for sample in samples}):
        if document_id in assignments:
            continue
        digest = sha256(f"{seed}:{document_id}".encode("utf-8")).digest()
        bucket = int.from_bytes(digest[:8], "big") / float(1 << 64)
        if bucket < train_ratio:
            split = "train"
        elif bucket < train_ratio + validation_ratio:
            split = "validation"
        else:
            split = "test"
        assignments[document_id] = split

    return assignments


def build_charset(samples: Iterable[ReceiptLineSample]) -> list[str]:
    observed = {
        character
        for sample in samples
        for character in sample.text
        if not character.isspace()
    }
    return training_charset(observed)


def prepare_dataset(
    annotations_path: Path,
    output_dir: Path,
    *,
    image_root: Path | None = None,
    train_ratio: float = 0.8,
    validation_ratio: float = 0.1,
    seed: str = "hoadon-insight-v1",
) -> PreparedDataset:
    annotations_path = annotations_path.resolve()
    root = image_root.resolve() if image_root else annotations_path.parent
    samples = load_jsonl(annotations_path, image_root=root)
    assignments = assign_document_splits(
        samples,
        train_ratio=train_ratio,
        validation_ratio=validation_ratio,
        seed=seed,
    )
    output_dir = output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    grouped: dict[str, list[ReceiptLineSample]] = defaultdict(list)
    for sample in samples:
        grouped[assignments[sample.document_id]].append(sample)

    split_files: dict[str, Path] = {}
    for split in sorted(VALID_SPLITS):
        path = output_dir / f"{split}.txt"
        with path.open("w", encoding="utf-8", newline="\n") as handle:
            for sample in sorted(
                grouped.get(split, []),
                key=lambda item: (item.document_id, item.sample_id),
            ):
                handle.write(f"{sample.image_path(root)}\t{sample.text}\n")
        split_files[split] = path

    split_samples_path = output_dir / "samples.jsonl"
    with split_samples_path.open("w", encoding="utf-8", newline="\n") as handle:
        for sample in sorted(samples, key=lambda item: item.sample_id):
            value = sample.to_mapping(split=assignments[sample.document_id])
            value["resolved_image"] = str(sample.image_path(root))
            handle.write(json.dumps(value, ensure_ascii=False, sort_keys=True) + "\n")

    charset_path = output_dir / "vietnamese_receipt_charset.txt"
    charset = build_charset(grouped.get("train", []))
    unsupported_characters = sorted(
        {
            character
            for sample in samples
            for character in sample.text
            if not character.isspace() and character not in charset
        },
        key=ord,
    )
    if unsupported_characters:
        rendered = " ".join(repr(item) for item in unsupported_characters[:20])
        raise ValueError(
            "Validation/test chứa ký tự ngoài charset nền và chưa xuất hiện trong "
            f"train: {rendered}. Hãy bổ sung train hoặc làm sạch nhãn."
        )
    charset_path.write_text("\n".join(charset) + "\n", encoding="utf-8")

    sample_counts = Counter(assignments[sample.document_id] for sample in samples)
    document_counts = Counter(assignments.values())
    source_counts = Counter(sample.source or "unknown" for sample in samples)
    manifest = {
        "format_version": 1,
        "seed": seed,
        "annotations": str(annotations_path),
        "annotations_sha256": _sha256_file(annotations_path),
        "image_root": str(root),
        "sample_count": len(samples),
        "document_count": len(assignments),
        "sample_counts": dict(sorted(sample_counts.items())),
        "document_counts": dict(sorted(document_counts.items())),
        "source_counts": dict(sorted(source_counts.items())),
        "charset_size": len(charset),
        "charset_sha256": _sha256_file(charset_path),
        "charset_source": "vietnamese-receipt-base-plus-train-only",
    }
    source_manifest_path = annotations_path.parent / "mcocr_conversion_manifest.json"
    if source_manifest_path.is_file():
        source_manifest = json.loads(source_manifest_path.read_text(encoding="utf-8"))
        manifest["source_manifest"] = str(source_manifest_path.resolve())
        manifest["source_manifest_sha256"] = _sha256_file(source_manifest_path)
        manifest["source_dataset"] = source_manifest.get("source")
        manifest["source_dataset_version"] = source_manifest.get("source_version")
        manifest["source_license"] = source_manifest.get("source_license")
        manifest["redistribution_allowed"] = source_manifest.get(
            "redistribution_allowed"
        )
        manifest["source_excluded_too_long_count"] = source_manifest.get(
            "excluded_too_long_count", 0
        )
    manifest_path = output_dir / "dataset_manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    return PreparedDataset(
        output_dir=output_dir,
        manifest_path=manifest_path,
        charset_path=charset_path,
        split_files=split_files,
        split_samples_path=split_samples_path,
    )


def _sha256_file(path: Path) -> str:
    digest = sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
