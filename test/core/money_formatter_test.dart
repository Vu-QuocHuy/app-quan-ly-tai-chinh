import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/utils/money_formatter.dart';

void main() {
  test('VND input accepts whole đồng and rejects decimal amounts', () {
    expect(MoneyFormatter.tryParse('125000'), 125000);
    expect(MoneyFormatter.tryParse('125.000 ₫'), 125000);
    expect(MoneyFormatter.tryParse(MoneyFormatter.format(125000)), 125000);
    expect(MoneyFormatter.tryParse('12,5'), isNull);
    expect(MoneyFormatter.tryParse('12.5'), isNull);
    expect(MoneyFormatter.tryParse('1.000,5'), isNull);
  });
}
