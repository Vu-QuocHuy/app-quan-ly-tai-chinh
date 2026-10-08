import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../app/theme/finance_colors.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/utils/month_utils.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../income/data/income_repository.dart';

class CashFlowTrendCard extends ConsumerWidget {
  const CashFlowTrendCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMonth = ref.watch(selectedMonthProvider);
    final expenses = ref.watch(monthlyExpenseTotalsProvider);
    final incomes = ref.watch(incomesProvider);
    if (expenses.isLoading || incomes.isLoading) return const SkeletonChart();

    if (expenses.hasError || incomes.hasError) {
      return AppCard(
        child: Row(
          children: [
            const Expanded(child: Text('Không tải được xu hướng dòng tiền.')),
            TextButton(
              onPressed: () {
                ref.invalidate(monthlyExpenseTotalsProvider);
                ref.invalidate(incomesProvider);
              },
              child: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }

    final incomeTotals = <String, int>{};
    for (final entry in incomes.valueOrNull ?? const <IncomeEntry>[]) {
      final key = MonthUtils.key(entry.receivedAt);
      incomeTotals.update(
        key,
        (total) => total + entry.amountMinor,
        ifAbsent: () => entry.amountMinor,
      );
    }
    final expenseTotals = expenses.valueOrNull ?? const <String, int>{};
    final months = List.generate(6, (index) {
      final month = MonthUtils.shift(selectedMonth, index - 5);
      final key = MonthUtils.key(month);
      return (
        month: month,
        income: incomeTotals[key] ?? 0,
        expense: expenseTotals[key] ?? 0,
      );
    });
    final hasData = months.any((item) => item.income > 0 || item.expense > 0);
    final maxAmount = months.fold<int>(0, (max, item) {
      final current = item.income > item.expense ? item.income : item.expense;
      return current > max ? current : max;
    });
    final finance = Theme.of(context).extension<AppFinanceColors>()!;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Legend(color: finance.income.color, label: 'Thu'),
              const SizedBox(width: AppSpacing.lg),
              _Legend(color: finance.expense.color, label: 'Chi'),
            ],
          ),
          if (!hasData)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Text('Chưa có khoản thu hoặc chi trong 6 tháng này.'),
            )
          else ...[
            const SizedBox(height: AppSpacing.sm),
            for (final item in months) ...[
              const Divider(height: 1, indent: 0, endIndent: 0),
              Semantics(
                button: true,
                onTap: () =>
                    context.go('/invoices?month=${MonthUtils.key(item.month)}'),
                label:
                    '${MonthUtils.label(item.month)}, '
                    'thu ${MoneyFormatter.format(item.income)}, '
                    'chi ${MoneyFormatter.format(item.expense)}, '
                    'thu trừ chi ${MoneyFormatter.format(item.income - item.expense)}. '
                    'Xem giao dịch.',
                child: ExcludeSemantics(
                  child: InkWell(
                    onTap: () => context.go(
                      '/invoices?month=${MonthUtils.key(item.month)}',
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Text(
                                '${item.month.month.toString().padLeft(2, '0')}/${item.month.year}',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  'Thu − chi ${MoneyFormatter.compact(item.income - item.expense)}',
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: item.income >= item.expense
                                            ? finance.income.color
                                            : finance.budgetWarn.color,
                                      ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              const Icon(Icons.chevron_right, size: 18),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _AmountBar(
                            label: 'Thu',
                            amount: item.income,
                            maxAmount: maxAmount,
                            color: finance.income.color,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          _AmountBar(
                            label: 'Chi',
                            amount: item.expense,
                            maxAmount: maxAmount,
                            color: finance.expense.color,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
        child: const SizedBox(width: 10, height: 10),
      ),
      const SizedBox(width: AppSpacing.xs),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _AmountBar extends StatelessWidget {
  const _AmountBar({
    required this.label,
    required this.amount,
    required this.maxAmount,
    required this.color,
  });

  final String label;
  final int amount;
  final int maxAmount;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 32,
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
      Expanded(
        child: LinearProgressIndicator(
          value: maxAmount == 0 ? 0 : amount / maxAmount,
          minHeight: 8,
          color: color,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      SizedBox(
        width: 88,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            MoneyFormatter.compact(amount),
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ),
    ],
  );
}
