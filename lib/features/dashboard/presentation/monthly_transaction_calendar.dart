import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../app/theme/finance_colors.dart';
import '../../../core/utils/month_utils.dart';
import '../../../core/utils/money_formatter.dart';
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
    final isEn = context.tr.isEn;
    final weekdays = isEn
        ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        : const ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final weekday in weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      weekday,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: leadingDays + daysInMonth,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent:
                  46 *
                  (MediaQuery.textScalerOf(context).scale(12) / 12).clamp(
                    1.0,
                    3.0,
                  ),
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
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
                net: (incomeByDay[day] ?? 0) - (snapshot.dailyTotals[day] ?? 0),
                positiveColor: finance.income.color,
                negativeColor: Theme.of(context).colorScheme.error,
                onTap: () => onSelectDay(date),
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
    final hasTransaction = net != 0;
    final color = net > 0 ? positiveColor : negativeColor;

    return Semantics(
      button: true,
      selected: selected,
      label: context.tr.isEn
          ? 'Day ${date.day}, ${net >= 0 ? 'surplus' : 'deficit'} ${MoneyFormatter.format(net.abs())}'
          : 'Ngày ${date.day}, ${net >= 0 ? 'dư' : 'thiếu'} ${MoneyFormatter.format(net.abs())}',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primaryContainer
                : (isToday
                      ? theme.colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        )
                      : theme.colorScheme.surfaceContainerLow),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : (isToday
                        ? theme.colorScheme.outline
                        : theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.4,
                          )),
              width: selected ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.only(top: 4, bottom: 2, left: 1, right: 1),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              FittedBox(
                child: Text(
                  '${date.day}',
                  maxLines: 1,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: selected || isToday
                        ? FontWeight.w800
                        : FontWeight.w500,
                    color: selected
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurface,
                    fontSize: 12,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: MediaQuery.textScalerOf(context).scale(13),
                child: hasTransaction
                    ? Text(
                        compactNet(net),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: color,
                          height: 1.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
              ),
            ],
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
