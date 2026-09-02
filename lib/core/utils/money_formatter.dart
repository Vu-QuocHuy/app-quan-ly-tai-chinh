import 'package:intl/intl.dart';

abstract final class MoneyFormatter {
  static final NumberFormat _vnd = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: '₫',
    decimalDigits: 0,
  );

  static String format(int minor, {String currencyCode = 'VND'}) {
    if (currencyCode == 'VND') return _vnd.format(minor);
    return NumberFormat.simpleCurrency(name: currencyCode).format(minor / 100);
  }

  static int? tryParse(String input) {
    final normalized = input.replaceAll(RegExp(r'[^0-9-]'), '');
    return int.tryParse(normalized);
  }
}
