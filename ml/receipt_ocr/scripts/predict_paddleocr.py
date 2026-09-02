#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from receipt_ocr.inference import load_prediction_inputs, predict_text_lines


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run PaddleOCR text recognition and write prediction JSONL."
    )
    parser.add_argument("--samples", type=Path, required=True)
    model = parser.add_mutually_exclusive_group(required=True)
    model.add_argument("--model-dir", type=Path)
    model.add_argument("--model-name")
    parser.add_argument("--split", choices=["validation", "test"], default="test")
    parser.add_argument("--device", default="gpu:0")
    parser.add_argument("--engine", default="paddle_static")
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    inputs = load_prediction_inputs(args.samples, args.split)
    if args.limit is not None:
        if args.limit <= 0:
            raise ValueError("--limit phải lớn hơn 0.")
        inputs = inputs[: args.limit]
    predictions = predict_text_lines(
        inputs,
        model_dir=args.model_dir,
        model_name=args.model_name,
        device=args.device,
        engine=args.engine,
        batch_size=args.batch_size,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="\n") as handle:
        for prediction in predictions:
            handle.write(
                json.dumps(prediction.to_dict(), ensure_ascii=False, sort_keys=True)
                + "\n"
            )
    print(f"Predictions: {len(predictions)} -> {args.output.resolve()}")


if __name__ == "__main__":
    main()

