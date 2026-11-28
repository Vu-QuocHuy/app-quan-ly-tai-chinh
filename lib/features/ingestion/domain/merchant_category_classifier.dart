/// On-device port of the server `classify` action (`merchant-rules-v1`, see
/// `classifyMerchant` in `supabase/functions/ai-api/index.ts`). Running it
/// locally (H8) removes one network round trip and one quota unit per
/// unclassified import while producing the same category ids.
class MerchantCategoryClassifier {
  const MerchantCategoryClassifier();

  static const version = 'merchant-rules-v1';

  // Same order and keywords as the server so results stay identical.
  static const _rules = <(String, List<String>)>[
    (
      'food',
      ['restaurant', 'cafe', 'coffee', 'food', 'mart', 'quan an', 'nha hang'],
    ),
    ('transport', ['grab', 'taxi', 'transport', 'xang', 'petrol', 'parking']),
    (
      'utilities',
      ['electric', 'water', 'internet', 'telecom', 'dien luc', 'cap nuoc'],
    ),
    ('health', ['hospital', 'clinic', 'pharmacy', 'benh vien', 'nha thuoc']),
    ('education', ['school', 'academy', 'education', 'truong', 'giao duc']),
    ('entertainment', ['cinema', 'movie', 'game', 'theater', 'rap phim']),
    ('shopping', ['shop', 'store', 'mall', 'retail', 'shopping']),
  ];

  /// The matching category id, or `null` when no rule matches (the server
  /// answers `other` with confidence 0.35 in that case).
  String? classify(String merchant) {
    final text = normalize(merchant);
    if (text.isEmpty) return null;
    for (final (categoryId, keywords) in _rules) {
      if (keywords.any(text.contains)) return categoryId;
    }
    return null;
  }

  /// Mirrors the server `normalize` (strip diacritics, lower-case, collapse
  /// non-alphanumerics to single spaces) and additionally folds `đ` → `d`:
  /// on the server NFD leaves `đ` intact, so "Điện lực" never matched
  /// "dien luc" there.
  static String normalize(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_fold[char] ?? char);
    }
    return buffer
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  static final Map<String, String> _fold = () {
    const groups = {
      'a': 'àáạảãâầấậẩẫăằắặẳẵ',
      'A': 'ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴ',
      'e': 'èéẹẻẽêềếệểễ',
      'E': 'ÈÉẸẺẼÊỀẾỆỂỄ',
      'i': 'ìíịỉĩ',
      'I': 'ÌÍỊỈĨ',
      'o': 'òóọỏõôồốộổỗơờớợởỡ',
      'O': 'ÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠ',
      'u': 'ùúụủũưừứựửữ',
      'U': 'ÙÚỤỦŨƯỪỨỰỬỮ',
      'y': 'ỳýỵỷỹ',
      'Y': 'ỲÝỴỶỸ',
      'd': 'đ',
      'D': 'Đ',
    };
    return {
      for (final entry in groups.entries)
        for (final char in entry.value.split('')) char: entry.key,
    };
  }();
}
