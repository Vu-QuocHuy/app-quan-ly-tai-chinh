import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/groups/domain/group_fund_progress.dart';

void main() {
  final today = DateTime(2026, 10, 20, 15, 30);

  test('không có mục tiêu', () {
    final progress = GroupFundProgress.compute(
      balanceMinor: 500000,
      goalMinor: null,
      deadline: null,
      today: today,
    );
    expect(progress.status, GroupFundStatus.noGoal);
    expect(progress.ratio, isNull);
    expect(progress.daysLeft, isNull);
  });

  test('đang góp, còn ngày', () {
    final progress = GroupFundProgress.compute(
      balanceMinor: 6400000,
      goalMinor: 10000000,
      deadline: DateTime(2026, 12, 15),
      today: today,
    );
    expect(progress.status, GroupFundStatus.inProgress);
    expect(progress.ratio, closeTo(0.64, 1e-9));
    expect(progress.daysLeft, 56);
  });

  test('hạn đúng hôm nay vẫn đang góp, còn 0 ngày', () {
    final progress = GroupFundProgress.compute(
      balanceMinor: 100,
      goalMinor: 1000,
      deadline: DateTime(2026, 10, 20),
      today: today,
    );
    expect(progress.status, GroupFundStatus.inProgress);
    expect(progress.daysLeft, 0);
  });

  test('quá hạn chưa đạt', () {
    final progress = GroupFundProgress.compute(
      balanceMinor: 100,
      goalMinor: 1000,
      deadline: DateTime(2026, 10, 17),
      today: today,
    );
    expect(progress.status, GroupFundStatus.overdue);
    expect(progress.daysLeft, -3);
  });

  test('đạt mục tiêu sau hạn vẫn là đạt, tỷ lệ có thể vượt 1', () {
    final progress = GroupFundProgress.compute(
      balanceMinor: 1500,
      goalMinor: 1000,
      deadline: DateTime(2026, 10, 1),
      today: today,
    );
    expect(progress.status, GroupFundStatus.reached);
    expect(progress.ratio, closeTo(1.5, 1e-9));
  });

  test('có mục tiêu, không có hạn', () {
    final progress = GroupFundProgress.compute(
      balanceMinor: 0,
      goalMinor: 1000,
      deadline: null,
      today: today,
    );
    expect(progress.status, GroupFundStatus.inProgress);
    expect(progress.ratio, 0);
    expect(progress.daysLeft, isNull);
  });
}
