from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import shlex
import subprocess
import sys
from typing import Sequence

import yaml


@dataclass(frozen=True, slots=True)
class PaddleTrainJob:
    paddleocr_dir: Path
    prepared_dir: Path
    output_dir: Path
    base_config: str = "configs/rec/PP-OCRv5/PP-OCRv5_mobile_rec.yml"
    pretrained_model: Path | None = None
    epochs: int = 30
    train_batch_size: int = 32
    eval_batch_size: int = 32
    learning_rate: float = 0.0005
    max_text_length: int = 64
    num_workers: int = 2
    eval_batch_step: int = 200
    use_gpu: bool = True
    extra_overrides: Sequence[str] = field(default_factory=tuple)

    def command(self) -> list[str]:
        paddleocr_dir = self.paddleocr_dir.resolve()
        prepared_dir = self.prepared_dir.resolve()
        config_path = (paddleocr_dir / self.base_config).resolve()
        train_script = paddleocr_dir / "tools" / "train.py"
        _require_file(train_script, "PaddleOCR tools/train.py")
        _require_file(config_path, "PaddleOCR base config")
        _require_nonempty_file(prepared_dir / "train.txt", "prepared train split")
        _require_nonempty_file(
            prepared_dir / "validation.txt", "prepared validation split"
        )
        _require_file(
            prepared_dir / "vietnamese_receipt_charset.txt", "receipt charset"
        )
        if self.epochs <= 0 or self.train_batch_size <= 0 or self.eval_batch_size <= 0:
            raise ValueError("epochs và batch size phải lớn hơn 0.")
        if self.learning_rate <= 0 or self.max_text_length <= 0:
            raise ValueError("learning_rate và max_text_length phải lớn hơn 0.")
        if self.num_workers < 0:
            raise ValueError("num_workers phải lớn hơn hoặc bằng 0.")
        if self.eval_batch_step <= 0:
            raise ValueError("eval_batch_step phải lớn hơn 0.")

        output_dir = self.output_dir.resolve()
        output_dir.mkdir(parents=True, exist_ok=True)
        config = _load_config(config_path)
        global_config = config.setdefault("Global", {})
        global_config.update(
            {
                "use_gpu": self.use_gpu,
                "epoch_num": self.epochs,
                "save_model_dir": str(output_dir),
                "use_space_char": True,
                "save_epoch_step": 1,
                "character_dict_path": str(
                    prepared_dir / "vietnamese_receipt_charset.txt"
                ),
                "max_text_length": self.max_text_length,
                "eval_batch_step": [0, self.eval_batch_step],
                "calc_epoch_interval": 1,
            }
        )
        _replace_key_recursive(config, "max_text_length", self.max_text_length)
        if self.pretrained_model is not None:
            _require_file(self.pretrained_model.resolve(), "pretrained model")
            global_config["pretrained_model"] = str(self.pretrained_model.resolve())
        else:
            global_config["pretrained_model"] = None

        _configure_dataset(
            config.setdefault("Train", {}),
            label_file=prepared_dir / "train.txt",
            batch_size=self.train_batch_size,
            num_workers=self.num_workers,
            max_text_length=self.max_text_length,
            training=True,
        )
        _configure_dataset(
            config.setdefault("Eval", {}),
            label_file=prepared_dir / "validation.txt",
            batch_size=self.eval_batch_size,
            num_workers=self.num_workers,
            max_text_length=self.max_text_length,
            training=False,
        )
        optimizer = config.setdefault("Optimizer", {})
        optimizer.setdefault("lr", {})["learning_rate"] = self.learning_rate
        resolved_config = output_dir / "resolved_train_config.yml"
        _write_config(resolved_config, config)

        command = [
            sys.executable,
            str(train_script),
            "-c",
            str(resolved_config),
        ]
        if self.extra_overrides:
            command.extend(["-o", *self.extra_overrides])
        return command


@dataclass(frozen=True, slots=True)
class PaddleExportJob:
    paddleocr_dir: Path
    prepared_dir: Path
    checkpoint: Path
    output_dir: Path
    base_config: str = "configs/rec/PP-OCRv5/PP-OCRv5_mobile_rec.yml"
    max_text_length: int = 64
    extra_overrides: Sequence[str] = field(default_factory=tuple)

    def command(self) -> list[str]:
        paddleocr_dir = self.paddleocr_dir.resolve()
        prepared_dir = self.prepared_dir.resolve()
        export_script = paddleocr_dir / "tools" / "export_model.py"
        config_path = (paddleocr_dir / self.base_config).resolve()
        _require_file(export_script, "PaddleOCR tools/export_model.py")
        _require_file(config_path, "PaddleOCR base config")
        _require_file(
            prepared_dir / "vietnamese_receipt_charset.txt", "receipt charset"
        )
        _require_checkpoint(self.checkpoint.resolve())
        if self.max_text_length <= 0:
            raise ValueError("max_text_length phải lớn hơn 0.")
        output_dir = self.output_dir.resolve()
        output_dir.mkdir(parents=True, exist_ok=True)
        config = _load_config(config_path)
        global_config = config.setdefault("Global", {})
        global_config.update(
            {
                "pretrained_model": str(self.checkpoint.resolve()),
                "save_inference_dir": str(output_dir),
                "use_space_char": True,
                "character_dict_path": str(
                    prepared_dir / "vietnamese_receipt_charset.txt"
                ),
            }
        )
        _replace_key_recursive(config, "max_text_length", self.max_text_length)
        resolved_config = output_dir / "resolved_export_config.yml"
        _write_config(resolved_config, config)
        command = [
            sys.executable,
            str(export_script),
            "-c",
            str(resolved_config),
        ]
        if self.extra_overrides:
            command.extend(["-o", *self.extra_overrides])
        return command


def run_command(command: Sequence[str], *, dry_run: bool = False) -> None:
    print(shlex.join(command), flush=True)
    if not dry_run:
        subprocess.run(command, check=True)


def _require_file(path: Path, label: str) -> None:
    if not path.is_file():
        raise FileNotFoundError(f"Không tìm thấy {label}: {path}")


def _require_nonempty_file(path: Path, label: str) -> None:
    _require_file(path, label)
    if path.stat().st_size == 0:
        raise ValueError(
            f"{label} đang rỗng: {path}. Hãy gán split rõ ràng hoặc bổ sung dữ liệu."
        )


def _require_checkpoint(path: Path) -> None:
    if path.is_file() or Path(f"{path}.pdparams").is_file():
        return
    raise FileNotFoundError(
        f"Không tìm thấy checkpoint {path} hoặc {path}.pdparams"
    )


def _load_config(path: Path) -> dict:
    value = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"PaddleOCR config phải là YAML object: {path}")
    return value


def _write_config(path: Path, config: dict) -> None:
    path.write_text(
        yaml.safe_dump(config, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


def _replace_key_recursive(value: object, key: str, replacement: object) -> None:
    if isinstance(value, dict):
        for current_key, child in value.items():
            if current_key == key:
                value[current_key] = replacement
            else:
                _replace_key_recursive(child, key, replacement)
    elif isinstance(value, list):
        for child in value:
            _replace_key_recursive(child, key, replacement)


def _configure_dataset(
    section: dict,
    *,
    label_file: Path,
    batch_size: int,
    num_workers: int,
    max_text_length: int,
    training: bool,
) -> None:
    dataset = section.setdefault("dataset", {})
    dataset["data_dir"] = "/"
    dataset["label_file_list"] = [str(label_file)]
    transforms = dataset.get("transforms", [])
    if isinstance(transforms, list):
        for transform in transforms:
            if not isinstance(transform, dict):
                continue
            augmentation = transform.get("RecConAug")
            if isinstance(augmentation, dict):
                augmentation["max_text_length"] = max_text_length
    loader = section.setdefault("loader", {})
    loader["batch_size_per_card"] = batch_size
    loader["num_workers"] = num_workers
    if training:
        sampler = section.get("sampler")
        if isinstance(sampler, dict) and "first_bs" in sampler:
            sampler["first_bs"] = batch_size
