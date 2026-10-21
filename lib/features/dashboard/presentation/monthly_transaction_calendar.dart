import 'package:flutter/material.dart';

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
    this.selectedDay,
    super.key,
  });

  final DateTime month;
  final DashboardSnapshot snapshot;
  final List<IncomeEntry> incomes;
  final ValueChanged<DateTime> onSelectDay;
  final DateTime? selectedDay;

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

    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final rows = ((leadingDays + daysInMonth) / 7).ceil();
    return AppCard(
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final minimumWidth = 48.0 * scale * 7;
              final width = constraints.maxWidth > minimumWidth
                  ? constraints.maxWidth
                  : minimumWidth;
              return SizedBox(
                height: rows * 68 * scale + 28 * scale + 8,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 28 * scale,
                          child: Row(
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
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: leadingDays + daysInMonth,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7,
                                mainAxisExtent: 68 * scale,
                              ),
                          itemBuilder: (context, index) {
                            if (index < leadingDays) {
                              return const SizedBox.shrink();
                            }
                            final day = index - leadingDays + 1;
                            final date = DateTime(month.year, month.month, day);
                            return _CalendarDay(
                              date: date,
                              selected: DateUtils.isSameDay(selectedDay, date),
                              net:
                                  (incomeByDay[day] ?? 0) -
                                  (snapshot.dailyTotals[day] ?? 0),
                              positiveColor: finance.income.color,
                              negativeColor: Theme.of(
                                context,
                              ).colorScheme.error,
                              onTap: () => onSelectDay(date),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
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
    required this.selected,
  });

  final DateTime date;
  final int net;
  final Color positiveColor;
  final Color negativeColor;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: BorderSide(
        color: selected || isToday
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
      excludeSemantics: true,
      onTap: onTap,
      selected: selected,
      label: label,
      child: Material(
        color: selected
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
                Text(
                  compactNet(net),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
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
}

/// Compact calendar labels; semantics and the daily list retain exact amounts.
String compactNet(int amount) {
  if (amount == 0) return '0';
  final value = amount.abs();
  final units = [
    (1000000000000000, 'P'),
    (1000000000000, 'T'),
    (1000000000, 'B'),
    (1000000, 'M'),
    (1000, 'K'),
  ];
  for (final unit in units) {
    if (value >= unit.$1) {
      final scaled = value / unit.$1;
      final text = scaled
          .toStringAsFixed(
            scaled < 10 && scaled != scaled.roundToDouble() ? 1 : 0,
          )
          .replaceAll('.', ',');
      return '${amount > 0 ? '+' : '−'}$text${unit.$2}';
    }
  }
  return '${amount > 0 ? '+' : '−'}$value';
}
