from __future__ import annotations

from typing import Iterable


# Space is handled by PaddleOCR's Global.use_space_char option and is therefore
# intentionally absent from the one-character-per-line dictionary.
VIETNAMESE_RECEIPT_BASE_CHARACTERS = frozenset(
    "0123456789"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    "ÀÁẢÃẠĂẰẮẲẴẶÂẦẤẨẪẬĐÈÉẺẼẸÊỀẾỂỄỆÌÍỈĨỊ"
    "ÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢÙÚỦŨỤƯỪỨỬỮỰỲÝỶỸỴ"
    "àáảãạăằắẳẵặâầấẩẫậđèéẻẽẹêềếểễệìíỉĩị"
    "òóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵ"
    ".,:;!?%+-*/=()[]{}<>#@&_\"'\\|~`^₫$€£¥"
)


def training_charset(observed_characters: Iterable[str]) -> list[str]:
    characters = set(VIETNAMESE_RECEIPT_BASE_CHARACTERS)
    characters.update(
        character for character in observed_characters if not character.isspace()
    )
    return sorted(characters, key=ord)

