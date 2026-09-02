#!/usr/bin/env python3
from __future__ import annotations

import argparse
from importlib import metadata
import json
from pathlib import Path
import platform
import subprocess
import sys
import tempfile


def _package_version(name: str) -> str | None:
    try:
        return metadata.version(name)
    except metadata.PackageNotFoundError:
        return None


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Verify Kaggle GPU/runtime paths before OCR training."
    )
    parser.add_argument("--paddleocr-dir", type=Path, required=True)
    parser.add_argument("--expected-paddleocr-tag", default="v3.7.0")
    parser.add_argument("--expected-paddle-version", default="3.2.0")
    parser.add_argument("--pretrained-model", type=Path, required=True)
    parser.add_argument("--dataset-dir", type=Path, required=True)
    parser.add_argument("--work-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    errors: list[str] = []
    warnings: list[str] = []
    report: dict[str, object] = {
        "python": sys.version,
        "platform": platform.platform(),
        "packages": {
            "paddleocr": _package_version("paddleocr"),
            "paddlepaddle-gpu": _package_version("paddlepaddle-gpu"),
            "paddlepaddle": _package_version("paddlepaddle"),
            "Pillow": _package_version("Pillow"),
            "PyYAML": _package_version("PyYAML"),
        },
    }

    expected_config = (
        args.paddleocr_dir
        / "configs/rec/PP-OCRv5/PP-OCRv5_mobile_rec.yml"
    )
    for label, path, kind in [
        ("PaddleOCR source", args.paddleocr_dir, "dir"),
        ("PP-OCRv5 config", expected_config, "file"),
        ("pretrained model", args.pretrained_model, "file"),
        ("dataset", args.dataset_dir, "dir"),
    ]:
        exists = path.is_dir() if kind == "dir" else path.is_file()
        if not exists:
            errors.append(f"Không tìm thấy {label}: {path}")

    if args.paddleocr_dir.is_dir():
        try:
            revision = subprocess.run(
                ["git", "-C", str(args.paddleocr_dir), "describe", "--tags", "--exact-match"],
                check=True,
                capture_output=True,
                text=True,
                timeout=15,
            ).stdout.strip()
            report["paddleocr_source_tag"] = revision
            if revision != args.expected_paddleocr_tag:
                errors.append(
                    f"PaddleOCR source tag là {revision!r}, cần "
                    f"{args.expected_paddleocr_tag!r}."
                )
        except (FileNotFoundError, subprocess.SubprocessError) as error:
            errors.append(f"Không xác minh được PaddleOCR source tag: {error}")

    args.work_dir.mkdir(parents=True, exist_ok=True)
    try:
        with tempfile.NamedTemporaryFile(dir=args.work_dir, delete=True):
            pass
    except OSError as error:
        errors.append(f"Không ghi được WORK_DIR {args.work_dir}: {error}")

    try:
        gpu = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=name,driver_version,memory.total",
                "--format=csv,noheader",
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=15,
        )
        report["nvidia_smi"] = [
            line.strip() for line in gpu.stdout.splitlines() if line.strip()
        ]
    except (FileNotFoundError, subprocess.SubprocessError) as error:
        errors.append(f"Không gọi được nvidia-smi: {error}")

    try:
        import paddle

        report["paddle"] = {
            "version": paddle.__version__,
            "compiled_with_cuda": paddle.device.is_compiled_with_cuda(),
            "cuda_device_count": paddle.device.cuda.device_count(),
        }
        if not paddle.device.is_compiled_with_cuda():
            errors.append("PaddlePaddle hiện tại không được build với CUDA.")
        elif paddle.device.cuda.device_count() < 1:
            errors.append("PaddlePaddle không nhìn thấy GPU nào.")
    except Exception as error:
        errors.append(f"Không import/kiểm tra được PaddlePaddle: {error}")

    paddleocr_version = _package_version("paddleocr")
    if paddleocr_version != "3.7.0":
        warnings.append(
            f"Pipeline được kiểm tra với paddleocr 3.7.0, hiện là "
            f"{paddleocr_version or 'chưa cài'}."
        )
    paddle_gpu_version = _package_version("paddlepaddle-gpu")
    paddle_cpu_version = _package_version("paddlepaddle")
    if paddle_gpu_version != args.expected_paddle_version:
        errors.append(
            "Cần paddlepaddle-gpu=="
            f"{args.expected_paddle_version}, hiện là "
            f"{paddle_gpu_version or 'chưa cài'}."
        )
    if paddle_cpu_version is not None:
        errors.append(
            "Đang cài đồng thời paddlepaddle CPU và paddlepaddle-gpu; hãy gỡ "
            f"paddlepaddle=={paddle_cpu_version}."
        )

    report["errors"] = errors
    report["warnings"] = warnings
    report["ok"] = not errors
    output = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True)
    print(output)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output + "\n", encoding="utf-8")
    if errors:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
