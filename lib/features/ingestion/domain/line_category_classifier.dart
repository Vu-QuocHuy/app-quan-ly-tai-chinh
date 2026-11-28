import '../../invoices/domain/invoice_models.dart';

class LineCategoryClassifier {
  const LineCategoryClassifier();

  List<InvoiceLineEntity> classify(
    List<InvoiceLineEntity> lines,
    List<CategoryEntity> categories,
  ) {
    final available = categories.map((item) => item.id).toSet();
    return lines
        .map(
          (line) => line.categoryId == null
              ? line.copyWith(
                  categoryId: _categoryFor(line.description, available),
                )
              : line,
        )
        .toList(growable: false);
  }

  // Single-syllable keywords (ca, mi, cu, qua, vo, but) matched inside
  // unrelated words ("cafe", "mì"→"mi" in "khuyến mi", "quà", "vớ"...), so
  // they were replaced by multi-syllable phrases. Matching is whole-word.
  static const _rules = <String, List<String>>{
    'food': [
      'thit',
      'rau',
      'gao',
      'sua',
      'banh',
      'do uong',
      'thuc pham',
      'gia vi',
      'ca hoi',
      'ca thu',
      'ca basa',
      'ca phe',
      'hai san',
      'hoa qua',
      'trai cay',
      'mi tom',
      'mi goi',
      'cu cai',
      'khoai',
      'trung ga',
      'trung vit',
      'nuoc ngot',
    ],
    'utilities': ['giay', 'nuoc rua', 'bot giat', 'dau goi', 'tieu dung'],
    'health': ['thuoc', 'vitamin', 'duoc', 'y te', 'khau trang'],
    'transport': ['xang', 'nhien lieu', 'gui xe', 've xe'],
    'education': ['sach', 'tap vo', 'vo viet', 'but bi', 'but chi', 'hoc phi'],
    'entertainment': ['phim', 'game', 've xem', 'giai tri'],
  };

  String? _categoryFor(String description, Set<String> available) {
    final text = ' ${_normalize(description)} ';
    for (final entry in _rules.entries) {
      if (available.contains(entry.key) &&
          entry.value.any((keyword) => text.contains(' $keyword '))) {
        return entry.key;
      }
    }
    return null;
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[àáạảãâầấậẩẫăằắặẳẵ]'), 'a')
        .replaceAll(RegExp(r'[èéẹẻẽêềếệểễ]'), 'e')
        .replaceAll(RegExp(r'[ìíịỉĩ]'), 'i')
        .replaceAll(RegExp(r'[òóọỏõôồốộổỗơờớợởỡ]'), 'o')
        .replaceAll(RegExp(r'[ùúụủũưừứựửữ]'), 'u')
        .replaceAll(RegExp(r'[ỳýỵỷỹ]'), 'y')
        .replaceAll('đ', 'd')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }
}
