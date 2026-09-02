from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Iterable, Sequence
import unicodedata


@dataclass(frozen=True, slots=True)
class OcrPair:
    sample_id: str
    reference: str
    prediction: str
    confidence: float | None = None


@dataclass(frozen=True, slots=True)
class OcrMetrics:
    sample_count: int
    exact_match: float
    character_error_rate: float
    word_error_rate: float
    mean_confidence: float | None
    character_edits: int
    reference_characters: int
    word_edits: int
    reference_words: int

    def to_dict(self) -> dict[str, int | float | None]:
        return asdict(self)


def normalize_metric_text(value: str) -> str:
    return " ".join(unicodedata.normalize("NFC", value).split())


def levenshtein_distance(reference: Sequence[str], hypothesis: Sequence[str]) -> int:
    if len(reference) < len(hypothesis):
        reference, hypothesis = hypothesis, reference
    previous = list(range(len(hypothesis) + 1))
    for reference_index, reference_item in enumerate(reference, start=1):
        current = [reference_index]
        for hypothesis_index, hypothesis_item in enumerate(hypothesis, start=1):
            substitution_cost = 0 if reference_item == hypothesis_item else 1
            current.append(
                min(
                    current[-1] + 1,
                    previous[hypothesis_index] + 1,
                    previous[hypothesis_index - 1] + substitution_cost,
                )
            )
        previous = current
    return previous[-1]


def calculate_ocr_metrics(pairs: Iterable[OcrPair]) -> OcrMetrics:
    values = list(pairs)
    if not values:
        raise ValueError("Cần ít nhất một cặp ground-truth/prediction.")

    exact = 0
    character_edits = 0
    reference_characters = 0
    word_edits = 0
    reference_words = 0
    confidences: list[float] = []

    for pair in values:
        reference = normalize_metric_text(pair.reference)
        prediction = normalize_metric_text(pair.prediction)
        if reference == prediction:
            exact += 1
        character_edits += levenshtein_distance(reference, prediction)
        reference_characters += len(reference)
        reference_tokens = reference.split()
        prediction_tokens = prediction.split()
        word_edits += levenshtein_distance(reference_tokens, prediction_tokens)
        reference_words += len(reference_tokens)
        if pair.confidence is not None:
            if not 0 <= pair.confidence <= 1:
                raise ValueError(
                    f"Confidence của {pair.sample_id!r} phải nằm trong [0, 1]."
                )
            confidences.append(pair.confidence)

    return OcrMetrics(
        sample_count=len(values),
        exact_match=exact / len(values),
        character_error_rate=character_edits / max(reference_characters, 1),
        word_error_rate=word_edits / max(reference_words, 1),
        mean_confidence=(sum(confidences) / len(confidences))
        if confidences
        else None,
        character_edits=character_edits,
        reference_characters=reference_characters,
        word_edits=word_edits,
        reference_words=reference_words,
    )

