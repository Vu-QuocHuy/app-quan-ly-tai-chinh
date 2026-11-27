import copy
import json
import unittest
from pathlib import Path

from validate_chat_questions import INTENTS, validate

DATA_PATH = Path(__file__).with_name("chat_questions_40.json")


def load():
    return json.loads(DATA_PATH.read_text(encoding="utf-8"))


class ChatQuestionsFileTest(unittest.TestCase):
    def test_real_file_is_valid(self):
        self.assertEqual(validate(load()), [])

    def test_has_40_unique_ids(self):
        questions = load()["questions"]
        self.assertEqual(len(questions), 40)
        self.assertEqual(len({q["id"] for q in questions}), 40)

    def test_distribution_is_12_8_8_6_6(self):
        counts = {}
        for q in load()["questions"]:
            counts[q["group"]] = counts.get(q["group"], 0) + 1
        self.assertEqual(
            counts,
            {"lookup": 12, "reasoning": 8, "write": 8, "ambiguous": 6, "reject": 6},
        )

    def test_every_write_question_must_not_go_local(self):
        for q in load()["questions"]:
            if q["group"] == "write":
                self.assertTrue(q["must_not_local"], q["id"])
                self.assertEqual(q["expected_route_b1"], "command", q["id"])

    def test_all_11_local_intents_are_covered(self):
        covered = {q["intent"] for q in load()["questions"] if "intent" in q}
        self.assertEqual(covered, set(INTENTS))
        self.assertEqual(len(INTENTS), 11)

    def test_every_lookup_has_expected_keys(self):
        for q in load()["questions"]:
            if q["group"] == "lookup":
                self.assertTrue(q["expected_keys"], q["id"])


class ChatQuestionsValidatorTest(unittest.TestCase):
    def mutate(self, fn):
        data = copy.deepcopy(load())
        fn(data)
        return validate(data)

    def test_detects_missing_question(self):
        errors = self.mutate(lambda d: d["questions"].pop())
        self.assertTrue(any("40" in e for e in errors), errors)

    def test_detects_duplicate_id(self):
        errors = self.mutate(lambda d: d["questions"][1].update(id="Q01"))
        self.assertTrue(any("trùng id" in e for e in errors), errors)

    def test_detects_write_routed_local(self):
        def fn(d):
            q = next(x for x in d["questions"] if x["group"] == "write")
            q["expected_route_b1"] = "local"

        errors = self.mutate(fn)
        self.assertTrue(any("write" in e and "command" in e for e in errors), errors)

    def test_detects_write_without_must_not_local(self):
        def fn(d):
            q = next(x for x in d["questions"] if x["group"] == "write")
            q["must_not_local"] = False

        errors = self.mutate(fn)
        self.assertTrue(any("must_not_local" in e for e in errors), errors)

    def test_detects_lookup_without_expected_keys(self):
        def fn(d):
            q = next(x for x in d["questions"] if x["group"] == "lookup")
            q["expected_keys"] = []

        errors = self.mutate(fn)
        self.assertTrue(any("expected_keys" in e for e in errors), errors)

    def test_detects_unknown_route(self):
        errors = self.mutate(lambda d: d["questions"][0].update(expected_route_b1="edge"))
        self.assertTrue(any("route" in e for e in errors), errors)

    def test_detects_missing_intent_coverage(self):
        def fn(d):
            for q in d["questions"]:
                if q.get("intent") == "scenario":
                    del q["intent"]

        errors = self.mutate(fn)
        self.assertTrue(any("scenario" in e for e in errors), errors)

    def test_detects_reject_without_refuse_behavior(self):
        def fn(d):
            q = next(x for x in d["questions"] if x["group"] == "reject")
            del q["expected_behavior"]

        errors = self.mutate(fn)
        self.assertTrue(any("refuse" in e for e in errors), errors)

    def test_detects_question_with_no_way_to_check_answer(self):
        def fn(d):
            q = next(x for x in d["questions"] if x["id"] == "Q13")
            del q["manual_review"]

        errors = self.mutate(fn)
        self.assertTrue(any("Q13" in e for e in errors), errors)

    def test_detects_text_longer_than_router_limit(self):
        errors = self.mutate(lambda d: d["questions"][0].update(text="a" * 161))
        self.assertTrue(any("160" in e for e in errors), errors)


if __name__ == "__main__":
    unittest.main()
