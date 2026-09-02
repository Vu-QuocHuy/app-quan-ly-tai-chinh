from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from receipt_ocr.dataset import prepare_dataset
from receipt_ocr.mcocr import _derive_document_id, convert_mcocr_dataset


class McOcrConverterTest(unittest.TestCase):
    def test_groups_real_mcocr_filename_pattern_by_receipt(self) -> None:
        root = Path("/dataset")
        first = _derive_document_id(
            root / "train_images/mcocr_public_145013snoxg_0.jpg", root
        )
        second = _derive_document_id(
            root / "train_images/mcocr_public_145013snoxg_10.jpg", root
        )
        other = _derive_document_id(
            root / "train_images/mcocr_public_145013jyzhp_0.jpg", root
        )
        self.assertEqual(first, second)
        self.assertNotEqual(first, other)

    def test_converts_train_and_official_validation_to_locked_test(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            images = root / "text_recognition_mcocr_data/train_images"
            images.mkdir(parents=True)
            train_lines = []
            for index in range(20):
                image = images / f"receipt_{index:03d}_line_0.png"
                image.write_bytes(f"train-{index}".encode())
                train_lines.append(
                    f"text_recognition_mcocr_data/train_images/{image.name}\t"
                    f"TỔNG CỘNG {index}.000 ₫\n"
                )
            long_image = images / "receipt_000_line_1.png"
            long_image.write_bytes(b"long")
            train_lines.append(f"{long_image}\t{'A' * 65}\n")
            test_image = images / "receipt_999_line_0.png"
            test_image.write_bytes(b"test")
            (root / "text_recognition_train_data.txt").write_text(
                "".join(train_lines), encoding="utf-8"
            )
            (root / "text_recognition_val_data.txt").write_text(
                f"{test_image}\tNgày 31/08/2026\n", encoding="utf-8"
            )

            annotations = convert_mcocr_dataset(root, root / "converted")
            rows = [
                json.loads(line)
                for line in annotations.read_text(encoding="utf-8").splitlines()
            ]
            splits = {row["split"] for row in rows}
            self.assertIn("train", splits)
            self.assertIn("validation", splits)
            self.assertIn("test", splits)
            self.assertEqual(
                [row for row in rows if row["split"] == "test"][0]["text"],
                "Ngày 31/08/2026",
            )
            manifest = json.loads(
                (root / "converted/mcocr_conversion_manifest.json").read_text()
            )
            self.assertEqual(manifest["source_license"], "Unknown")
            self.assertFalse(manifest["redistribution_allowed"])
            self.assertEqual(manifest["excluded_too_long_count"], 1)
            self.assertNotIn("A" * 65, {row["text"] for row in rows})

            prepared = prepare_dataset(
                annotations, root / "prepared", image_root=root
            )
            dataset_manifest = json.loads(
                prepared.manifest_path.read_text(encoding="utf-8")
            )
            self.assertEqual(dataset_manifest["source_dataset_version"], 17)
            self.assertEqual(dataset_manifest["source_license"], "Unknown")
            self.assertFalse(dataset_manifest["redistribution_allowed"])


if __name__ == "__main__":
    unittest.main()
