import 'package:flutter/material.dart';

import '../../../app/theme/finance_colors.dart';
import '../../../core/utils/money_formatter.dart';
import '../domain/group_fund_progress.dart';

class FundProgressCard extends StatelessWidget {
  const FundProgressCard({
    required this.balanceMinor,
    required this.goalMinor,
    required this.deadline,
    required this.isOwner,
    required this.onEditGoal,
    this.today,
    super.key,
  });

  final int balanceMinor;
  final int? goalMinor;
  final DateTime? deadline;
  final bool isOwner;
  final VoidCallback onEditGoal;

  /// Chỉ để test; mặc định là thời điểm hiện tại.
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final progress = GroupFundProgress.compute(
      balanceMinor: balanceMinor,
      goalMinor: goalMinor,
      deadline: deadline,
      today: today ?? DateTime.now(),
    );
    if (progress.status == GroupFundStatus.noGoal) {
      if (!isOwner) return const SizedBox.shrink();
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: onEditGoal,
          icon: const Icon(Icons.flag_outlined),
          label: const Text('Đặt mục tiêu quỹ'),
        ),
      );
    }
    final theme = Theme.of(context);
    final finance = theme.extension<AppFinanceColors>();
    final color = switch (progress.status) {
      GroupFundStatus.reached =>
        finance?.budgetSafe.color ?? theme.colorScheme.primary,
      GroupFundStatus.overdue =>
        finance?.budgetWarn.color ?? theme.colorScheme.error,
      _ => theme.colorScheme.primary,
    };
    final ratio = progress.ratio!;
    final percent = (ratio * 100).floor();
    final daysLeft = progress.daysLeft;
    final statusText = switch (progress.status) {
      GroupFundStatus.reached => 'Đã đạt mục tiêu',
      GroupFundStatus.overdue => 'Quá hạn ${-daysLeft!} ngày',
      _ when daysLeft == null => '',
      _ when daysLeft == 0 => 'Hạn hôm nay',
      _ => 'Còn $daysLeft ngày',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Mục tiêu quỹ',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (isOwner)
                  IconButton(
                    tooltip: 'Sửa mục tiêu',
                    onPressed: onEditGoal,
                    icon: const Icon(Icons.edit_outlined),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0).toDouble(),
              color: color,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Text('$percent% của ${MoneyFormatter.format(goalMinor!)}'),
            if (statusText.isNotEmpty)
              Text(
                statusText,
                style: TextStyle(
                  color: progress.status == GroupFundStatus.inProgress
                      ? null
                      : color,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
