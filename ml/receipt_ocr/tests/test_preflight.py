from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from receipt_ocr.preflight import inspect_dataset


class PreflightTest(unittest.TestCase):
    def test_accepts_three_unique_explicit_splits(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            rows = []
            for index, split in enumerate(["train", "validation", "test"]):
                image = root / f"line-{index}.png"
                image.write_bytes(f"image-{index}".encode())
                rows.append(
                    {
                        "id": f"line-{index}",
                        "image": image.name,
                        "text": f"TỔNG TIỀN {index}.000 ₫",
                        "document_id": f"receipt-{index}",
                        "split": split,
                        "metadata": {"field": "total"},
                    }
                )
            annotations = root / "annotations.jsonl"
            annotations.write_text(
                "".join(
                    json.dumps(row, ensure_ascii=False) + "\n" for row in rows
                ),
                encoding="utf-8",
            )

            report = inspect_dataset(
                annotations,
                minimum_documents=3,
                decode_images=False,
            )
            self.assertTrue(report.ok)
            self.assertEqual(report.field_counts["total"], 3)

    def test_rejects_duplicate_image_across_splits(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            rows = []
            for index, split in enumerate(["train", "validation", "test"]):
                image = root / f"line-{index}.png"
                image.write_bytes(b"same-image" if index < 2 else b"unique")
                rows.append(
                    {
                        "id": f"line-{index}",
                        "image": image.name,
                        "text": f"DÒNG {index}",
                        "document_id": f"receipt-{index}",
                        "split": split,
                    }
                )
            annotations = root / "annotations.jsonl"
            annotations.write_text(
                "".join(
                    json.dumps(row, ensure_ascii=False) + "\n" for row in rows
                ),
                encoding="utf-8",
            )

            report = inspect_dataset(
                annotations,
                minimum_documents=3,
                decode_images=False,
            )
            self.assertFalse(report.ok)
            self.assertTrue(
                any(issue.code == "duplicate_image_across_splits" for issue in report.issues)
            )


if __name__ == "__main__":
    unittest.main()

