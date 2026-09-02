#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from receipt_ocr.metrics import OcrPair, calculate_ocr_metrics, levenshtein_distance
from receipt_ocr.schema import ReceiptLineSample, normalize_transcription


def _load_ground_truth(path: Path, split: str | None) -> dict[str, ReceiptLineSample]:
    result: dict[str, ReceiptLineSample] = {}
    with path.open("r", encoding="utf-8") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            if not raw_line.strip():
                continue
            value = json.loads(raw_line)
            sample = ReceiptLineSample.from_mapping(value)
            if split is not None and sample.split != split:
                continue
            if sample.sample_id in result:
                raise ValueError(f"Ground-truth trùng id {sample.sample_id!r}.")
            result[sample.sample_id] = sample
    if not result:
        raise ValueError("Không có ground-truth phù hợp để đánh giá.")
    return result


def _load_predictions(path: Path) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    with path.open("r", encoding="utf-8") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            if not raw_line.strip():
                continue
            value = json.loads(raw_line)
            sample_id = str(value.get("id", "")).strip()
            if not sample_id:
                raise ValueError(f"Prediction dòng {line_number} thiếu 'id'.")
            if sample_id in result:
                raise ValueError(f"Prediction trùng id {sample_id!r}.")
            prediction = value.get("prediction", value.get("text"))
            if prediction is None:
                raise ValueError(
                    f"Prediction {sample_id!r} thiếu 'prediction' hoặc 'text'."
                )
            confidence = value.get("confidence")
            result[sample_id] = {
                "prediction": str(prediction),
                "confidence": float(confidence) if confidence is not None else None,
            }
    return result


def _parse_gate(value: str) -> tuple[str, float]:
    field, separator, raw_threshold = value.partition("=")
    if not separator or not field.strip():
        raise argparse.ArgumentTypeError("Gate phải có dạng field=threshold.")
    try:
        threshold = float(raw_threshold)
    except ValueError as error:
        raise argparse.ArgumentTypeError("Threshold phải là số.") from error
    if not 0 <= threshold <= 1:
        raise argparse.ArgumentTypeError("Threshold phải nằm trong [0, 1].")
    return field.strip(), threshold


def main() -> None:
    parser = argparse.ArgumentParser(description="Calculate receipt OCR CER/WER metrics.")
    parser.add_argument("--ground-truth", type=Path, required=True)
    parser.add_argument("--predictions", type=Path, required=True)
    parser.add_argument("--split", choices=["train", "validation", "test"])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--max-cer", type=float)
    parser.add_argument("--min-exact-match", type=float)
    parser.add_argument("--min-coverage", type=float, default=1.0)
    parser.add_argument(
        "--field-min-exact",
        action="append",
        default=[],
        type=_parse_gate,
        metavar="FIELD=VALUE",
    )
    parser.add_argument(
        "--field-max-cer",
        action="append",
        default=[],
        type=_parse_gate,
        metavar="FIELD=VALUE",
    )
    args = parser.parse_args()

    ground_truth = _load_ground_truth(args.ground_truth, args.split)
    predictions = _load_predictions(args.predictions)
    unknown = sorted(set(predictions) - set(ground_truth))
    missing = sorted(set(ground_truth) - set(predictions))
    if unknown:
        raise ValueError(f"Prediction chứa id không có trong ground-truth: {unknown[:5]}")

    pairs = []
    pairs_by_field: dict[str, list[OcrPair]] = {}
    errors = []
    for sample_id, sample in ground_truth.items():
        predicted = predictions.get(sample_id, {"prediction": "", "confidence": None})
        pair = OcrPair(
            sample_id=sample_id,
            reference=sample.text,
            prediction=predicted["prediction"],
            confidence=predicted["confidence"],
        )
        pairs.append(pair)
        field = str(sample.metadata.get("field", "untyped"))
        pairs_by_field.setdefault(field, []).append(pair)
        reference = normalize_transcription(pair.reference)
        prediction = normalize_transcription(pair.prediction)
        errors.append(
            {
                "id": sample_id,
                "reference": reference,
                "prediction": prediction,
                "character_edits": levenshtein_distance(reference, prediction),
            }
        )

    metrics = calculate_ocr_metrics(pairs)
    coverage = (len(ground_truth) - len(missing)) / len(ground_truth)
    field_metrics = {
        field: calculate_ocr_metrics(field_pairs).to_dict()
        for field, field_pairs in sorted(pairs_by_field.items())
    }
    gate_failures: list[str] = []
    if args.max_cer is not None and metrics.character_error_rate > args.max_cer:
        gate_failures.append(
            f"CER {metrics.character_error_rate:.4f} > {args.max_cer:.4f}"
        )
    if args.min_exact_match is not None and metrics.exact_match < args.min_exact_match:
        gate_failures.append(
            f"exact_match {metrics.exact_match:.4f} < {args.min_exact_match:.4f}"
        )
    if coverage < args.min_coverage:
        gate_failures.append(f"coverage {coverage:.4f} < {args.min_coverage:.4f}")
    for field, threshold in args.field_min_exact:
        value = field_metrics.get(field)
        if value is None:
            gate_failures.append(f"field {field!r} không có ground-truth")
        elif value["exact_match"] < threshold:
            gate_failures.append(
                f"field {field!r} exact_match {value['exact_match']:.4f} < "
                f"{threshold:.4f}"
            )
    for field, threshold in args.field_max_cer:
        value = field_metrics.get(field)
        if value is None:
            gate_failures.append(f"field {field!r} không có ground-truth")
        elif value["character_error_rate"] > threshold:
            gate_failures.append(
                f"field {field!r} CER {value['character_error_rate']:.4f} > "
                f"{threshold:.4f}"
            )
    report = {
        "metrics": metrics.to_dict(),
        "prediction_coverage": coverage,
        "field_metrics": field_metrics,
        "gate_passed": not gate_failures,
        "gate_failures": gate_failures,
        "missing_prediction_count": len(missing),
        "missing_prediction_ids": missing,
        "largest_errors": sorted(
            errors, key=lambda item: item["character_edits"], reverse=True
        )[:20],
    }
    output = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True)
    print(output)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output + "\n", encoding="utf-8")

    if gate_failures:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
