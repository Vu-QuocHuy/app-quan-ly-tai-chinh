import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../app/theme/finance_colors.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/utils/month_utils.dart';
import '../../../shared/widgets/app_card.dart';
import '../../income/data/income_repository.dart';
import '../../invoices/domain/invoice_models.dart';

class MonthlyTransactionCalendar extends StatelessWidget {
  const MonthlyTransactionCalendar({
    required this.month,
    required this.snapshot,
    required this.incomes,
    required this.onSelectDay,
    super.key,
  });

  final DateTime month;
  final DashboardSnapshot snapshot;
  final List<IncomeEntry> incomes;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final incomeByDay = <int, int>{};
    final monthKey = MonthUtils.key(month);
    for (final income in incomes) {
      if (MonthUtils.key(income.receivedAt) == monthKey) {
        incomeByDay.update(
          income.receivedAt.day,
          (total) => total + income.amountMinor,
          ifAbsent: () => income.amountMinor,
        );
      }
    }

    final firstWeekday = DateTime(month.year, month.month).weekday;
    final leadingDays = firstWeekday - DateTime.monday;
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final finance = Theme.of(context).extension<AppFinanceColors>()!;

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          children: [
            Row(
              children: [
                for (final weekday in const [
                  'T2',
                  'T3',
                  'T4',
                  'T5',
                  'T6',
                  'T7',
                  'CN',
                ])
                  Expanded(
                    child: Center(
                      child: Text(
                        weekday,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: leadingDays + daysInMonth,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                crossAxisSpacing: AppSpacing.xs,
                mainAxisSpacing: AppSpacing.xs,
                mainAxisExtent: 64,
              ),
              itemBuilder: (context, index) {
                if (index < leadingDays) return const SizedBox.shrink();
                final day = index - leadingDays + 1;
                final date = DateTime(month.year, month.month, day);
                return _CalendarDay(
                  date: date,
                  net:
                      (incomeByDay[day] ?? 0) -
                      (snapshot.dailyTotals[day] ?? 0),
                  positiveColor: finance.income.color,
                  negativeColor: Theme.of(context).colorScheme.error,
                  onTap: () => onSelectDay(date),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.date,
    required this.net,
    required this.positiveColor,
    required this.negativeColor,
    required this.onTap,
  });

  final DateTime date;
  final int net;
  final Color positiveColor;
  final Color negativeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    final shape = RoundedRectangleBorder(
      borderRadius: AppShapes.controlRadius,
      side: BorderSide(
        color: isToday
            ? theme.colorScheme.primary
            : theme.colorScheme.outlineVariant,
      ),
    );
    final color = net > 0
        ? positiveColor
        : net < 0
        ? negativeColor
        : theme.colorScheme.onSurfaceVariant;
    final label = net == 0
        ? 'Ngày ${date.day}, thu chi cân bằng'
        : 'Ngày ${date.day}, ${net > 0 ? 'dư' : 'thiếu'} ${MoneyFormatter.format(net.abs())}';

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: isToday
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerLow,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
            child: Column(
              children: [
                Text(
                  '${date.day}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: isToday ? FontWeight.bold : null,
                  ),
                ),
                const SizedBox(height: 2),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 18,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      net == 0
                          ? '—'
                          : '${net > 0 ? '+' : '−'}${_calendarAmount(net.abs())}',
                      maxLines: 1,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _calendarAmount(int amount) {
    if (amount >= 1000000) {
      return MoneyFormatter.compact(
        amount,
      ).replaceAll(' tr ₫', 'tr').replaceAll(' tỷ ₫', 'tỷ');
    }
    if (amount < 1000) return '$amount';
    final tenths = amount ~/ 100;
    final whole = tenths ~/ 10;
    final decimal = tenths % 10;
    return '${decimal == 0 ? whole : '$whole,$decimal'}K';
  }
}
