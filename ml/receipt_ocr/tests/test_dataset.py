from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from receipt_ocr.dataset import assign_document_splits, load_jsonl, prepare_dataset
from receipt_ocr.schema import ReceiptLineSample


class DatasetTest(unittest.TestCase):
    def test_prepare_dataset_keeps_documents_in_one_split(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            images = root / "images"
            images.mkdir()
            rows = []
            for document_index in range(12):
                for line_index in range(2):
                    image = images / f"d{document_index}-l{line_index}.png"
                    image.write_bytes(b"not-decoded-by-the-preparer")
                    rows.append(
                        {
                            "id": f"d{document_index}-l{line_index}",
                            "image": str(image.relative_to(root)),
                            "text": f"TỔNG TIỀN {document_index}.000 ₫",
                            "document_id": f"document-{document_index}",
                            "source": "test",
                        }
                    )
            annotations = root / "annotations.jsonl"
            annotations.write_text(
                "".join(
                    json.dumps(row, ensure_ascii=False) + "\n" for row in rows
                ),
                encoding="utf-8",
            )

            prepared = prepare_dataset(annotations, root / "prepared")
            samples = load_jsonl(annotations)
            assignments = assign_document_splits(samples)

            self.assertEqual(len(assignments), 12)
            self.assertTrue(prepared.manifest_path.is_file())
            self.assertTrue(prepared.charset_path.is_file())
            self.assertIn("₫", prepared.charset_path.read_text(encoding="utf-8"))
            split_rows = [
                json.loads(line)
                for line in prepared.split_samples_path.read_text(
                    encoding="utf-8"
                ).splitlines()
            ]
            by_document: dict[str, set[str]] = {}
            for row in split_rows:
                by_document.setdefault(row["document_id"], set()).add(row["split"])
            self.assertTrue(all(len(splits) == 1 for splits in by_document.values()))

    def test_conflicting_explicit_splits_are_rejected(self) -> None:
        samples = [
            ReceiptLineSample("a", "a.png", "A", "receipt", split="train"),
            ReceiptLineSample("b", "b.png", "B", "receipt", split="test"),
        ]
        with self.assertRaisesRegex(ValueError, "nhiều split"):
            assign_document_splits(samples)

    def test_duplicate_ids_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            image = root / "line.png"
            image.write_bytes(b"image")
            row = {
                "id": "same",
                "image": "line.png",
                "text": "HÓA ĐƠN",
                "document_id": "receipt",
            }
            annotations = root / "annotations.jsonl"
            annotations.write_text(
                json.dumps(row, ensure_ascii=False)
                + "\n"
                + json.dumps(row, ensure_ascii=False)
                + "\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "Trùng id"):
                load_jsonl(annotations)


if __name__ == "__main__":
    unittest.main()

