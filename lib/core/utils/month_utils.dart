abstract final class MonthUtils {
  static DateTime normalize(DateTime date) => DateTime(date.year, date.month);

  static DateTime shift(DateTime date, int delta) {
    final month = normalize(date);
    return DateTime(month.year, month.month + delta);
  }

  static String key(DateTime date) {
    final month = normalize(date);
    return '${month.year}-${month.month.toString().padLeft(2, '0')}';
  }

  static String label(DateTime date) {
    final month = normalize(date);
    return 'Tháng ${month.month.toString().padLeft(2, '0')}/${month.year}';
  }
}
