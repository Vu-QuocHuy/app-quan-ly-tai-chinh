import json
import tempfile
import unittest
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
from matplotlib.text import Text  # noqa: E402

import make_charts  # noqa: E402
from summarize_chat import read_rows, summarize  # noqa: E402

FIXTURE = Path(__file__).with_name("fixtures") / "chat_sample.csv"


def figure_text(fig) -> str:
    return "\n".join(t.get_text() for t in fig.findobj(Text) if t.get_text())


class ChartTestBase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)

    def assertPng(self, path: Path):
        self.assertTrue(path.exists(), f"{path} không tồn tại")
        self.assertGreater(path.stat().st_size, 1000)
        self.assertEqual(path.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")


class TokenStackTest(ChartTestBase):
    def test_writes_png_with_vietnamese_labels(self):
        out = self.dir / "token.png"
        fig = make_charts.plot_token_stack(out)
        self.assertPng(out)
        text = figure_text(fig)
        for label in ("đầu vào", "suy luận", "đầu ra", "30 ảnh hóa đơn", "báo cáo TV1"):
            self.assertIn(label, text)
        self.assertIn("−30,8%", text)

    def test_stack_values_match_tv1_totals(self):
        self.assertEqual(sum(make_charts.TOKENS_B0.values()), 3305)
        self.assertEqual(sum(make_charts.TOKENS_B1.values()), 2286)
        self.assertEqual(make_charts.TOKENS_B0["input"], 2094)
        self.assertEqual(make_charts.TOKENS_B1["input"], 2095)


class LatencyBoxTest(ChartTestBase):
    def test_writes_png_and_draws_timeout_line(self):
        out = self.dir / "lat.png"
        fig = make_charts.plot_latency_box(
            [9000, 11000, 14000, 27000, 29500], [4000, 6000, 7000, 9000, 14000], out
        )
        self.assertPng(out)
        ys = [set(line.get_ydata()) for line in fig.axes[0].lines]
        self.assertIn({30000}, ys)
        text = figure_text(fig)
        self.assertIn("30 s", text)
        self.assertIn("B0", text)
        self.assertIn("B1", text)

    def test_custom_timeout(self):
        fig = make_charts.plot_latency_box([1, 2, 3], [1, 2, 3], self.dir / "a.png",
                                           timeout_ms=5000)
        self.assertIn({5000}, [set(l.get_ydata()) for l in fig.axes[0].lines])

    def test_empty_input_raises(self):
        with self.assertRaises(ValueError):
            make_charts.plot_latency_box([], [1, 2], self.dir / "x.png")
        with self.assertRaises(ValueError):
            make_charts.plot_latency_box([1, 2], [], self.dir / "x.png")

    def test_cli_reads_json_files(self):
        b0, b1 = self.dir / "b0.json", self.dir / "b1.json"
        b0.write_text(json.dumps([9000, 12000, 28000]))
        b1.write_text(json.dumps([4000, 6000, 9000]))
        out = self.dir / "cli.png"
        code = make_charts.main(["--latency-b0", str(b0), "--latency-b1", str(b1),
                                 "--out", str(out)])
        self.assertEqual(code, 0)
        self.assertPng(out)


class ChatCallsTest(ChartTestBase):
    def test_writes_png_from_fixture_summary(self):
        with FIXTURE.open(encoding="utf-8", newline="") as handle:
            summary = summarize(read_rows(handle))
        out = self.dir / "calls.png"
        fig = make_charts.plot_chat_calls(summary, out)
        self.assertPng(out)
        text = figure_text(fig)
        self.assertIn("lượt gọi", text)
        for profile in summary:
            self.assertIn(profile, text)

    def test_empty_summary_raises(self):
        with self.assertRaises(ValueError):
            make_charts.plot_chat_calls({}, self.dir / "x.png")


class ChatFlowTest(ChartTestBase):
    def test_writes_png_with_design_caption(self):
        out = self.dir / "flow.png"
        fig = make_charts.plot_chat_flow(out)
        self.assertPng(out)
        text = figure_text(fig)
        self.assertIn("theo thiết kế, chưa phải số đo", text)
        self.assertIn("3 lượt", text)
        self.assertIn("0 lượt", text)
        self.assertIn("1 lượt", text)


if __name__ == "__main__":
    unittest.main()
