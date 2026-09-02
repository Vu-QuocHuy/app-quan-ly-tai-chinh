from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Mapping
import unicodedata


VALID_SPLITS = frozenset({"train", "validation", "test"})
SUPPORTED_IMAGE_SUFFIXES = frozenset(
    {".bmp", ".jpeg", ".jpg", ".png", ".tif", ".tiff", ".webp"}
)


def normalize_transcription(value: str) -> str:
    """Normalize labels without removing Vietnamese diacritics."""

    return " ".join(unicodedata.normalize("NFC", value).split())


@dataclass(frozen=True, slots=True)
class ReceiptLineSample:
    sample_id: str
    image: str
    text: str
    document_id: str
    split: str | None = None
    source: str | None = None
    metadata: Mapping[str, Any] = field(default_factory=dict)

    @classmethod
    def from_mapping(cls, value: Mapping[str, Any]) -> "ReceiptLineSample":
        sample_id = str(value.get("id", "")).strip()
        image = str(value.get("image", "")).strip()
        text = normalize_transcription(str(value.get("text", "")))
        document_id = str(value.get("document_id", "")).strip()
        raw_split = value.get("split")
        split = str(raw_split).strip().lower() if raw_split is not None else None
        raw_source = value.get("source")
        source = str(raw_source).strip() if raw_source is not None else None
        metadata = value.get("metadata", {})

        if not sample_id:
            raise ValueError("Mỗi mẫu phải có 'id' không rỗng.")
        if not image:
            raise ValueError(f"Mẫu {sample_id!r} thiếu đường dẫn 'image'.")
        if not text:
            raise ValueError(f"Mẫu {sample_id!r} thiếu nhãn 'text'.")
        if not document_id:
            raise ValueError(f"Mẫu {sample_id!r} thiếu 'document_id'.")
        if split is not None and split not in VALID_SPLITS:
            raise ValueError(
                f"Mẫu {sample_id!r} có split {split!r}; "
                f"chỉ chấp nhận {sorted(VALID_SPLITS)}."
            )
        if not isinstance(metadata, Mapping):
            raise ValueError(f"metadata của mẫu {sample_id!r} phải là object JSON.")
        if Path(image).suffix.lower() not in SUPPORTED_IMAGE_SUFFIXES:
            raise ValueError(
                f"Mẫu {sample_id!r} dùng định dạng ảnh không hỗ trợ: {image!r}."
            )

        return cls(
            sample_id=sample_id,
            image=image,
            text=text,
            document_id=document_id,
            split=split,
            source=source,
            metadata=dict(metadata),
        )

    def image_path(self, image_root: Path) -> Path:
        path = Path(self.image)
        return path.resolve() if path.is_absolute() else (image_root / path).resolve()

    def to_mapping(self, *, split: str | None = None) -> dict[str, Any]:
        result: dict[str, Any] = {
            "id": self.sample_id,
            "image": self.image,
            "text": self.text,
            "document_id": self.document_id,
        }
        resolved_split = split if split is not None else self.split
        if resolved_split is not None:
            result["split"] = resolved_split
        if self.source:
            result["source"] = self.source
        if self.metadata:
            result["metadata"] = dict(self.metadata)
        return result

