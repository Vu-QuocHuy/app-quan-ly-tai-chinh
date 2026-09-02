from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile


class PackageReleaseTest(unittest.TestCase):
    def test_packages_only_passing_metrics_with_checksum(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            model_dir = root / "model"
            model_dir.mkdir()
            (model_dir / "inference.pdmodel").write_bytes(b"model")
            charset = root / "charset.txt"
            charset.write_text("A\n", encoding="utf-8")
            dataset_manifest = root / "dataset.json"
            source_manifest = root / "source.json"
            source_manifest.write_text(
                '{"source_license": "Unknown"}\n', encoding="utf-8"
            )
            dataset_manifest.write_text(
                json.dumps(
                    {"sample_count": 3, "source_manifest": str(source_manifest)}
                )
                + "\n",
                encoding="utf-8",
            )
            metrics = root / "metrics.json"
            metrics.write_text('{"gate_passed": true}\n', encoding="utf-8")
            output = root / "release/model.zip"
            script = (
                Path(__file__).resolve().parents[1]
                / "scripts/package_model_release.py"
            )
            subprocess.run(
                [
                    sys.executable,
                    str(script),
                    "--model-version",
                    "test",
                    "--model-dir",
                    str(model_dir),
                    "--charset",
                    str(charset),
                    "--dataset-manifest",
                    str(dataset_manifest),
                    "--metrics",
                    str(metrics),
                    "--output",
                    str(output),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertTrue(output.is_file())
            self.assertTrue(Path(f"{output}.sha256").is_file())
            with zipfile.ZipFile(output) as archive:
                self.assertIn("model-manifest.json", archive.namelist())
                self.assertIn("model/inference.pdmodel", archive.namelist())
                self.assertIn("source_dataset_manifest.json", archive.namelist())


if __name__ == "__main__":
    unittest.main()
