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
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/budget_meter.dart';
import '../../../shared/widgets/eyebrow_label.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/month_selector.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../../shared/widgets/section_header.dart';

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
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final selectedMonth = ref.watch(selectedMonthProvider);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: const Text('Tổng quan'),
            actions: [
              IconButton(
                tooltip: 'Xem hóa đơn',
                onPressed: () => context.go('/invoices'),
                icon: const Icon(Icons.receipt_long_outlined),
              ),
              IconButton(
                tooltip: 'Mở trợ lý chi tiêu',
                onPressed: () => context.push('/chat'),
                icon: const Icon(Icons.chat_bubble_outline),
              ),
            ],
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
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
                    SizedBox(height: AppSpacing.lg),
                    SkeletonListRows(count: 1),
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
                  _HeroSummary(snapshot: snapshot, month: selectedMonth),
                  const SizedBox(height: AppSpacing.lg),
                  _BudgetCard(
                    snapshot: snapshot,
                    month: selectedMonth,
                    onViewBudgets: () => context.go('/budgets'),
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
                  ),
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
  const _HeroSummary({required this.snapshot, required this.month});

  final DashboardSnapshot snapshot;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label:
          'Tổng chi ${MonthUtils.label(month)} ${MoneyFormatter.format(snapshot.totalMinor)}, ${snapshot.invoiceCount} hóa đơn',
      child: DecoratedBox(
        decoration: ShapeDecoration(
          // Gradient bị GIỚI HẠN trong MỘT họ vai VÀ theo brightness — xem
          // `ColorScheme.heroGradientEnd`. Bản đầu chạy tới `primaryContainer`
          // (1.31:1 ở theme sáng); bản sửa dùng vai *Fixed bất biến nên lại
          // hỏng ở theme tối (2.31:1). Nay cả hai đều >= 6.74:1.
          gradient: LinearGradient(
            colors: [scheme.primary, scheme.heroGradientEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          // Hình khối biểu cảm DUY NHẤT của app.
          shape: AppShapes.hero,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: EyebrowLabel(
                      'Tổng chi ${MonthUtils.label(month)}',
                      color: scheme.onPrimary,
                    ),
                  ),
                  ExcludeSemantics(
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: scheme.onPrimary.withValues(alpha: 0.14),
                        shape: AppShapes.control,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.sm),
                        child: Icon(
                          Icons.account_balance_wallet_outlined,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // fitToWidth: "1.234.567.890 ₫" ở 36sp trong ~280dp trước đây
              // xuống dòng chỉ còn ký hiệu ₫.
              MoneyText(
                snapshot.totalMinor,
                emphasis: MoneyEmphasis.display,
                fitToWidth: true,
                animate: true,
                tone: FinanceTone(
                  color: scheme.onPrimary,
                  onColor: scheme.primary,
                  container: scheme.primaryContainer,
                  onContainer: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '${snapshot.invoiceCount} hóa đơn đã xác nhận',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: scheme.onPrimary),
              ),
              if (snapshot.monthOverMonthChange case final change?) ...[
                const SizedBox(height: AppSpacing.md),
                StatusPill(
                  icon: change >= 0 ? Icons.trending_up : Icons.trending_down,
                  label:
                      '${change >= 0 ? 'Tăng' : 'Giảm'} ${(change.abs() * 100).round()}% so với tháng trước',
                  tone: change >= 0 ? StatusTone.warn : StatusTone.safe,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.snapshot,
    required this.month,
    required this.onViewBudgets,
  });

  final DashboardSnapshot snapshot;
  final DateTime month;
  final VoidCallback onViewBudgets;

  @override
  Widget build(BuildContext context) {
    final hasBudget = snapshot.budgetLimitMinor > 0;
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Ngân sách',
            subtitle: hasBudget
                ? 'Mức sử dụng ngân sách ${MonthUtils.label(month)}'
                : 'Chưa có hạn mức cho tháng này',
            trailing: TextButton(
              onPressed: onViewBudgets,
              child: Text(hasBudget ? 'Quản lý' : 'Thiết lập'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (hasBudget) ...[
            BudgetMeter(
              spentMinor: snapshot.totalMinor,
              limitMinor: snapshot.budgetLimitMinor,
              colorTransition: true,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              snapshot.budgetLimitMinor >= snapshot.totalMinor
                  ? 'Còn lại ${MoneyFormatter.format(snapshot.budgetLimitMinor - snapshot.totalMinor)}'
                  : 'Vượt ${MoneyFormatter.format(snapshot.totalMinor - snapshot.budgetLimitMinor)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: snapshot.budgetLimitMinor < snapshot.totalMinor
                    ? scheme.error
                    : scheme.onSurfaceVariant,
              ),
            ),
          ] else
            Text(
              'Thiết lập hạn mức theo danh mục để theo dõi số đã chi và số còn lại.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final dailyTotals = List<int>.generate(
      days,
      (index) => snapshot.dailyTotals[index + 1] ?? 0,
      growable: false,
    );
    final hasData = dailyTotals.any((amount) => amount > 0);
    final maxY = dailyTotals
        .fold<int>(0, (highest, amount) => amount > highest ? amount : highest)
        .toDouble();
    final spots = List<FlSpot>.generate(
      days,
      (index) => FlSpot((index + 1).toDouble(), dailyTotals[index].toDouble()),
      growable: false,
    );
    // Giữ vùng vẽ và lưới tham chiếu nhẹ khi tháng chưa có khoản chi.
    final chartMaxY = maxY <= 0 ? 1.0 : maxY * 1.12;
    final horizontalInterval = maxY <= 0 ? 0.25 : maxY / 3;

    return Semantics(
      label: hasData
          ? 'Biểu đồ đường chi tiêu theo ngày trong tháng ${MonthUtils.label(month)}. '
                'Tổng chi ${MoneyFormatter.format(snapshot.totalMinor)}.'
          : 'Biểu đồ đường chi tiêu theo ngày, chưa có dữ liệu trong tháng ${MonthUtils.label(month)}.',
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasData) ...[
              const _ChartLegendItem(label: 'Chi tiêu trong ngày'),
              const SizedBox(height: AppSpacing.md),
            ],
            AspectRatio(
              aspectRatio: 16 / 10,
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
                      color: scheme.outlineVariant.withValues(
                        alpha: hasData ? 0.36 : 0.44,
                      ),
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
                        reservedSize: 56,
                        interval: horizontalInterval,
                        getTitlesWidget: (value, meta) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            MoneyFormatter.compact(value.round()),
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
                            final monthNumber = month.month.toString().padLeft(
                              2,
                              '0',
                            );
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

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.snapshot, required this.categories});

  final DashboardSnapshot snapshot;
  final List<CategoryEntity> categories;

  @override
  Widget build(BuildContext context) {
    final entries =
        snapshot.categoryTotals.entries
            .where((entry) => entry.value > 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    final scheme = Theme.of(context).colorScheme;
    final categoriesById = {
      for (final category in categories) category.id: category,
    };
    const maxPieSlices = 6;
    final visibleCount = entries.length > maxPieSlices
        ? maxPieSlices - 1
        : entries.length;
    final visibleEntries = entries.take(visibleCount).toList(growable: false);
    final remainingEntries = entries.skip(visibleCount).toList(growable: false);
    final slices = <({String label, int amount, Color color})>[];
    for (final entry in visibleEntries) {
      final category = categoriesById[entry.key];
      slices.add((
        label: category?.name ?? 'Khác',
        amount: entry.value,
        color: category == null
            ? scheme.primary
            : CategoryPalette.resolve(category.colorValue, scheme).glyph,
      ));
    }
    if (remainingEntries.isNotEmpty) {
      slices.add((
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

    Widget legendEntry(({String label, int amount, Color color}) slice) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final stackAmount = constraints.maxWidth < 220;
          final labelRow = Row(
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          );
          final amount = FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              MoneyFormatter.format(slice.amount),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          );

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: stackAmount
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      labelRow,
                      Padding(
                        padding: const EdgeInsets.only(
                          left: AppSpacing.xl,
                          top: AppSpacing.xs,
                        ),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: amount,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: labelRow),
                      const SizedBox(width: AppSpacing.sm),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth * 0.46,
                        ),
                        child: amount,
                      ),
                    ],
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
                    ? (constraints.maxWidth * 0.62)
                          .clamp(136.0, 220.0)
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
                                    radius: chartSize * 0.41,
                                    title: '',
                                  ),
                              ],
                              centerSpaceRadius: chartSize * 0.24,
                              sectionsSpace: 2,
                              startDegreeOffset: -90,
                            ),
                          ),
                          IgnorePointer(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'TỔNG CHI',
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
                                      MoneyFormatter.compact(total),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final slice in slices) legendEntry(slice)],
                );

                if (useVerticalLayout) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: chartSize + AppSpacing.xl,
                        child: Center(child: chart),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      legend,
                    ],
                  );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                  child: Row(
                    children: [
                      Expanded(child: Center(child: chart)),
                      Expanded(
                        child: Center(
                          child: FractionallySizedBox(
                            widthFactor: 0.9,
                            child: legend,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );

    final categoryList = entries.isEmpty
        ? const AppCard(
            child: SizedBox(
              height: 80,
              child: Center(child: Text('Chưa có khoản chi theo danh mục.')),
            ),
          )
        : AppCard(
            padding: EdgeInsets.zero,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final category = categoriesById[entry.key];
                return Padding(
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
                );
              },
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        compositionCard,
        const SizedBox(height: AppSpacing.xl),
        const SectionHeader(title: 'Chi tiêu theo danh mục'),
        const SizedBox(height: AppSpacing.md),
        categoryList,
      ],
    );
  }
}
