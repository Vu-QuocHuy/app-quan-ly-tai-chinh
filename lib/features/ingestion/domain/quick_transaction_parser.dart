class QuickTransaction {
  const QuickTransaction({
    required this.amountMinor,
    required this.isIncome,
    required this.title,
    required this.date,
  });

  final int amountMinor;
  final bool isIncome;
  final String title;
  final DateTime date;
}

abstract final class QuickTransactionParser {
  static final _money = RegExp(
    r'(\d{1,3}(?:[.,]\d{3})+|\d+(?:[.,]\d+)?)\s*(triệu|tr|nghìn|ngàn|k|đồng|vnd|đ)?(?=$|[\s,.;!?/])',
    caseSensitive: false,
    unicode: true,
  );

  static QuickTransaction parse(String input, {DateTime? now}) {
    final text = input.trim();
    if (text.isEmpty || text.length > 300) {
      throw const FormatException('Nhập mô tả giao dịch dưới 300 ký tự.');
    }
    final matches = _money.allMatches(text).toList();
    if (matches.isEmpty) {
      throw const FormatException('Chưa tìm thấy số tiền trong mô tả.');
    }
    final match =
        matches.where((item) => item.group(2) != null).firstOrNull ??
        matches.first;
    final number = match.group(1)!;
    final unit = (match.group(2) ?? '').toLowerCase();
    final multiplier = switch (unit) {
      'triệu' || 'tr' => 1000000,
      'nghìn' || 'ngàn' || 'k' => 1000,
      _ => 1,
    };
    if (multiplier == 1 && RegExp(r'[.,]\d{1,2}$').hasMatch(number)) {
      throw const FormatException('Tiền Việt Nam cần nhập số đồng nguyên.');
    }
    final normalized = multiplier == 1
        ? number.replaceAll(RegExp(r'[.,]'), '')
        : number.replaceAll(',', '.');
    final amount = multiplier == 1
        ? int.tryParse(normalized)
        : ((double.tryParse(normalized) ?? 0) * multiplier).round();
    if (amount == null || amount <= 0 || amount > 9007199254740991) {
      throw const FormatException('Số tiền không hợp lệ.');
    }
    final lower = text.toLowerCase();
    final isIncome = RegExp(
      r'\b(nhận|thu|lương|thưởng|được trả|bán)\b',
      unicode: true,
    ).hasMatch(lower);
    final baseDate = now ?? DateTime.now();
    final date = lower.contains('hôm qua')
        ? DateTime(baseDate.year, baseDate.month, baseDate.day - 1)
        : baseDate;
    final title = text
        .replaceRange(match.start, match.end, '')
        .replaceAll(RegExp(r'\b(hôm nay|hôm qua)\b', caseSensitive: false), '')
        .trim();
    return QuickTransaction(
      amountMinor: amount,
      isIncome: isIncome,
      title: title.isEmpty ? (isIncome ? 'Khoản thu' : 'Khoản chi') : title,
      date: date,
    );
  }
}
