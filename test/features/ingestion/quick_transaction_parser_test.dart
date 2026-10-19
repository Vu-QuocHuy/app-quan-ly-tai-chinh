import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/ingestion/domain/quick_transaction_parser.dart';

void main() {
  test('parses whole dong and yesterday expense', () {
    final result = QuickTransactionParser.parse(
      'Ăn trưa 35k hôm qua',
      now: DateTime(2026, 10, 20),
    );
    expect(result.amountMinor, 35000);
    expect(result.isIncome, false);
    expect(result.date, DateTime(2026, 10, 19));
  });

  test('parses income with fractional million into whole dong', () {
    final result = QuickTransactionParser.parse('Nhận lương 12,5 triệu');
    expect(result.amountMinor, 12500000);
    expect(result.isIncome, true);
  });

  test('rejects missing and zero amounts', () {
    expect(() => QuickTransactionParser.parse('Ăn trưa'), throwsFormatException);
    expect(() => QuickTransactionParser.parse('Ăn trưa 0đ'), throwsFormatException);
    expect(() => QuickTransactionParser.parse('Ăn trưa 1,5đ'), throwsFormatException);
  });
}
