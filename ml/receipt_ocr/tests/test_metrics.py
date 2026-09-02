from __future__ import annotations

import unittest

from receipt_ocr.metrics import OcrPair, calculate_ocr_metrics, levenshtein_distance


class MetricsTest(unittest.TestCase):
    def test_levenshtein_distance(self) -> None:
        self.assertEqual(levenshtein_distance("kitten", "sitting"), 3)
        self.assertEqual(levenshtein_distance([], []), 0)

    def test_perfect_predictions(self) -> None:
        metrics = calculate_ocr_metrics(
            [
                OcrPair("1", "TỔNG TIỀN 125.000 ₫", "TỔNG TIỀN 125.000 ₫", 0.9),
                OcrPair("2", "Ngày 31/08/2026", "Ngày 31/08/2026", 1.0),
            ]
        )
        self.assertEqual(metrics.exact_match, 1.0)
        self.assertEqual(metrics.character_error_rate, 0.0)
        self.assertEqual(metrics.word_error_rate, 0.0)
        self.assertAlmostEqual(metrics.mean_confidence or 0, 0.95)

    def test_error_rates_use_corpus_totals(self) -> None:
        metrics = calculate_ocr_metrics(
            [OcrPair("1", "TỔNG TIỀN", "TỔNG TIÊN")]
        )
        self.assertEqual(metrics.character_edits, 1)
        self.assertEqual(metrics.reference_characters, len("TỔNG TIỀN"))
        self.assertGreater(metrics.character_error_rate, 0)
        self.assertEqual(metrics.word_edits, 1)

    def test_invalid_confidence_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "Confidence"):
            calculate_ocr_metrics([OcrPair("1", "A", "A", 1.1)])


if __name__ == "__main__":
    unittest.main()

