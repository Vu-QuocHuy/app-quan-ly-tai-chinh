"""Hợp đồng cột CSV giữa AiLabBatchRunner (Dart) và summarize_chat.py.

Danh sách cột cố định ở đây phải khớp `aiLabBatchCsvColumns` trong
lib/features/ai_lab/application/ai_lab_batch_runner.dart.
"""

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from summarize_chat import COLUMNS  # noqa: E402

EXPECTED = (
    "question_id", "group", "flag_profile", "run", "route", "llm_calls",
    "cloud_calls", "duration_ms", "contains_expected", "misrouted_write",
)
DART_FILE = (
    Path(__file__).resolve().parents[2]
    / "lib/features/ai_lab/application/ai_lab_batch_runner.dart"
)


class BatchCsvContractTest(unittest.TestCase):
    def test_summarize_columns_are_the_contract(self):
        self.assertEqual(tuple(COLUMNS), EXPECTED)

    def test_dart_runner_exports_the_same_columns(self):
        if not DART_FILE.exists():
            self.skipTest("không có file Dart của runner")
        source = DART_FILE.read_text(encoding="utf-8")
        block = re.search(
            r"const aiLabBatchCsvColumns = \[(.*?)\];", source, re.DOTALL
        )
        self.assertIsNotNone(block, "không thấy aiLabBatchCsvColumns")
        columns = tuple(re.findall(r"'([a-z_]+)'", block.group(1)))
        self.assertEqual(columns, EXPECTED)


if __name__ == "__main__":
    unittest.main()
