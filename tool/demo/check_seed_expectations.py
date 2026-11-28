"""Kiểm tra seed_expectations.json phủ mọi expected_keys của bộ 40 câu.

Chạy: python tool/demo/check_seed_expectations.py [questions.json] [expectations.json]
Thoát với mã 1 nếu thiếu khóa hoặc giá trị rỗng/sai kiểu. Khóa thừa chỉ là cảnh báo.
"""

import json
import sys
from pathlib import Path

MANUAL = "MANUAL"
HERE = Path(__file__).resolve().parent
DEFAULT_QUESTIONS = HERE.parent / "benchmark" / "chat_questions_40.json"
DEFAULT_EXPECTATIONS = HERE / "seed_expectations.json"


def used_keys(questions_data: dict) -> set[str]:
    """Mọi khóa xuất hiện trong expected_keys của bộ câu hỏi."""
    keys: set[str] = set()
    for question in questions_data.get("questions", []):
        keys.update(question.get("expected_keys", []))
    return keys


def check(questions_data: dict, expectations: dict) -> tuple[list[str], list[str]]:
    """Trả về (lỗi, cảnh báo). Có lỗi nghĩa là file kỳ vọng chưa dùng được."""
    errors: list[str] = []
    warnings: list[str] = []
    needed = used_keys(questions_data)

    for key in sorted(needed - set(expectations)):
        errors.append(f"thiếu khóa {key!r} trong seed_expectations.json")
    for key, value in expectations.items():
        if not isinstance(value, str) or not value.strip():
            errors.append(f"{key}: giá trị phải là chuỗi không rỗng, hiện là {value!r}")
    for key in sorted(set(expectations) - needed):
        warnings.append(f"khóa {key!r} không câu nào dùng")
    return errors, warnings


def manual_keys(expectations: dict) -> list[str]:
    return sorted(key for key, value in expectations.items() if value == MANUAL)


def main(argv: list[str]) -> int:
    if hasattr(sys.stdout, "reconfigure"):  # console Windows mặc định cp1252
        sys.stdout.reconfigure(encoding="utf-8")
    questions_path = Path(argv[1]) if len(argv) > 1 else DEFAULT_QUESTIONS
    expectations_path = Path(argv[2]) if len(argv) > 2 else DEFAULT_EXPECTATIONS
    questions = json.loads(questions_path.read_text(encoding="utf-8"))
    expectations = json.loads(expectations_path.read_text(encoding="utf-8"))
    errors, warnings = check(questions, expectations)
    for message in warnings:
        print(f"cảnh báo: {message}")
    for message in errors:
        print(f"lỗi: {message}")
    if errors:
        return 1
    manual = manual_keys(expectations)
    print(
        f"OK: {len(used_keys(questions))} khóa được phủ; "
        f"{len(manual)} khóa MANUAL: {', '.join(manual) or '-'}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
