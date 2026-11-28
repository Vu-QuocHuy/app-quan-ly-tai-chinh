"""Keeps tool/demo/controller/index.html and the Dart parser in step.

Run: python tool/demo/controller/test_controller_contract.py
"""
import re
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
HTML = (HERE / "index.html").read_text(encoding="utf-8")
DART = (
    HERE.parents[2] / "lib" / "features" / "ai_lab" / "data" / "ai_lab_bridge.dart"
).read_text(encoding="utf-8")

PROTOCOL_COMMANDS = {"ask", "fault", "importAsset", "tamper", "reset"}


class ControllerContract(unittest.TestCase):
    def test_posted_commands_are_exactly_the_protocol(self):
        posted = set(re.findall(r"\bsend\(\s*'([A-Za-z]+)'", HTML))
        self.assertEqual(posted, PROTOCOL_COMMANDS)

    def test_dart_parser_handles_the_same_commands(self):
        handled = set(re.findall(r"case '([A-Za-z]+)':", DART))
        self.assertEqual(handled, PROTOCOL_COMMANDS)

    def test_message_envelope_uses_protocol_version_1(self):
        self.assertRegex(HTML, r"\{\s*ailab:\s*1\s*,\s*cmd:")

    def test_iframe_urls_use_ports_8080_and_8081(self):
        srcs = re.findall(r"<iframe[^>]*\ssrc=\"([^\"]+)\"", HTML)
        self.assertEqual(srcs, ["http://localhost:8080/", "http://localhost:8081/"])
        origins = re.findall(r"origin:\s*'([^']+)'", HTML)
        self.assertEqual(origins, ["http://localhost:8080", "http://localhost:8081"])

    def test_iframe_titles(self):
        self.assertIn('title="B0 – GỐC"', HTML)
        self.assertIn('title="B1 – TỐI ƯU"', HTML)

    def test_controller_origin_is_allowed_by_dart(self):
        self.assertIn("http://localhost:8090", DART)

    def test_preset_questions_and_assets(self):
        for q in (
            "Tháng này tôi chi bao nhiêu?",
            "Tại sao tháng này tôi chi nhiều?",
            "Hôm nay ăn trưa hết 35k",
        ):
            self.assertIn(f'data-question="{q}"', HTML)
        for a in ("receipt_normal.png", "receipt_repeat.png"):
            self.assertIn(f'data-asset="assets/ai_lab/{a}"', HTML)

    def test_asset_values_pass_the_dart_prefix_rule(self):
        for a in re.findall(r'data-asset="([^"]+)"', HTML):
            self.assertTrue(a.startswith("assets/ai_lab/"))
            self.assertNotIn("..", a)

    def test_fault_values_are_allowed_by_dart(self):
        values = set(re.findall(r'name="fault" value="([^"]*)"', HTML))
        self.assertEqual(values, {"", "429", "500", "timeout"})
        self.assertIn("{'429', '500', 'timeout'}", DART)

    def test_questions_fit_the_dart_length_limit(self):
        for q in re.findall(r'data-question="([^"]+)"', HTML):
            self.assertLessEqual(len(q), 500)


if __name__ == "__main__":
    unittest.main()
