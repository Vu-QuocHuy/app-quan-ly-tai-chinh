from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class EvaluationCliTest(unittest.TestCase):
    def test_reports_field_metrics_and_passes_gate(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            ground_truth = root / "samples.jsonl"
            predictions = root / "predictions.jsonl"
            report = root / "metrics.json"
            ground_truth.write_text(
                json.dumps(
                    {
                        "id": "total-1",
                        "image": "line.png",
                        "text": "TỔNG CỘNG 125.000 ₫",
                        "document_id": "receipt-1",
                        "split": "test",
                        "metadata": {"field": "total"},
                    },
                    ensure_ascii=False,
                )
                + "\n",
                encoding="utf-8",
            )
            predictions.write_text(
                json.dumps(
                    {
                        "id": "total-1",
                        "prediction": "TỔNG CỘNG 125.000 ₫",
                        "confidence": 0.99,
                    },
                    ensure_ascii=False,
                )
                + "\n",
                encoding="utf-8",
            )
            script = Path(__file__).resolve().parents[1] / "scripts/evaluate_predictions.py"
            subprocess.run(
                [
                    sys.executable,
                    str(script),
                    "--ground-truth",
                    str(ground_truth),
                    "--predictions",
                    str(predictions),
                    "--split",
                    "test",
                    "--field-min-exact",
                    "total=0.90",
                    "--output",
                    str(report),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            value = json.loads(report.read_text(encoding="utf-8"))
            self.assertTrue(value["gate_passed"])
            self.assertEqual(value["prediction_coverage"], 1.0)
            self.assertEqual(value["field_metrics"]["total"]["exact_match"], 1.0)


if __name__ == "__main__":
    unittest.main()

