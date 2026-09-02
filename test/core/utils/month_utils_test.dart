import 'package:flutter_test/flutter_test.dart';

import 'package:hoadon_insight/core/utils/month_utils.dart';

void main() {
  test('normalizes month keys and labels', () {
    final date = DateTime(2026, 8, 29, 18, 30);

    expect(MonthUtils.key(date), '2026-08');
    expect(MonthUtils.label(date), 'Tháng 08/2026');
    expect(MonthUtils.normalize(date), DateTime(2026, 8));
  });

  test('shifts across year boundaries', () {
    expect(MonthUtils.key(MonthUtils.shift(DateTime(2026, 1), -1)), '2025-12');
    expect(MonthUtils.key(MonthUtils.shift(DateTime(2026, 12), 1)), '2027-01');
  });
}
