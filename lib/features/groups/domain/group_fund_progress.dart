enum GroupFundStatus { noGoal, inProgress, reached, overdue }

class GroupFundProgress {
  const GroupFundProgress({required this.status, this.ratio, this.daysLeft});

  final GroupFundStatus status;

  /// Số dư / mục tiêu; không chặn ở 1.0. `null` khi chưa có mục tiêu.
  final double? ratio;

  /// Số ngày tới hạn; âm khi quá hạn; `null` khi không có hạn hoặc mục tiêu.
  final int? daysLeft;

  static GroupFundProgress compute({
    required int balanceMinor,
    int? goalMinor,
    DateTime? deadline,
    required DateTime today,
  }) {
    if (goalMinor == null || goalMinor <= 0) {
      return const GroupFundProgress(status: GroupFundStatus.noGoal);
    }
    final daysLeft = deadline == null
        ? null
        : _dateOnly(deadline).difference(_dateOnly(today)).inDays;
    final status = balanceMinor >= goalMinor
        ? GroupFundStatus.reached
        : daysLeft != null && daysLeft < 0
        ? GroupFundStatus.overdue
        : GroupFundStatus.inProgress;
    return GroupFundProgress(
      status: status,
      ratio: balanceMinor / goalMinor,
      daysLeft: daysLeft,
    );
  }

  // UTC để phép trừ ngày không lệch vì giờ mùa hè.
  static DateTime _dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
}
