import 'package:fl_chart/fl_chart.dart';
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
    final months = List.generate(3, (index) {
      final month = MonthUtils.shift(selectedMonth, index - 2);
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
    final theme = Theme.of(context);
    final finance = theme.extension<AppFinanceColors>()!;
    final scheme = theme.colorScheme;
    final axisMax = maxAmount == 0 ? 1.0 : maxAmount * 1.2;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _Legend(color: finance.income.color, label: 'Thu'),
              _Legend(color: finance.budgetOver.color, label: 'Chi'),
              _Legend(
                color: finance.cashFlowBalance.color,
                label: 'Chênh lệch |Thu − Chi|',
              ),
            ],
          ),
          if (!hasData)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Text('Chưa có khoản thu hoặc chi trong 3 tháng này.'),
            )
          else ...[
            const SizedBox(height: AppSpacing.lg),
            Semantics(
              label:
                  'Biểu đồ cột dòng tiền 3 tháng gần nhất. Cả ba cột đều ở phía trên đường 0: '
                  'cột xanh là thu, cột đỏ là chi, cột vàng là độ lớn chênh lệch thu trừ chi. '
                  'Chạm cột để xem giao dịch.',
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final chartWidth = constraints.maxWidth;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: chartWidth,
                      height: 260,
                      child: BarChart(
                        BarChartData(
                          minY: 0,
                          maxY: axisMax,
                          alignment: BarChartAlignment.spaceAround,
                          barGroups: [
                            for (var index = 0; index < months.length; index++)
                              BarChartGroupData(
                                x: index,
                                barsSpace: 4,
                                barRods: [
                                  BarChartRodData(
                                    toY: months[index].income.toDouble(),
                                    width: 20,
                                    color: finance.income.color,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(AppSpacing.xs),
                                    ),
                                  ),
                                  BarChartRodData(
                                    toY: months[index].expense.toDouble(),
                                    width: 20,
                                    color: finance.budgetOver.color,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(AppSpacing.xs),
                                    ),
                                  ),
                                  BarChartRodData(
                                    toY:
                                        (months[index].income -
                                                months[index].expense)
                                            .abs()
                                            .toDouble(),
                                    width: 20,
                                    color: finance.cashFlowBalance.color,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(AppSpacing.xs),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: axisMax / 2,
                            checkToShowHorizontalLine: (value) => value != 0,
                            getDrawingHorizontalLine: (_) => FlLine(
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.5,
                              ),
                              strokeWidth: 1,
                            ),
                          ),
                          extraLinesData: ExtraLinesData(
                            horizontalLines: [
                              HorizontalLine(
                                y: 0,
                                color: scheme.outline,
                                strokeWidth: 1.5,
                              ),
                            ],
                          ),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 54,
                                interval: axisMax / 2,
                                getTitlesWidget: (value, meta) => Padding(
                                  padding: const EdgeInsets.only(
                                    right: AppSpacing.xs,
                                  ),
                                  child: Text(
                                    MoneyFormatter.compact(value.round()),
                                    textAlign: TextAlign.right,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 28,
                                getTitlesWidget: (value, meta) {
                                  final index = value.round();
                                  if (index != value ||
                                      index < 0 ||
                                      index >= months.length) {
                                    return const SizedBox.shrink();
                                  }
                                  final month = months[index].month;
                                  return SideTitleWidget(
                                    meta: meta,
                                    child: Text(
                                      '${month.month}/${month.year % 100}',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          barTouchData: BarTouchData(
                            touchExtraThreshold: const EdgeInsets.all(14),
                            mouseCursorResolver: (event, response) =>
                                response?.spot == null
                                ? SystemMouseCursors.basic
                                : SystemMouseCursors.click,
                            touchCallback: (event, response) {
                              if (event is FlTapUpEvent) {
                                final spot = response?.spot;
                                if (spot != null) {
                                  context.go(
                                    '/invoices?month=${MonthUtils.key(months[spot.touchedBarGroupIndex].month)}',
                                  );
                                }
                              }
                            },
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipColor: (_) => scheme.inverseSurface,
                              fitInsideHorizontally: true,
                              fitInsideVertically: true,
                              maxContentWidth: 180,
                              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                final item = months[groupIndex];
                                final amount = switch (rodIndex) {
                                  0 => item.income,
                                  1 => item.expense,
                                  _ => item.income - item.expense,
                                };
                                final label = switch (rodIndex) {
                                  0 => 'Thu',
                                  1 => 'Chi',
                                  _ => 'Chênh lệch',
                                };
                                return BarTooltipItem(
                                  '${item.month.month}/${item.month.year} · $label\n'
                                  '${MoneyFormatter.format(amount)}',
                                  TextStyle(color: scheme.onInverseSurface),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
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
