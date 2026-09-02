from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image

from receipt_ocr.cropper import crop_document_annotations


class CropperTest(unittest.TestCase):
    def test_crops_document_lines_and_writes_training_annotations(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            receipt = root / "receipt.png"
            Image.new("RGB", (200, 100), "white").save(receipt)
            documents = root / "documents.jsonl"
            documents.write_text(
                json.dumps(
                    {
                        "document_id": "receipt-1",
                        "image": receipt.name,
                        "split": "train",
                        "lines": [
                            {
                                "id": "receipt-1-line-1",
                                "bbox": [10, 20, 180, 60],
                                "text": "TỔNG CỘNG 125.000 ₫",
                                "field": "total",
                            }
                        ],
                    },
                    ensure_ascii=False,
                )
                + "\n",
                encoding="utf-8",
            )

            annotations = crop_document_annotations(documents, root / "output")
            row = json.loads(annotations.read_text(encoding="utf-8"))
            crop = annotations.parent / row["image"]
            self.assertTrue(crop.is_file())
            self.assertEqual(row["metadata"]["field"], "total")
            with Image.open(crop) as image:
                self.assertEqual(image.size, (178, 48))


if __name__ == "__main__":
    unittest.main()

