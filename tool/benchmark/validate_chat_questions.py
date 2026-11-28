"""Kiểm tra cấu trúc bộ 40 câu đo chat (chat_questions_40.json).

Chạy: python tool/benchmark/validate_chat_questions.py [đường_dẫn.json]
Thoát với mã 1 nếu có lỗi.
"""

import json
import sys
from collections import Counter
from pathlib import Path

# Khớp enum LocalChatIntent trong lib/features/chat/domain/chat_routing_rules.dart (nhánh TV2).
INTENTS = (
    "expenseTotal",
    "incomeTotal",
    "budget",
    "debt",
    "topCategory",
    "comparison",
    "forecast",
    "recurring",
    "anomaly",
    "recentInvoices",
    "scenario",
)
GROUPS = {"lookup": 12, "reasoning": 8, "write": 8, "ambiguous": 6, "reject": 6}
ROUTES = ("local", "cloud", "command")
MAX_TEXT = 160  # ChatRoutingRules.localIntent bỏ qua câu dài hơn 160 ký tự.
DEFAULT_PATH = Path(__file__).with_name("chat_questions_40.json")


def validate(data: dict) -> list[str]:
    errors: list[str] = []
    questions = data.get("questions", [])
    if len(questions) != 40:
        errors.append(f"cần đúng 40 câu, hiện có {len(questions)}")

    ids = Counter(q.get("id") for q in questions)
    for qid, count in ids.items():
        if count > 1:
            errors.append(f"trùng id {qid}")

    groups = Counter(q.get("group") for q in questions)
    if dict(groups) != GROUPS:
        errors.append(f"phân bố nhóm phải là {GROUPS}, hiện là {dict(groups)}")

    for q in questions:
        qid = q.get("id", "?")
        text = q.get("text", "")
        group = q.get("group")
        route = q.get("expected_route_b1")
        if not text.strip():
            errors.append(f"{qid}: text rỗng")
        if len(text) > MAX_TEXT:
            errors.append(f"{qid}: text dài hơn {MAX_TEXT} ký tự (router cục bộ sẽ bỏ qua)")
        if route not in ROUTES:
            errors.append(f"{qid}: expected_route_b1 phải thuộc {ROUTES}, hiện là {route!r}")

        if group == "write":
            if q.get("must_not_local") is not True:
                errors.append(f"{qid}: câu write phải có must_not_local=true")
            if route != "command":
                errors.append(f"{qid}: câu write phải có expected_route_b1=command")
        elif group == "lookup":
            if not q.get("expected_keys"):
                errors.append(f"{qid}: câu lookup phải có expected_keys không rỗng")
            if route != "local":
                errors.append(f"{qid}: câu lookup phải có expected_route_b1=local")
            if q.get("intent") not in INTENTS:
                errors.append(f"{qid}: intent không hợp lệ: {q.get('intent')!r}")
        elif group == "reject":
            if q.get("expected_behavior") != "refuse":
                errors.append(f"{qid}: câu reject phải có expected_behavior=refuse")
        elif not (q.get("expected_keys") or q.get("manual_review")):
            errors.append(f"{qid}: cần expected_keys hoặc manual_review để chấm câu trả lời")

    covered = {q["intent"] for q in questions if "intent" in q}
    for intent in INTENTS:
        if intent not in covered:
            errors.append(f"thiếu câu phủ ý định {intent}")
    return errors


def main(argv: list[str]) -> int:
    path = Path(argv[1]) if len(argv) > 1 else DEFAULT_PATH
    errors = validate(json.loads(path.read_text(encoding="utf-8")))
    for error in errors:
        print(f"LỖI: {error}")
    print("OK" if not errors else f"{len(errors)} lỗi")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
