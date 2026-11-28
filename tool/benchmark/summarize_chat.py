"""Tổng hợp CSV đo chat (T3.2/T3.3) thành bảng M6, M7, M9 theo từng profile cờ.

Chạy: python tool/benchmark/summarize_chat.py chat_b0.csv chat_b1.csv ...
In bảng Markdown (dấu phẩy thập phân kiểu Việt) ra stdout.

Cột CSV (cố định, do AiLabBatchRunner xuất):
question_id,group,flag_profile,run,route,llm_calls,cloud_calls,duration_ms,
contains_expected,misrouted_write
"""

import csv
import sys
from pathlib import Path
from typing import Iterable, TextIO

COLUMNS = (
    "question_id", "group", "flag_profile", "run", "route", "llm_calls",
    "cloud_calls", "duration_ms", "contains_expected", "misrouted_write",
)
_INT_COLUMNS = ("llm_calls", "cloud_calls", "duration_ms")


def percentile(values: Iterable[float], p: float):
    """Nội suy tuyến tính giữa hai mẫu gần nhất (trùng numpy mặc định)."""
    ordered = sorted(values)
    if not ordered:
        return None
    index = (len(ordered) - 1) * p / 100
    low = int(index)
    high = min(low + 1, len(ordered) - 1)
    return ordered[low] + (ordered[high] - ordered[low]) * (index - low)


def read_rows(handle: TextIO) -> list[dict]:
    reader = csv.DictReader(handle)
    if reader.fieldnames is None:
        raise ValueError("file CSV rỗng")
    missing = [c for c in COLUMNS if c not in reader.fieldnames]
    if missing:
        raise ValueError(f"thiếu cột: {', '.join(missing)}")
    rows = []
    for number, row in enumerate(reader, start=2):
        for column in _INT_COLUMNS:
            try:
                row[column] = int(row[column])
            except (TypeError, ValueError):
                raise ValueError(
                    f"dòng {number}: cột {column} không phải số nguyên: {row[column]!r}"
                ) from None
        rows.append(row)
    return rows


def _mean(values: list[float]):
    return sum(values) / len(values) if values else None


def summarize(rows: list[dict]) -> dict[str, dict]:
    """Gom theo flag_profile (giữ thứ tự xuất hiện đầu tiên)."""
    grouped: dict[str, list[dict]] = {}
    for row in rows:
        grouped.setdefault(row["flag_profile"], []).append(row)

    result = {}
    for profile, items in grouped.items():
        checked = [r for r in items if r["contains_expected"] in ("true", "false")]
        lookups = [r["llm_calls"] for r in items if r["group"] == "lookup"]
        durations = [r["duration_ms"] for r in items]
        result[profile] = {
            "turns": len(items),
            "m6_avg_llm_calls": _mean([r["llm_calls"] for r in items]),
            "lookup_avg_llm_calls": _mean(lookups),
            "m7_local_rate": sum(r["route"] == "local" for r in items) / len(items),
            "m9_p50_ms": percentile(durations, 50),
            "m9_p95_ms": percentile(durations, 95),
            "misrouted_writes": sum(r["misrouted_write"] == "true" for r in items),
            "contains_expected_rate": (
                sum(r["contains_expected"] == "true" for r in checked) / len(checked)
                if checked else None
            ),
        }
    return result


def _fmt(value, digits=2, percent=False) -> str:
    if value is None:
        return "—"
    if percent:
        return f"{value * 100:.1f}%".replace(".", ",")
    return f"{value:.{digits}f}".replace(".", ",")


def to_markdown(summary: dict[str, dict]) -> str:
    lines = [
        "| Cấu hình | Số lượt | M6 lượt gọi LLM TB | Tra cứu: lượt gọi TB | M7 tỉ lệ cục bộ "
        "| M9 p50 (ms) | M9 p95 (ms) | Lệnh ghi bị định tuyến nhầm | Trả lời đúng |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for profile, s in summary.items():
        lines.append(
            f"| {profile} | {s['turns']} | {_fmt(s['m6_avg_llm_calls'])} "
            f"| {_fmt(s['lookup_avg_llm_calls'])} | {_fmt(s['m7_local_rate'], percent=True)} "
            f"| {_fmt(s['m9_p50_ms'], 0)} | {_fmt(s['m9_p95_ms'], 0)} "
            f"| {s['misrouted_writes']} | {_fmt(s['contains_expected_rate'], percent=True)} |"
        )
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    sys.stdout.reconfigure(encoding="utf-8")  # Windows mặc định cp1252 không in được tiếng Việt
    if len(argv) < 2:
        print(__doc__)
        return 2
    rows: list[dict] = []
    for name in argv[1:]:
        with Path(name).open(encoding="utf-8", newline="") as handle:
            rows.extend(read_rows(handle))
    print(to_markdown(summarize(rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
