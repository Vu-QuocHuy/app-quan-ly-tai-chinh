from __future__ import annotations

from collections import Counter, defaultdict
from dataclasses import asdict, dataclass
from hashlib import sha256
from pathlib import Path
import re
from typing import Any

from .dataset import assign_document_splits, load_jsonl


_SENSITIVE_NUMBER = re.compile(r"(?<!\d)(?:\d[ -]?){13,19}(?!\d)")


@dataclass(frozen=True, slots=True)
class PreflightIssue:
    severity: str
    code: str
    message: str
    sample_id: str | None = None


@dataclass(frozen=True, slots=True)
class PreflightReport:
    ok: bool
    sample_count: int
    document_count: int
    split_samples: dict[str, int]
    split_documents: dict[str, int]
    field_counts: dict[str, int]
    image_format_counts: dict[str, int]
    max_text_length: int
    issues: list[PreflightIssue]

    def to_dict(self) -> dict[str, Any]:
        value = asdict(self)
        value["error_count"] = sum(
            issue.severity == "error" for issue in self.issues
        )
        value["warning_count"] = sum(
            issue.severity == "warning" for issue in self.issues
        )
        return value


def inspect_dataset(
    annotations_path: Path,
    *,
    image_root: Path | None = None,
    train_ratio: float = 0.8,
    validation_ratio: float = 0.1,
    seed: str = "hoadon-insight-v1",
    model_max_text_length: int = 64,
    minimum_documents: int = 20,
    decode_images: bool = True,
) -> PreflightReport:
    annotations_path = annotations_path.resolve()
    root = image_root.resolve() if image_root else annotations_path.parent
    samples = load_jsonl(annotations_path, image_root=root)
    assignments = assign_document_splits(
        samples,
        train_ratio=train_ratio,
        validation_ratio=validation_ratio,
        seed=seed,
    )
    issues: list[PreflightIssue] = []
    split_samples = Counter(assignments[sample.document_id] for sample in samples)
    split_documents = Counter(assignments.values())
    field_counts = Counter(
        str(sample.metadata.get("field", "untyped")) for sample in samples
    )
    image_format_counts: Counter[str] = Counter()
    hashes: dict[str, list[tuple[str, str]]] = defaultdict(list)
    longest_text = 0

    if len(assignments) < minimum_documents:
        issues.append(
            PreflightIssue(
                "warning",
                "dataset_too_small",
                f"Dataset chỉ có {len(assignments)} hóa đơn; mốc kiểm tra hiện tại là "
                f"{minimum_documents}.",
            )
        )
    for split in ("train", "validation", "test"):
        if split_documents.get(split, 0) == 0:
            issues.append(
                PreflightIssue(
                    "error",
                    "empty_split",
                    f"Split {split!r} không có hóa đơn nào.",
                )
            )

    pillow_image = None
    if decode_images:
        try:
            from PIL import Image

            pillow_image = Image
        except ImportError:
            issues.append(
                PreflightIssue(
                    "error",
                    "pillow_missing",
                    "Thiếu Pillow; cài requirements-kaggle.txt để kiểm tra ảnh.",
                )
            )

    for sample in samples:
        image_path = sample.image_path(root)
        split = assignments[sample.document_id]
        image_size = image_path.stat().st_size
        if image_size == 0:
            issues.append(
                PreflightIssue(
                    "error", "empty_image", "Tệp ảnh rỗng.", sample.sample_id
                )
            )
            continue
        if image_size > 10 * 1024 * 1024:
            issues.append(
                PreflightIssue(
                    "warning",
                    "large_line_image",
                    f"Line crop lớn bất thường: {image_size} bytes.",
                    sample.sample_id,
                )
            )
        digest = _sha256_file(image_path)
        hashes[digest].append((sample.sample_id, split))

        text_length = len(sample.text)
        longest_text = max(longest_text, text_length)
        if text_length > model_max_text_length:
            issues.append(
                PreflightIssue(
                    "error",
                    "text_too_long",
                    f"Nhãn dài {text_length} ký tự, vượt max_text_length="
                    f"{model_max_text_length}.",
                    sample.sample_id,
                )
            )
        if _SENSITIVE_NUMBER.search(sample.text):
            issues.append(
                PreflightIssue(
                    "warning",
                    "possible_sensitive_number",
                    "Nhãn có chuỗi 13-19 chữ số; kiểm tra số thẻ/tài khoản trước "
                    "khi upload.",
                    sample.sample_id,
                )
            )

        if pillow_image is not None:
            try:
                with pillow_image.open(image_path) as image:
                    image.verify()
                with pillow_image.open(image_path) as image:
                    width, height = image.size
                    image_format_counts[(image.format or "unknown").lower()] += 1
                if width <= 0 or height <= 0:
                    raise ValueError("kích thước ảnh không hợp lệ")
                if height < 12:
                    issues.append(
                        PreflightIssue(
                            "warning",
                            "line_too_short",
                            f"Chiều cao crop chỉ {height}px.",
                            sample.sample_id,
                        )
                    )
                if width / height > 40:
                    issues.append(
                        PreflightIssue(
                            "warning",
                            "extreme_aspect_ratio",
                            f"Tỉ lệ width/height={width / height:.1f} có thể làm "
                            "chữ bị co khi resize.",
                            sample.sample_id,
                        )
                    )
            except Exception as error:
                issues.append(
                    PreflightIssue(
                        "error",
                        "invalid_image",
                        f"Không giải mã được ảnh: {error}",
                        sample.sample_id,
                    )
                )

    for entries in hashes.values():
        if len(entries) < 2:
            continue
        sample_ids = [item[0] for item in entries]
        splits = {item[1] for item in entries}
        severity = "error" if len(splits) > 1 else "warning"
        code = "duplicate_image_across_splits" if len(splits) > 1 else "duplicate_image"
        issues.append(
            PreflightIssue(
                severity,
                code,
                f"Ảnh trùng byte ở các mẫu {sample_ids[:8]}"
                + (f" thuộc các split {sorted(splits)}." if len(splits) > 1 else "."),
            )
        )

    return PreflightReport(
        ok=not any(issue.severity == "error" for issue in issues),
        sample_count=len(samples),
        document_count=len(assignments),
        split_samples=dict(sorted(split_samples.items())),
        split_documents=dict(sorted(split_documents.items())),
        field_counts=dict(sorted(field_counts.items())),
        image_format_counts=dict(sorted(image_format_counts.items())),
        max_text_length=longest_text,
        issues=issues,
    )


def _sha256_file(path: Path) -> str:
    digest = sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

