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
                  income: incomeByDay[day] ?? 0,
                  expense: snapshot.dailyTotals[day] ?? 0,
                  incomeColor: finance.income.color,
                  expenseColor: finance.expense.color,
                  onTap: () => onSelectDay(date),
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                _CalendarLegend(
                  color: finance.income.color,
                  icon: Icons.arrow_upward_rounded,
                  label: 'Thu',
                ),
                const SizedBox(width: AppSpacing.lg),
                _CalendarLegend(
                  color: finance.expense.color,
                  icon: Icons.arrow_downward_rounded,
                  label: 'Chi',
                ),
              ],
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
    required this.income,
    required this.expense,
    required this.incomeColor,
    required this.expenseColor,
    required this.onTap,
  });

  final DateTime date;
  final int income;
  final int expense;
  final Color incomeColor;
  final Color expenseColor;
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
    final label =
        'Ngày ${date.day}, thu ${MoneyFormatter.format(income)}, '
        'chi ${MoneyFormatter.format(expense)}';

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
                _DayAmount(amount: income, color: incomeColor, arrow: '↑'),
                _DayAmount(amount: expense, color: expenseColor, arrow: '↓'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayAmount extends StatelessWidget {
  const _DayAmount({
    required this.amount,
    required this.color,
    required this.arrow,
  });

  final int amount;
  final Color color;
  final String arrow;

  @override
  Widget build(BuildContext context) {
    final value = amount == 0 ? '—' : _shortAmount(amount);
    return SizedBox(
      width: double.infinity,
      height: 12,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '$arrow$value',
          maxLines: 1,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontSize: 9,
            height: 1,
          ),
        ),
      ),
    );
  }

  String _shortAmount(int value) =>
      (value >= 1000000
              ? MoneyFormatter.compact(value)
              : MoneyFormatter.format(value))
          .replaceAll(RegExp(r'\s*₫'), '');
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: color, size: AppIconSizes.sm),
      const SizedBox(width: AppSpacing.xs),
      Text(label, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}
