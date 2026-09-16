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

  String? _categoryFor(String description, Set<String> available) {
    final text = _normalize(description);
    const rules = <String, List<String>>{
      'food': [
        'thit',
        'ca',
        'rau',
        'cu',
        'qua',
        'gao',
        'mi',
        'sua',
        'banh',
        'do uong',
        'thuc pham',
        'gia vi',
      ],
      'utilities': ['giay', 'nuoc rua', 'bot giat', 'dau goi', 'tieu dung'],
      'health': ['thuoc', 'vitamin', 'duoc', 'y te', 'khau trang'],
      'transport': ['xang', 'nhien lieu', 'gui xe', 've xe'],
      'education': ['sach', 'vo', 'but', 'hoc phi'],
      'entertainment': ['phim', 'game', 've xem', 'giai tri'],
    };
    for (final entry in rules.entries) {
      if (available.contains(entry.key) && entry.value.any(text.contains)) {
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
        .replaceAll('đ', 'd');
  }
}
