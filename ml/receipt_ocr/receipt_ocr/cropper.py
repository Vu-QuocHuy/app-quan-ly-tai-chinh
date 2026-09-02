from __future__ import annotations

import json
from pathlib import Path
import re
from typing import Any

from .schema import normalize_transcription


_SAFE_FILENAME = re.compile(r"[^A-Za-z0-9._-]+")


def crop_document_annotations(
    documents_path: Path,
    output_dir: Path,
    *,
    image_root: Path | None = None,
    padding: int = 4,
) -> Path:
    if padding < 0:
        raise ValueError("padding phải lớn hơn hoặc bằng 0.")
    try:
        from PIL import Image, ImageOps
    except ImportError as error:
        raise RuntimeError("Cần Pillow để crop ảnh hóa đơn.") from error

    documents_path = documents_path.resolve()
    root = image_root.resolve() if image_root else documents_path.parent
    output_dir = output_dir.resolve()
    crops_dir = output_dir / "images"
    crops_dir.mkdir(parents=True, exist_ok=True)
    output_annotations = output_dir / "annotations.jsonl"
    rows: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    seen_files: set[str] = set()

    with documents_path.open("r", encoding="utf-8") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            if not raw_line.strip():
                continue
            value = json.loads(raw_line)
            if not isinstance(value, dict):
                raise ValueError(f"documents.jsonl dòng {line_number} phải là object.")
            document_id = str(value.get("document_id", "")).strip()
            image_value = str(value.get("image", "")).strip()
            lines = value.get("lines")
            split = value.get("split")
            source = value.get("source")
            if not document_id or not image_value or not isinstance(lines, list):
                raise ValueError(
                    f"Dòng {line_number} thiếu document_id/image/lines hợp lệ."
                )
            image_path = Path(image_value)
            if not image_path.is_absolute():
                image_path = root / image_path
            if not image_path.is_file():
                raise FileNotFoundError(f"Không tìm thấy ảnh hóa đơn: {image_path}")

            with Image.open(image_path) as opened:
                document_image = ImageOps.exif_transpose(opened).convert("RGB")
                width, height = document_image.size
                for line_index, line in enumerate(lines):
                    if not isinstance(line, dict):
                        raise ValueError(
                            f"Line {line_index} của {document_id!r} phải là object."
                        )
                    sample_id = str(line.get("id", "")).strip()
                    text = normalize_transcription(str(line.get("text", "")))
                    bbox = line.get("bbox")
                    if not sample_id or not text:
                        raise ValueError(
                            f"Line {line_index} của {document_id!r} thiếu id/text."
                        )
                    if sample_id in seen_ids:
                        raise ValueError(f"Trùng line id {sample_id!r}.")
                    seen_ids.add(sample_id)
                    if (
                        not isinstance(bbox, list)
                        or len(bbox) != 4
                        or not all(isinstance(item, (int, float)) for item in bbox)
                    ):
                        raise ValueError(
                            f"Line {sample_id!r} cần bbox [x1, y1, x2, y2]."
                        )
                    x1, y1, x2, y2 = (int(round(item)) for item in bbox)
                    x1 = max(0, x1 - padding)
                    y1 = max(0, y1 - padding)
                    x2 = min(width, x2 + padding)
                    y2 = min(height, y2 + padding)
                    if x1 >= x2 or y1 >= y2:
                        raise ValueError(
                            f"Line {sample_id!r} có bbox rỗng/sai thứ tự: {bbox}."
                        )

                    file_stem = _SAFE_FILENAME.sub("-", sample_id).strip("-._")
                    if not file_stem:
                        raise ValueError(f"Line id {sample_id!r} không tạo được filename.")
                    file_name = f"{file_stem}.png"
                    if file_name in seen_files:
                        raise ValueError(
                            f"Các line id tạo trùng filename an toàn: {file_name!r}."
                        )
                    seen_files.add(file_name)
                    crop_path = crops_dir / file_name
                    document_image.crop((x1, y1, x2, y2)).save(
                        crop_path, format="PNG", optimize=True
                    )

                    metadata = line.get("metadata", {})
                    if not isinstance(metadata, dict):
                        raise ValueError(f"metadata của {sample_id!r} phải là object.")
                    if line.get("field") is not None:
                        metadata = {**metadata, "field": str(line["field"])}
                    row: dict[str, Any] = {
                        "id": sample_id,
                        "image": str(Path("images") / file_name),
                        "text": text,
                        "document_id": document_id,
                        "metadata": metadata,
                    }
                    if split is not None:
                        row["split"] = split
                    if source is not None:
                        row["source"] = source
                    rows.append(row)

    if not rows:
        raise ValueError("Không có line annotation nào để crop.")
    with output_annotations.open("w", encoding="utf-8", newline="\n") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")
    return output_annotations

