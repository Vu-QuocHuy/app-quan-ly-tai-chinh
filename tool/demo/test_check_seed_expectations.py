import json
import re
import unittest
from collections import defaultdict
from datetime import datetime
from pathlib import Path

from check_seed_expectations import (
    DEFAULT_EXPECTATIONS,
    DEFAULT_QUESTIONS,
    MANUAL,
    check,
    manual_keys,
    used_keys,
)

SQL_PATH = Path(__file__).with_name("seed_demo_account.sql")
README_PATH = Path(__file__).with_name("README.md")


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def questions(*key_lists):
    return {"questions": [{"id": f"Q{i}", "expected_keys": keys} for i, keys in enumerate(key_lists)]}


class CheckerTest(unittest.TestCase):
    def test_real_files_are_consistent(self):
        errors, _ = check(load(DEFAULT_QUESTIONS), load(DEFAULT_EXPECTATIONS))
        self.assertEqual(errors, [])

    def test_missing_key_fails(self):
        errors, _ = check(questions(["a", "b"]), {"a": "1"})
        self.assertEqual(len(errors), 1)
        self.assertIn("'b'", errors[0])

    def test_empty_or_non_string_value_fails(self):
        errors, _ = check(questions(["a", "b", "c"]), {"a": "", "b": 5, "c": "  "})
        self.assertEqual(len(errors), 3)

    def test_unused_key_is_only_a_warning(self):
        errors, warnings = check(questions(["a"]), {"a": "1", "extra": "2"})
        self.assertEqual(errors, [])
        self.assertEqual(len(warnings), 1)

    def test_questions_without_expected_keys_are_ignored(self):
        data = {"questions": [{"id": "Q1"}, {"id": "Q2", "expected_keys": ["a"]}]}
        self.assertEqual(used_keys(data), {"a"})

    def test_manual_keys_are_the_documented_ones(self):
        self.assertEqual(
            manual_keys(load(DEFAULT_EXPECTATIONS)),
            ["forecast_month_end", "group_fund_travel_balance", "scenario_saving_500k"],
        )


def block(text, name):
    match = re.search(rf"-- SEED-{name}-BEGIN(.*?)-- SEED-{name}-END", text, re.S)
    assert match, f"thiếu khối SEED-{name} trong seed_demo_account.sql"
    return match.group(1)


def vnd(value):
    return f"{value:,}".replace(",", ".")


# Tháng chạy tham chiếu mà seed_expectations.json được tính cho (2026-11).
MONTH_OF = {"c": (2026, 11), "p": (2026, 10), "q": (2026, 9)}


class SeedConsistencyTest(unittest.TestCase):
    """Tính lại từng giá trị kỳ vọng từ chính các dòng VALUES trong file SQL."""

    @classmethod
    def setUpClass(cls):
        text = SQL_PATH.read_text(encoding="utf-8")
        cls.expectations = load(DEFAULT_EXPECTATIONS)
        cls.invoices = []
        for m in re.finditer(
            r"\('([cpq])',\s*(\d+),\s*(\d+),\s*'([^']+)',\s*'([a-z]+)',\s*(\d+)\)",
            block(text, "INVOICES"),
        ):
            role, seq, day, merchant, category, amount = m.groups()
            cls.invoices.append(
                {
                    "role": role,
                    "seq": int(seq),
                    "day": int(day),
                    "merchant": merchant,
                    "category": category,
                    "amount": int(amount),
                    "date": datetime(*MONTH_OF[role], int(day), 12),
                }
            )
        cls.income = [
            {"role": m.group(1), "amount": int(m.group(4))}
            for m in re.finditer(
                r"\('([cpq])',\s*(\d+),\s*(\d+),\s*(\d+),\s*'\w+',\s*'\w+',\s*'[^']+'\)",
                block(text, "INCOME"),
            )
        ]
        cls.budgets = {
            m.group(1): int(m.group(2))
            for m in re.finditer(r"\('(\w+)',\s*(\d+)\)", block(text, "BUDGET"))
        }
        cls.funds = [
            (m.group(1), int(m.group(2)))
            for m in re.finditer(r"'(deposit|expense)',\s*(\d+),\s*'", text)
        ]

    def total(self, role):
        return sum(i["amount"] for i in self.invoices if i["role"] == role)

    def test_rows_were_parsed(self):
        self.assertEqual(
            {role: sum(1 for i in self.invoices if i["role"] == role) for role in "cpq"},
            {"c": 18, "p": 14, "q": 14},
        )
        self.assertEqual(len(self.income), 5)
        self.assertEqual(len(self.budgets), 5)

    def test_ids_are_unique_per_role_and_days_are_safe(self):
        ids = [(i["role"], i["seq"]) for i in self.invoices]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertTrue(all(1 <= i["day"] <= 28 for i in self.invoices))
        self.assertTrue(all(i["category"] in {
            "food", "transport", "shopping", "utilities", "health",
            "education", "entertainment", "other",
        } for i in self.invoices))

    def test_monthly_totals(self):
        self.assertEqual(vnd(self.total("c")), self.expectations["expense_total_current"])
        self.assertEqual(vnd(self.total("p")), self.expectations["expense_total_previous"])
        # 2026-10 reuses the previous-month rows (role f) when it is not c/p/q.
        self.assertEqual(vnd(self.total("p")), self.expectations["expense_total_2026_10"])

    def test_q06_trick_month_before_previous_equals_current(self):
        # Q06 ("tháng này với tháng trước") makes the local assistant answer for
        # the PREVIOUS month, printing previous and previous-of-previous totals.
        self.assertEqual(self.total("q"), self.total("c"))
        self.assertNotEqual(self.total("p"), self.total("c"))

    def test_income_total(self):
        total = sum(e["amount"] for e in self.income if e["role"] == "c")
        self.assertEqual(vnd(total), self.expectations["income_total_current"])

    def test_budget_limit_and_progress_band(self):
        limit = sum(self.budgets.values())
        self.assertEqual(vnd(limit), self.expectations["budget_remaining_current"])
        progress = self.total("c") / limit
        self.assertTrue(0.8 <= progress < 1.0)  # "chạm mức x% ngân sách" branch

    def test_top_category_is_food(self):
        totals = defaultdict(int)
        for i in self.invoices:
            if i["role"] == "c":
                totals[i["category"]] += i["amount"]
        ranked = sorted(totals.items(), key=lambda kv: -kv[1])
        self.assertEqual(ranked[0][0], "food")
        self.assertEqual(vnd(ranked[0][1]), self.expectations["top_category_current"])
        self.assertGreater(ranked[0][1], ranked[1][1])

    def test_recent_invoice_is_last_inserted_current_month_row(self):
        # Insert order: q, f, p, c; inside a role by (day, seq). Last row wins.
        order = {"q": 1, "p": 3, "c": 4}
        last = max(self.invoices, key=lambda i: (order[i["role"]], i["day"], i["seq"]))
        self.assertEqual(last["role"], "c")
        self.assertEqual(last["merchant"], self.expectations["recent_invoices_first"])

    def recurring(self):
        """Port of SpendingInsightEngine._recurring over the seed rows."""
        grouped = defaultdict(list)
        for i in self.invoices:
            grouped[i["merchant"].strip().lower()].append(i)
        result = []
        for items in grouped.values():
            items = sorted(items, key=lambda i: i["date"])
            if len(items) < 3:
                continue
            intervals = [
                abs((items[k]["date"] - items[k - 1]["date"]).days)
                for k in range(1, len(items))
            ]
            avg_interval = sum(intervals) / len(intervals)
            avg_amount = sum(i["amount"] for i in items) / len(items)
            max_delta = max(abs(i["amount"] - avg_amount) for i in items)
            tolerance = avg_interval * 0.4 + 2
            stable_interval = all(abs(v - avg_interval) <= tolerance for v in intervals)
            stable_amount = avg_amount > 0 and max_delta / avg_amount <= 0.3
            if stable_interval and stable_amount:
                result.append((items[0]["merchant"], round(avg_amount), avg_interval))
        return sorted(result, key=lambda r: -r[1])

    def test_recurring_list(self):
        found = self.recurring()
        self.assertEqual([r[0] for r in found], ["Thuê nhà", "Netflix", "FPT Internet"])
        self.assertEqual(found[0][0], self.expectations["recurring_list"])
        self.assertTrue(all(20 <= r[2] <= 40 for r in found))  # "Hàng tháng"

    def test_single_anomaly(self):
        month_start = datetime(2026, 11, 1)
        history = defaultdict(list)
        current = []
        for i in self.invoices:
            if i["date"] < month_start:
                history[i["merchant"].strip().lower()].append(i)
            elif i["date"] < datetime(2026, 12, 1):
                current.append(i)
        anomalies = []
        for i in current:
            past = history.get(i["merchant"].strip().lower())
            if not past or len(past) < 3:
                continue
            avg = sum(p["amount"] for p in past) / len(past)
            if avg <= 0 or i["amount"] / avg < 1.8 or i["amount"] - avg < 100000:
                continue
            anomalies.append((i["merchant"], i["amount"], i["amount"] / avg))
        self.assertEqual(len(anomalies), 1)
        merchant, amount, ratio = anomalies[0]
        self.assertEqual(merchant, "Highlands Coffee")
        self.assertEqual(vnd(amount), self.expectations["anomaly_summary"])
        self.assertEqual(f"{ratio:.1f}", "9.0")

    def test_group_fund_balance_hand_value(self):
        balance = sum(a if kind == "deposit" else -a for kind, a in self.funds)
        self.assertEqual(vnd(balance), "3.750.000")  # documented in README (MANUAL key)

    def test_expected_values_do_not_hide_each_other(self):
        values = {
            k: v for k, v in self.expectations.items() if v != MANUAL
        }
        items = sorted(values.items())
        for a_key, a in items:
            for b_key, b in items:
                if a_key >= b_key or a == b:
                    continue
                self.assertNotIn(a, b, f"{a_key}={a!r} là chuỗi con của {b_key}={b!r}")
                self.assertNotIn(b, a, f"{b_key}={b!r} là chuỗi con của {a_key}={a!r}")
        equal = {(a, b) for a, av in items for b, bv in items if a < b and av == bv}
        self.assertEqual(equal, {("expense_total_2026_10", "expense_total_previous")})

    def test_debt_value_is_documented_in_readme(self):
        readme = README_PATH.read_text(encoding="utf-8")
        self.assertIn(self.expectations["debt_creditors"], readme)


if __name__ == "__main__":
    unittest.main()
