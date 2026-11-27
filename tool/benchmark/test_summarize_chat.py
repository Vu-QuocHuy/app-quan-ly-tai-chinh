import csv
import io
import unittest
from pathlib import Path

from summarize_chat import COLUMNS, percentile, read_rows, summarize, to_markdown

FIXTURE = Path(__file__).with_name("fixtures") / "chat_sample.csv"


def row(profile="b0", group="lookup", route="cloud", llm=3, cloud=3, ms=1000,
        contains="true", misrouted="false", qid="Q01", run="1"):
    return {
        "question_id": qid, "group": group, "flag_profile": profile, "run": run,
        "route": route, "llm_calls": llm, "cloud_calls": cloud,
        "duration_ms": ms, "contains_expected": contains,
        "misrouted_write": misrouted,
    }


def to_csv_text(rows, columns=COLUMNS):
    out = io.StringIO()
    writer = csv.DictWriter(out, fieldnames=columns, extrasaction="ignore")
    writer.writeheader()
    writer.writerows(rows)
    return out.getvalue()


class PercentileTest(unittest.TestCase):
    def test_p50_of_odd_list_is_middle(self):
        self.assertEqual(percentile([3, 1, 2], 50), 2)

    def test_p95_of_20_samples_interpolates(self):
        self.assertAlmostEqual(percentile(list(range(1, 21)), 95), 19.05)

    def test_single_value(self):
        self.assertEqual(percentile([7], 95), 7)

    def test_empty_returns_none(self):
        self.assertIsNone(percentile([], 50))


class SummarizeTest(unittest.TestCase):
    def test_m6_is_mean_llm_calls_per_turn(self):
        s = summarize([row(llm=3), row(llm=3), row(llm=0, route="local", cloud=0)])
        self.assertAlmostEqual(s["b0"]["m6_avg_llm_calls"], 2.0)

    def test_m7_is_share_of_local_turns(self):
        rows = [row(profile="b1", route="local", llm=0, cloud=0),
                row(profile="b1", route="local", llm=0, cloud=0),
                row(profile="b1", route="cloud", llm=1, cloud=1),
                row(profile="b1", route="cloud", llm=1, cloud=1)]
        self.assertAlmostEqual(summarize(rows)["b1"]["m7_local_rate"], 0.5)

    def test_m9_percentiles_use_all_turns(self):
        rows = [row(ms=v) for v in range(1, 21)]
        s = summarize(rows)["b0"]
        self.assertAlmostEqual(s["m9_p50_ms"], 10.5)
        self.assertAlmostEqual(s["m9_p95_ms"], 19.05)

    def test_counts_misrouted_writes(self):
        rows = [row(group="write", route="local", misrouted="true"),
                row(group="write", route="cloud", misrouted="false")]
        self.assertEqual(summarize(rows)["b0"]["misrouted_writes"], 1)

    def test_accuracy_ignores_rows_without_automatic_check(self):
        rows = [row(contains="true"), row(contains="false"), row(contains="")]
        self.assertAlmostEqual(summarize(rows)["b0"]["contains_expected_rate"], 0.5)

    def test_accuracy_is_none_when_nothing_checked(self):
        self.assertIsNone(summarize([row(contains="")])["b0"]["contains_expected_rate"])

    def test_lookup_group_avg_llm_calls_reported_separately(self):
        rows = [row(group="lookup", llm=0, route="local", cloud=0),
                row(group="write", llm=2, cloud=2)]
        s = summarize(rows)["b0"]
        self.assertAlmostEqual(s["lookup_avg_llm_calls"], 0.0)
        self.assertAlmostEqual(s["m6_avg_llm_calls"], 1.0)

    def test_profiles_are_kept_apart_and_ordered_by_first_appearance(self):
        s = summarize([row(profile="b1"), row(profile="b0")])
        self.assertEqual(list(s), ["b1", "b0"])

    def test_turn_count_includes_repeated_runs(self):
        rows = [row(run="1"), row(run="2"), row(run="3")]
        self.assertEqual(summarize(rows)["b0"]["turns"], 3)


class ReadRowsTest(unittest.TestCase):
    def test_missing_column_raises_with_its_name(self):
        text = to_csv_text([row()], columns=[c for c in COLUMNS if c != "route"])
        with self.assertRaises(ValueError) as ctx:
            read_rows(io.StringIO(text))
        self.assertIn("route", str(ctx.exception))

    def test_non_numeric_duration_raises_with_line_number(self):
        text = to_csv_text([row(ms="abc")])
        with self.assertRaises(ValueError) as ctx:
            read_rows(io.StringIO(text))
        self.assertIn("dòng 2", str(ctx.exception))

    def test_empty_file_raises(self):
        with self.assertRaises(ValueError):
            read_rows(io.StringIO(""))


class MarkdownTest(unittest.TestCase):
    def test_table_has_one_line_per_profile(self):
        md = to_markdown(summarize([row(profile="b0"), row(profile="b1", llm=0, route="local", cloud=0)]))
        lines = [l for l in md.splitlines() if l.startswith("| b")]
        self.assertEqual(len(lines), 2)
        self.assertIn("| b0 |", md)

    def test_uses_vietnamese_decimal_comma(self):
        md = to_markdown(summarize([row(llm=2), row(llm=3)]))
        self.assertIn("2,50", md)


class FixtureTest(unittest.TestCase):
    def test_fixture_summary(self):
        with FIXTURE.open(encoding="utf-8", newline="") as handle:
            s = summarize(read_rows(handle))
        self.assertEqual(s["b0"]["turns"], 4)
        self.assertAlmostEqual(s["b0"]["m6_avg_llm_calls"], 2.75)
        self.assertAlmostEqual(s["b1"]["m6_avg_llm_calls"], 0.5)
        self.assertAlmostEqual(s["b1"]["m7_local_rate"], 0.5)
        self.assertEqual(s["b1"]["misrouted_writes"], 0)


if __name__ == "__main__":
    unittest.main()
