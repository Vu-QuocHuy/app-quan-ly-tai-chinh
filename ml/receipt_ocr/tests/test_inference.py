from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from receipt_ocr.inference import extract_recognition_payload, load_prediction_inputs


class _Result:
    def __init__(self, value):
        self.json = value


class InferenceTest(unittest.TestCase):
    def test_extracts_nested_and_direct_payload(self) -> None:
        nested = extract_recognition_payload(
            _Result({"res": {"rec_text": "TỔNG TIỀN", "rec_score": 0.98}})
        )
        direct = extract_recognition_payload(
            _Result({"rec_text": "125.000 ₫", "rec_score": 0.97})
        )
        self.assertEqual(nested["rec_text"], "TỔNG TIỀN")
        self.assertEqual(direct["rec_score"], 0.97)

    def test_loads_only_requested_split(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            image = root / "line.png"
            image.write_bytes(b"image")
            samples = root / "samples.jsonl"
            samples.write_text(
                json.dumps(
                    {
                        "id": "test-line",
                        "image": "line.png",
                        "resolved_image": str(image),
                        "text": "TỔNG CỘNG",
                        "document_id": "receipt-test",
                        "split": "test",
                        "metadata": {"field": "total"},
                    },
                    ensure_ascii=False,
                )
                + "\n",
                encoding="utf-8",
            )
            inputs = load_prediction_inputs(samples, "test")
            self.assertEqual(len(inputs), 1)
            self.assertEqual(inputs[0].field, "total")


if __name__ == "__main__":
    unittest.main()

