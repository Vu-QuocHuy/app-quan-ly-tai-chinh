import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/utils/month_utils.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/theme/category_palette.dart';
import '../../../app/theme/finance_colors.dart';
import '../../../shared/widgets/category_avatar.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_callout.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/month_selector.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../invoices/domain/invoice_filters.dart';
import '../../income/data/income_repository.dart';
import '../../income/presentation/income_entry_sheet.dart';
import '../../../shared/widgets/section_header.dart';
import 'cash_flow_trend_card.dart';
import 'monthly_transaction_calendar.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<DashboardSnapshot>>(dashboardProvider, (
      previous,
      next,
    ) {
      final snapshot = next.asData?.value;
      if (snapshot != null) _deliverBudgetNotification(snapshot);
    }, fireImmediately: true);
  }

  Future<void> _deliverBudgetNotification(DashboardSnapshot snapshot) async {
    await ref.read(budgetNotificationServiceProvider).notifyIfNeeded(snapshot);
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(dashboardProvider);
    final incomes = ref.watch(incomesProvider);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final incomeCategories =
        ref.watch(incomeCategoriesProvider).value ?? const [];
    final selectedMonth = ref.watch(selectedMonthProvider);
    final hasPendingReview =
        ref
            .watch(
              filteredInvoiceSummariesProvider(
                const InvoiceListQuery(
                  filter: InvoiceFilter(status: InvoiceStatus.needsReview),
                  limit: 1,
                ),
              ),
            )
            .valueOrNull
            ?.isNotEmpty ??
        false;

    void openIncomeEntry() {
      showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => const IncomeEntrySheet(),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: const Text('Tổng quan'),
            actions: [
              IconButton(
                tooltip: 'Lịch sử giao dịch',
                onPressed: () => context.push('/invoices'),
                icon: const Icon(Icons.receipt_long_outlined),
              ),
            ],
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: MonthSelector(),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
            sliver: dashboard.when(
              loading: () => const SliverToBoxAdapter(
                child: Column(
                  children: [
                    SkeletonHero(),
                    SizedBox(height: AppSpacing.xl),
                    SkeletonChart(),
                    SizedBox(height: AppSpacing.xl),
                    _CategoryBreakdownSkeleton(),
                  ],
                ),
              ),
              error: (error, stack) => SliverFillRemaining(
                hasScrollBody: false,
                child: AppErrorState(
                  error: error,
                  stackTrace: stack,
                  onRetry: () => ref.invalidate(dashboardProvider),
                ),
              ),
              data: (snapshot) => SliverList.list(
                children: [
                  _HeroSummary(
                    snapshot: snapshot,
                    month: selectedMonth,
                    incomeError: incomes.hasError,
                    incomeTotal: incomes.whenOrNull(
                      data: (entries) => entries
                          .where(
                            (entry) =>
                                MonthUtils.key(entry.receivedAt) ==
                                MonthUtils.key(selectedMonth),
                          )
                          .fold<int>(
                            0,
                            (total, entry) => total + entry.amountMinor,
                          ),
                    ),
                  ),
                  if (hasPendingReview) ...[
                    const SizedBox(height: AppSpacing.lg),
                    AppCallout(
                      title: 'Có giao dịch cần kiểm tra',
                      message:
                          'Kiểm tra dữ liệu hóa đơn trước khi khoản chi xuất hiện trong ngân sách và báo cáo.',
                      tone: CalloutTone.warning,
                      icon: Icons.fact_check_outlined,
                      actions: [
                        TextButton(
                          onPressed: () => context.push('/invoices?review=1'),
                          child: const Text('Kiểm tra giao dịch'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  _BudgetCard(
                    snapshot: snapshot,
                    month: selectedMonth,
                    onViewBudgets: () => context.go('/budgets'),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(
                    title: 'Lịch thu chi',
                    subtitle: 'Chênh lệch thu và chi từng ngày',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  MonthlyTransactionCalendar(
                    month: selectedMonth,
                    snapshot: snapshot,
                    incomes: incomes.valueOrNull ?? const <IncomeEntry>[],
                    onSelectDay: (day) => context.push(
                      '/invoices/day/${day.toIso8601String().substring(0, 10)}',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(title: 'Chi tiêu theo ngày'),
                  const SizedBox(height: AppSpacing.md),
                  _DailyChart(snapshot: snapshot, month: selectedMonth),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(title: 'Cơ cấu chi tiêu'),
                  const SizedBox(height: AppSpacing.md),
                  _CategoryBreakdown(
                    snapshot: snapshot,
                    categories: categories,
                    month: selectedMonth,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(title: 'Cơ cấu thu nhập'),
                  const SizedBox(height: AppSpacing.md),
                  incomes.when(
                    data: (entries) => _IncomeBreakdown(
                      entries: entries
                          .where(
                            (entry) =>
                                MonthUtils.key(entry.receivedAt) ==
                                MonthUtils.key(selectedMonth),
                          )
                          .toList(growable: false),
                      categories: incomeCategories,
                      onAddIncome: openIncomeEntry,
                    ),
                    loading: () => const AppCard(
                      child: SizedBox(
                        height: 104,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                    error: (error, stackTrace) => AppErrorState(
                      error: error,
                      stackTrace: stackTrace,
                      onRetry: () => ref.invalidate(incomesProvider),
                      compact: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(
                    title: 'Dòng tiền 3 tháng gần nhất',
                    subtitle: 'Chạm vào tháng để xem giao dịch',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const CashFlowTrendCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSummary extends StatelessWidget {
  const _HeroSummary({
    required this.snapshot,
    required this.month,
    required this.incomeTotal,
    required this.incomeError,
  });

  final DashboardSnapshot snapshot;
  final DateTime month;
  final int? incomeTotal;
  final bool incomeError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finance = theme.extension<AppFinanceColors>()!;
    final income = incomeTotal;
    final balance = income == null ? null : income - snapshot.totalMinor;
    final balanceTone = balance == null || balance >= 0
        ? finance.budgetSafe
        : finance.budgetOver;

    return Semantics(
      container: true,
      label:
          'Thu chi ${MonthUtils.label(month)}: thu ${income == null ? 'đang tải' : MoneyFormatter.format(income)}, chi ${MoneyFormatter.format(snapshot.totalMinor)}, ${snapshot.invoiceCount} khoản chi',
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Thu chi', style: theme.textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${MonthUtils.label(month)} · ${snapshot.invoiceCount} khoản chi',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _CashFlowMetric(
                    label: 'Thu',
                    amount: income,
                    loadingLabel: incomeError ? 'Không tải được' : 'Đang tải…',
                    icon: Icons.arrow_upward_rounded,
                    tone: finance.income,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _CashFlowMetric(
                    label: 'Chi',
                    amount: snapshot.totalMinor,
                    icon: Icons.arrow_downward_rounded,
                    tone: finance.expense,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            DecoratedBox(
              decoration: ShapeDecoration(
                color: balanceTone.container,
                shape: AppShapes.control,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      balance != null && balance < 0
                          ? Icons.trending_down_rounded
                          : Icons.trending_up_rounded,
                      size: AppIconSizes.sm,
                      color: balanceTone.onContainer,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Chênh lệch thu − chi',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: balanceTone.onContainer,
                        ),
                      ),
                    ),
                    if (balance == null)
                      Text(
                        incomeError ? 'Không tải được' : 'Đang tải…',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: balanceTone.onContainer,
                        ),
                      )
                    else
                      Expanded(
                        child: MoneyText(
                          balance,
                          emphasis: MoneyEmphasis.body,
                          fitToWidth: true,
                          tone: balanceTone,
                          textAlign: TextAlign.right,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (snapshot.monthOverMonthChange case final change?) ...[
              const SizedBox(height: AppSpacing.md),
              StatusPill(
                icon: change >= 0 ? Icons.trending_up : Icons.trending_down,
                label:
                    'Chi tiêu ${change >= 0 ? 'tăng' : 'giảm'} ${(change.abs() * 100).round()}% so với tháng trước',
                tone: change >= 0 ? StatusTone.warn : StatusTone.safe,
                dense: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CashFlowMetric extends StatelessWidget {
  const _CashFlowMetric({
    required this.label,
    required this.amount,
    required this.icon,
    required this.tone,
    this.loadingLabel,
  });

  final String label;
  final int? amount;
  final IconData icon;
  final FinanceTone tone;
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: tone.container,
        shape: AppShapes.control,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tone.onContainer.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: Icon(
                      icon,
                      size: AppIconSizes.sm,
                      color: tone.onContainer,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: tone.onContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (amount == null)
              Text(
                loadingLabel ?? 'Đang tải…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tone.onContainer,
                ),
              )
            else
              MoneyText(
                amount!,
                emphasis: MoneyEmphasis.title,
                fitToWidth: true,
                tone: tone,
              ),
          ],
        ),
      ),
    );
  }
}

/// Thẻ ngân sách chỉ cảnh báo theo từng danh mục; danh mục chưa đặt hạn mức
/// là không giới hạn nên không có cảnh báo tổng tháng.
class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.snapshot,
    required this.month,
    required this.onViewBudgets,
  });

  static const _maxWarnings = 3;

  final DashboardSnapshot snapshot;
  final DateTime month;
  final VoidCallback onViewBudgets;

  @override
  Widget build(BuildContext context) {
    final hasBudget = snapshot.categoryBudgets.isNotEmpty;
    final overBudget = snapshot.overBudgetCategories;
    final hasOver = overBudget.isNotEmpty;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final finance = theme.extension<AppFinanceColors>()!;
    final statusColor = hasOver ? finance.budgetOver : finance.budgetSafe;
    final hiddenCount = overBudget.length - _maxWarnings;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: statusColor.container,
                  shape: AppShapes.control,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Icon(
                    Icons.savings_outlined,
                    size: AppIconSizes.md,
                    color: statusColor.onContainer,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ngân sách', style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      MonthUtils.label(month),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onViewBudgets,
                child: Text(hasBudget ? 'Quản lý' : 'Thiết lập'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (hasBudget) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    hasOver
                        ? 'Danh mục vượt hạn mức nhiều nhất'
                        : 'Các danh mục có hạn mức đều chưa vượt.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                StatusPill(
                  icon: hasOver
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  label: hasOver
                      ? '${overBudget.length} mục vượt'
                      : 'Trong hạn mức',
                  tone: hasOver ? StatusTone.danger : StatusTone.safe,
                  dense: true,
                ),
              ],
            ),
            for (final item in overBudget.take(_maxWarnings)) ...[
              const SizedBox(height: AppSpacing.md),
              _OverBudgetRow(item: item),
            ],
            if (hiddenCount > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'và $hiddenCount mục khác vượt hạn mức',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ] else
            Text(
              'Đặt hạn mức cho từng danh mục để được cảnh báo khi chi vượt. '
              'Danh mục chưa đặt hạn mức là không giới hạn.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _OverBudgetRow extends StatelessWidget {
  const _OverBudgetRow({required this.item});

  final CategoryBudgetStatus item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final over = theme.extension<AppFinanceColors>()!.budgetOver;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: over.container,
        shape: AppShapes.control,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: AppIconSizes.md,
              color: over.onContainer,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.categoryName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: over.onContainer,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${MoneyFormatter.format(item.spentMinor)} / '
                    '${MoneyFormatter.format(item.limitMinor)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Vượt ${MoneyFormatter.format(item.overMinor)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: over.onContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.snapshot, required this.month});

  final DashboardSnapshot snapshot;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final dailyTotals = List<int>.generate(
      days,
      (index) => snapshot.dailyTotals[index + 1] ?? 0,
      growable: false,
    );
    final hasData = dailyTotals.any((amount) => amount > 0);
    if (!hasData) {
      return Semantics(
        label:
            'Biểu đồ đường chi tiêu theo ngày, chưa có dữ liệu trong tháng ${MonthUtils.label(month)}.',
        child: const AppCard(
          child: AppEmptyState(
            icon: Icons.show_chart,
            title: 'Chưa có dữ liệu chi tiêu',
            message:
                'Các khoản chi sẽ xuất hiện tại đây khi bạn thêm giao dịch.',
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxY = dailyTotals
        .fold<int>(0, (highest, amount) => amount > highest ? amount : highest)
        .toDouble();
    final spots = List<FlSpot>.generate(
      days,
      (index) => FlSpot((index + 1).toDouble(), dailyTotals[index].toDouble()),
      growable: false,
    );
    final chartMaxY = maxY * 1.12;
    final horizontalInterval = maxY / 3;

    return Semantics(
      label:
          'Biểu đồ đường chi tiêu theo ngày trong tháng ${MonthUtils.label(month)}. '
          'Tổng chi ${MoneyFormatter.format(snapshot.totalMinor)}.',
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const _ChartLegendItem(label: 'Chi tiêu trong ngày'),
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) => AspectRatio(
                aspectRatio: constraints.maxWidth >= AppBreakpoints.compact
                    ? 2.2
                    : 16 / 10,
                child: LineChart(
                  LineChartData(
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: false,
                        color: scheme.primary,
                        barWidth: 3,
                        dotData: FlDotData(show: false),
                        belowBarData: BarAreaData(show: false),
                      ),
                    ],
                    minX: 1,
                    maxX: days.toDouble(),
                    minY: 0,
                    maxY: chartMaxY,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: horizontalInterval,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: scheme.outlineVariant.withValues(alpha: 0.36),
                        strokeWidth: 1,
                      ),
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
                          showTitles: maxY > 0,
                          reservedSize: 80,
                          interval: horizontalInterval,
                          getTitlesWidget: (value, meta) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              MoneyFormatter.compact(value.round()),
                              maxLines: 1,
                              softWrap: false,
                              style: theme.textTheme.bodySmall,
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 5,
                          reservedSize: 28,
                          getTitlesWidget: (value, meta) {
                            final day = value.round();
                            if (day < 1 || day > days) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                '$day',
                                style: theme.textTheme.bodySmall,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => scheme.inverseSurface,
                        getTooltipItems: (touchedSpots) => touchedSpots
                            .map((spot) {
                              final day = spot.x.round().toString().padLeft(
                                2,
                                '0',
                              );
                              final monthNumber = month.month
                                  .toString()
                                  .padLeft(2, '0');
                              return LineTooltipItem(
                                '$day/$monthNumber\n'
                                '${MoneyFormatter.format(spot.y.round())}',
                                TextStyle(color: scheme.onInverseSurface),
                              );
                            })
                            .toList(growable: false),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartLegendItem extends StatelessWidget {
  const _ChartLegendItem({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: SizedBox(
            width: 10,
            height: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _CategoryBreakdownSkeleton extends StatelessWidget {
  const _CategoryBreakdownSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppCard(
          child: Row(
            children: [
              const SkeletonBox(width: 128, height: 128, radius: 999),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  children: [
                    for (var index = 0; index < 4; index++)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                        child: Row(
                          children: [
                            SkeletonBox(width: 10, height: 10, radius: 999),
                            SizedBox(width: AppSpacing.sm),
                            Expanded(child: SkeletonBox(height: 12)),
                            SizedBox(width: AppSpacing.sm),
                            SkeletonBox(width: 40, height: 12),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        const SectionHeader(title: 'Chi tiêu theo danh mục'),
        const SizedBox(height: AppSpacing.md),
        const SkeletonListRows(count: 3),
      ],
    );
  }
}

class _CategoryBreakdown extends StatefulWidget {
  const _CategoryBreakdown({
    required this.snapshot,
    required this.categories,
    required this.month,
  });

  final DashboardSnapshot snapshot;
  final List<CategoryEntity> categories;
  final DateTime month;

  @override
  State<_CategoryBreakdown> createState() => _CategoryBreakdownState();
}

class _CategoryBreakdownState extends State<_CategoryBreakdown> {
  String? _selectedCategoryId;

  void _toggleCategory(String id) {
    setState(() {
      _selectedCategoryId = _selectedCategoryId == id ? null : id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries =
        widget.snapshot.categoryTotals.entries
            .where((entry) => entry.value > 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    final scheme = Theme.of(context).colorScheme;
    final categoriesById = {
      for (final category in widget.categories) category.id: category,
    };
    const maxPieSlices = 6;
    final visibleCount = entries.length > maxPieSlices
        ? maxPieSlices - 1
        : entries.length;
    final visibleEntries = entries.take(visibleCount).toList(growable: false);
    final remainingEntries = entries.skip(visibleCount).toList(growable: false);
    final slices = <({String id, String label, int amount, Color color})>[];
    for (final entry in visibleEntries) {
      final category = categoriesById[entry.key];
      slices.add((
        id: entry.key,
        label: category?.name ?? 'Khác',
        amount: entry.value,
        color: category == null
            ? scheme.primary
            : CategoryPalette.resolve(category.colorValue, scheme).glyph,
      ));
    }
    if (remainingEntries.isNotEmpty) {
      slices.add((
        id: '__other__',
        label: 'Còn lại (${remainingEntries.length} danh mục)',
        amount: remainingEntries.fold<int>(
          0,
          (sum, entry) => sum + entry.value,
        ),
        color: scheme.outline,
      ));
    }
    final chartSummary = slices
        .map(
          (slice) => '${slice.label}: ${MoneyFormatter.format(slice.amount)}',
        )
        .join(', ');

    String sharePercent(int amount) {
      final percent = (amount * 100 / total).round();
      return percent == 0 ? '<1%' : '$percent%';
    }

    final selectedEntry = _selectedCategoryId == null
        ? null
        : entries
              .where((entry) => entry.key == _selectedCategoryId)
              .firstOrNull;
    final selectedSlice = _selectedCategoryId == null
        ? null
        : slices.where((slice) => slice.id == _selectedCategoryId).firstOrNull;
    final selectedLabel = selectedEntry == null
        ? selectedSlice?.label
        : categoriesById[selectedEntry.key]?.name ?? 'Khác';
    final selectedAmount = selectedEntry?.value ?? selectedSlice?.amount;

    Widget legendEntry(
      ({String id, String label, int amount, Color color}) slice,
    ) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final labelRow = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: SizedBox.square(
                  dimension: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: slice.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * 0.64 - 42,
                ),
                child: Text(
                  slice.label,
                  key: ValueKey('composition-legend-label-${slice.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          );
          final amountText = FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              MoneyFormatter.format(slice.amount),
              key: ValueKey('composition-legend-amount-${slice.id}'),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          );
          final amount = ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.36),
            child: amountText,
          );

          return InkWell(
            key: ValueKey('composition-legend-${slice.id}'),
            onTap: () => _toggleCategory(slice.id),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  labelRow,
                  const Spacer(),
                  const SizedBox(width: AppSpacing.md),
                  amount,
                ],
              ),
            ),
          );
        },
      );
    }

    final compositionCard = entries.isEmpty
        ? const AppCard(
            semanticLabel: 'Chưa có dữ liệu cơ cấu chi tiêu trong tháng này.',
            child: SizedBox(
              height: 104,
              child: Center(child: Text('Chưa có dữ liệu cơ cấu chi tiêu.')),
            ),
          )
        : AppCard(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final useVerticalLayout = constraints.maxWidth < 480;
                final chartSize = useVerticalLayout
                    ? (constraints.maxWidth * 0.52)
                          .clamp(136.0, 184.0)
                          .toDouble()
                    : (constraints.maxWidth * 0.4)
                          .clamp(128.0, 184.0)
                          .toDouble();
                final chart = Semantics(
                  container: true,
                  label:
                      'Biểu đồ tròn cơ cấu chi tiêu. Tổng ${MoneyFormatter.format(total)}. $chartSummary.',
                  child: ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: chartSize,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          PieChart(
                            PieChartData(
                              sections: [
                                for (final slice in slices)
                                  PieChartSectionData(
                                    value: slice.amount.toDouble(),
                                    color: slice.color,
                                    radius:
                                        chartSize *
                                        (slice.id == _selectedCategoryId
                                            ? 0.28
                                            : 0.24),
                                    title: sharePercent(slice.amount),
                                    titleStyle: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color:
                                              slice.color.computeLuminance() >
                                                  0.18
                                              ? Colors.black
                                              : Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                    titlePositionPercentageOffset: 0.75,
                                  ),
                              ],
                              centerSpaceRadius: chartSize * 0.28,
                              sectionsSpace: 2,
                              startDegreeOffset: -90,
                            ),
                          ),
                          IgnorePointer(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  selectedLabel ?? 'TỔNG CHI',
                                  key: const ValueKey(
                                    'composition-center-label',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                SizedBox(
                                  width: chartSize * 0.7,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      MoneyFormatter.compact(
                                        selectedAmount ?? total,
                                      ),
                                      key: const ValueKey(
                                        'composition-center-amount',
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                ),
                                if (selectedAmount != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '${sharePercent(selectedAmount)} tổng chi',
                                    key: const ValueKey(
                                      'composition-center-share',
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
                final legend = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final slice in slices) legendEntry(slice)],
                );
                if (useVerticalLayout) {
                  return Column(
                    children: [
                      Center(child: chart),
                      const SizedBox(height: AppSpacing.lg),
                      legend,
                    ],
                  );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Center(child: chart)),
                      Expanded(child: legend),
                    ],
                  ),
                );
              },
            ),
          );

    final categoryList = entries.isEmpty
        ? const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Text('Chưa có khoản chi theo danh mục.'),
          )
        : ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final category = categoriesById[entry.key];
              return InkWell(
                key: ValueKey('composition-detail-${entry.key}'),
                onTap: () => _toggleCategory(entry.key),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      CategoryAvatar(category: category, radius: 18),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          category?.name ?? 'Khác',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      MoneyText(entry.value),
                    ],
                  ),
                ),
              );
            },
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        compositionCard,
        if (selectedEntry != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => context.push(
                Uri(
                  path: '/invoices',
                  queryParameters: {
                    'month': MonthUtils.key(widget.month),
                    'category': selectedEntry.key,
                  },
                ).toString(),
              ),
              icon: const Icon(Icons.arrow_forward),
              label: Text('Xem giao dịch ${selectedLabel ?? 'danh mục'}'),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        _CategoryDropdown(
          key: const ValueKey('expense-categories-dropdown'),
          title: 'Chi tiêu theo danh mục',
          child: categoryList,
        ),
      ],
    );
  }
}

class _IncomeBreakdown extends StatelessWidget {
  const _IncomeBreakdown({
    required this.entries,
    required this.categories,
    required this.onAddIncome,
  });

  final List<IncomeEntry> entries;
  final List<CategoryEntity> categories;
  final VoidCallback onAddIncome;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, int>{};
    for (final entry in entries) {
      grouped.update(
        entry.categoryId,
        (amount) => amount + entry.amountMinor,
        ifAbsent: () => entry.amountMinor,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final categoriesById = {
      for (final category in categories) category.id: category,
    };
    final slices = <({String id, String label, int amount, Color color})>[
      for (final entry in grouped.entries)
        (
          id: entry.key,
          label: categoriesById[entry.key]?.name ?? 'Chưa phân loại',
          amount: entry.value,
          color: categoriesById[entry.key] == null
              ? scheme.outline
              : CategoryPalette.resolve(
                  categoriesById[entry.key]!.colorValue,
                  scheme,
                ).glyph,
        ),
    ]..sort((left, right) => right.amount.compareTo(left.amount));

    if (slices.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: AppEmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Chưa có khoản thu trong tháng này',
              message: 'Thêm khoản thu để xem cơ cấu theo danh mục.',
              action: FilledButton.icon(
                onPressed: onAddIncome,
                icon: const Icon(Icons.add),
                label: const Text('Thêm khoản thu'),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _CategoryDropdown(
            key: const ValueKey('income-categories-dropdown'),
            title: 'Thu nhập theo danh mục',
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Text('Chưa có khoản thu theo danh mục.'),
            ),
          ),
        ],
      );
    }

    final total = slices.fold<int>(0, (sum, slice) => sum + slice.amount);
    String sharePercent(int amount) {
      final percent = (amount * 100 / total).round();
      return percent == 0 ? '<1%' : '$percent%';
    }

    final summary = slices
        .map(
          (slice) => '${slice.label}: ${MoneyFormatter.format(slice.amount)}',
        )
        .join(', ');
    final chart = LayoutBuilder(
      builder: (context, constraints) {
        final useVerticalLayout = constraints.maxWidth < 480;
        final chartSize = useVerticalLayout
            ? (constraints.maxWidth * 0.52).clamp(136.0, 184.0).toDouble()
            : (constraints.maxWidth * 0.4).clamp(128.0, 184.0).toDouble();
        final pie = Semantics(
          container: true,
          label:
              'Biểu đồ tròn cơ cấu thu. Tổng ${MoneyFormatter.format(total)}. $summary.',
          child: ExcludeSemantics(
            child: SizedBox.square(
              dimension: chartSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    key: const ValueKey('income-composition-chart'),
                    PieChartData(
                      sections: [
                        for (final slice in slices)
                          PieChartSectionData(
                            value: slice.amount.toDouble(),
                            color: slice.color,
                            radius: chartSize * 0.24,
                            title: sharePercent(slice.amount),
                            titleStyle: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: slice.color.computeLuminance() > 0.18
                                      ? Colors.black
                                      : Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                            titlePositionPercentageOffset: 0.75,
                          ),
                      ],
                      centerSpaceRadius: chartSize * 0.28,
                      sectionsSpace: 2,
                      startDegreeOffset: -90,
                    ),
                  ),
                  IgnorePointer(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'TỔNG THU',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: chartSize * 0.7,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              MoneyFormatter.compact(total),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final legend = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final slice in slices)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: SizedBox.square(
                        dimension: 10,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: slice.color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        slice.label,
                        key: ValueKey('income-composition-label-${slice.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        MoneyFormatter.format(slice.amount),
                        key: ValueKey('income-composition-amount-${slice.id}'),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );

        if (useVerticalLayout) {
          return Column(
            children: [
              Center(child: pie),
              const SizedBox(height: AppSpacing.lg),
              legend,
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 2, child: Center(child: pie)),
            Expanded(child: legend),
          ],
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(child: chart),
        const SizedBox(height: AppSpacing.xl),
        _CategoryDropdown(
          key: const ValueKey('income-categories-dropdown'),
          title: 'Thu nhập theo danh mục',
          child: Column(
            children: [
              for (var index = 0; index < slices.length; index++) ...[
                if (index > 0) const Divider(height: 1),
                ListTile(
                  leading: CategoryAvatar(
                    category: categoriesById[slices[index].id],
                    radius: 18,
                  ),
                  title: Text(slices[index].label),
                  trailing: MoneyText(slices[index].amount),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  const _CategoryDropdown({
    required this.title,
    required this.child,
    super.key,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    elevation: AppElevations.raised,
    shape: AppShapes.card,
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      title: Text(title, style: Theme.of(context).textTheme.titleLarge),
      children: [child],
    ),
  );
}
