from __future__ import annotations

from pathlib import Path
import tempfile
import unittest

from receipt_ocr.paddle_runner import PaddleExportJob, PaddleTrainJob


class PaddleRunnerTest(unittest.TestCase):
    def test_builds_train_and_export_commands_without_shell(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            paddle = root / "PaddleOCR"
            config = paddle / "configs/rec/PP-OCRv5/PP-OCRv5_mobile_rec.yml"
            train_script = paddle / "tools/train.py"
            export_script = paddle / "tools/export_model.py"
            prepared = root / "prepared"
            for path in [config, train_script, export_script]:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(
                    """
Global:
  max_text_length: 25
Architecture:
  Head:
    head_list:
      - NRTRHead:
          max_text_length: 25
Optimizer:
  lr:
    learning_rate: 0.001
Train:
  dataset:
    transforms:
      - RecConAug:
          max_text_length: 25
  sampler:
    first_bs: 128
  loader:
    batch_size_per_card: 128
Eval:
  dataset:
    transforms: []
  loader:
    batch_size_per_card: 128
""".lstrip(),
                    encoding="utf-8",
                )
            prepared.mkdir()
            for name in [
                "train.txt",
                "validation.txt",
                "vietnamese_receipt_charset.txt",
            ]:
                (prepared / name).write_text("fixture\n", encoding="utf-8")
            pretrained = root / "pretrained.pdparams"
            pretrained.write_bytes(b"weights")
            (root / "best_accuracy.pdparams").write_bytes(b"checkpoint")

            train_command = PaddleTrainJob(
                paddleocr_dir=paddle,
                prepared_dir=prepared,
                output_dir=root / "train-output",
                epochs=2,
                pretrained_model=pretrained,
            ).command()
            export_command = PaddleExportJob(
                paddleocr_dir=paddle,
                prepared_dir=prepared,
                checkpoint=root / "best_accuracy",
                output_dir=root / "inference",
            ).command()

            train_config = (root / "train-output/resolved_train_config.yml").read_text(
                encoding="utf-8"
            )
            export_config = (root / "inference/resolved_export_config.yml").read_text(
                encoding="utf-8"
            )
            self.assertIn("resolved_train_config.yml", train_command[-1])
            self.assertIn("epoch_num: 2", train_config)
            self.assertIn("max_text_length: 64", train_config)
            self.assertIn("eval_batch_step:", train_config)
            self.assertIn("- 200", train_config)
            self.assertIn("pretrained_model:", train_config)
            self.assertIn("resolved_export_config.yml", export_command[-1])
            self.assertIn("save_inference_dir:", export_config)
            self.assertNotIn("max_text_length: 25", train_config)
            self.assertNotIn("max_text_length: 25", export_config)
            self.assertIn("max_text_length: 64", export_config)


if __name__ == "__main__":
    unittest.main()
