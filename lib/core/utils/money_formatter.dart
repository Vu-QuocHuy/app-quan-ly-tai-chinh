import 'package:intl/intl.dart';

abstract final class MoneyFormatter {
  static final NumberFormat _vnd = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: '₫',
    decimalDigits: 0,
  );

  static final NumberFormat _compactBillions = NumberFormat(
    '#,##0.##',
    'vi_VN',
  );
  static final NumberFormat _compactMillions = NumberFormat('#,##0.#', 'vi_VN');

  static String format(int minor, {String currencyCode = 'VND'}) {
    if (currencyCode == 'VND') return _vnd.format(minor);
    return NumberFormat.simpleCurrency(name: currencyCode).format(minor / 100);
  }

  /// Dạng rút gọn cho nhãn trục biểu đồ, thanh tỉ trọng và lối thoát khi số
  /// tiền tràn khỏi hero: `12,5 tr ₫`, `1,23 tỷ ₫`.
  ///
  /// Dưới một triệu thì trả về dạng đầy đủ — rút gọn ở đó không tiết kiệm được
  /// chỗ mà lại làm mất độ chính xác.
  static String compact(int minor) {
    final absolute = minor.abs();
    if (absolute >= 1000000000) {
      return '${_compactBillions.format(minor / 1000000000)} tỷ ₫';
    }
    if (absolute >= 1000000) {
      return '${_compactMillions.format(minor / 1000000)} tr ₫';
    }
    return format(minor);
  }

  static int? tryParse(String input) {
    final normalized = input.replaceAll(RegExp(r'[^0-9-]'), '');
    return int.tryParse(normalized);
  }
}
