import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/groups/domain/group_split_calculator.dart';

void main() {
  test('requires exact amounts to reconcile', () {
    expect(
      GroupSplitCalculator.calculate(
        totalMinor: 100000,
        memberIds: const ['a', 'b'],
        values: const {'a': 60000, 'b': 40000},
        mode: GroupSplitMode.exact,
      ),
      {'a': 60000, 'b': 40000},
    );
    expect(
      GroupSplitCalculator.calculate(
        totalMinor: 100000,
        memberIds: const ['a', 'b'],
        values: const {'a': 60000, 'b': 30000},
        mode: GroupSplitMode.exact,
      ),
      isNull,
    );
  });

  test('distributes percentage rounding remainder without losing money', () {
    final result = GroupSplitCalculator.calculate(
      totalMinor: 100,
      memberIds: const ['a', 'b', 'c'],
      values: const {'a': 33.33, 'b': 33.33, 'c': 33.34},
      mode: GroupSplitMode.percentage,
    );

    expect(result!.values.reduce((a, b) => a + b), 100);
  });
}
