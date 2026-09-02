from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
import json
from pathlib import Path
from typing import Any, Iterable


@dataclass(frozen=True, slots=True)
class PredictionInput:
    sample_id: str
    image_path: Path
    split: str
    field: str


@dataclass(frozen=True, slots=True)
class PredictionRecord:
    sample_id: str
    image: str
    prediction: str
    confidence: float
    split: str
    field: str
    model: str

    def to_dict(self) -> dict[str, str | float]:
        return {
            "id": self.sample_id,
            "image": self.image,
            "prediction": self.prediction,
            "confidence": self.confidence,
            "split": self.split,
            "field": self.field,
            "model": self.model,
        }


def load_prediction_inputs(samples_path: Path, split: str) -> list[PredictionInput]:
    inputs: list[PredictionInput] = []
    with samples_path.open("r", encoding="utf-8") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            if not raw_line.strip():
                continue
            value = json.loads(raw_line)
            if value.get("split") != split:
                continue
            sample_id = str(value.get("id", "")).strip()
            resolved_image = str(value.get("resolved_image", value.get("image", "")))
            if not sample_id or not resolved_image:
                raise ValueError(
                    f"samples.jsonl dòng {line_number} thiếu id/resolved_image."
                )
            metadata = value.get("metadata", {})
            field = (
                str(metadata.get("field", "untyped"))
                if isinstance(metadata, Mapping)
                else "untyped"
            )
            inputs.append(
                PredictionInput(
                    sample_id=sample_id,
                    image_path=Path(resolved_image).resolve(),
                    split=split,
                    field=field,
                )
            )
    if not inputs:
        raise ValueError(f"Không có mẫu thuộc split {split!r} trong {samples_path}.")
    missing = [item for item in inputs if not item.image_path.is_file()]
    if missing:
        raise FileNotFoundError(
            f"Không tìm thấy ảnh của {missing[0].sample_id!r}: {missing[0].image_path}"
        )
    return inputs


def extract_recognition_payload(result: Any) -> dict[str, Any]:
    raw = getattr(result, "json", None)
    if callable(raw):
        raw = raw()
    if raw is None and isinstance(result, Mapping):
        raw = result
    if isinstance(raw, str):
        raw = json.loads(raw)
    if not isinstance(raw, Mapping):
        raise TypeError(
            "PaddleOCR result không cung cấp mapping qua thuộc tính .json."
        )
    payload = raw.get("res", raw)
    if not isinstance(payload, Mapping):
        raise TypeError("PaddleOCR result có trường 'res' không hợp lệ.")
    if "rec_text" not in payload or "rec_score" not in payload:
        raise KeyError("PaddleOCR result thiếu rec_text/rec_score.")
    return dict(payload)


def predict_text_lines(
    inputs: Iterable[PredictionInput],
    *,
    model_dir: Path | None = None,
    model_name: str | None = None,
    device: str = "gpu:0",
    engine: str = "paddle_static",
    batch_size: int = 32,
) -> list[PredictionRecord]:
    values = list(inputs)
    if not values:
        raise ValueError("Cần ít nhất một ảnh để inference.")
    if (model_dir is None) == (model_name is None):
        raise ValueError("Chọn đúng một trong model_dir hoặc model_name.")
    if batch_size <= 0:
        raise ValueError("batch_size phải lớn hơn 0.")

    try:
        from paddleocr import TextRecognition
    except ImportError as error:
        raise RuntimeError(
            "Chưa cài paddleocr/PaddlePaddle. Hãy chạy setup Kaggle trước."
        ) from error

    model_id = str(model_dir.resolve()) if model_dir is not None else str(model_name)
    kwargs: dict[str, Any] = {"device": device, "engine": engine}
    if model_dir is not None:
        kwargs["model_dir"] = str(model_dir.resolve())
    else:
        kwargs["model_name"] = model_name
    model = TextRecognition(**kwargs)
    results = list(
        model.predict(
            input=[str(item.image_path) for item in values],
            batch_size=batch_size,
        )
    )
    if len(results) != len(values):
        raise RuntimeError(
            f"PaddleOCR trả {len(results)} kết quả cho {len(values)} ảnh."
        )

    predictions: list[PredictionRecord] = []
    for item, result in zip(values, results, strict=True):
        payload = extract_recognition_payload(result)
        confidence = float(payload["rec_score"])
        if not 0 <= confidence <= 1:
            raise ValueError(
                f"Confidence ngoài [0, 1] cho mẫu {item.sample_id!r}: {confidence}"
            )
        predictions.append(
            PredictionRecord(
                sample_id=item.sample_id,
                image=str(item.image_path),
                prediction=str(payload["rec_text"]),
                confidence=confidence,
                split=item.split,
                field=item.field,
                model=model_id,
            )
        )
    return predictions

