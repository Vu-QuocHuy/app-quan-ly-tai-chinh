import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/utils/month_utils.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/theme/finance_colors.dart';
import '../../../shared/widgets/app_callout.dart';
import '../../../shared/widgets/category_avatar.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/budget_meter.dart';
import '../../../shared/widgets/eyebrow_label.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/month_selector.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../../shared/errors/error_presenter.dart';
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

  Future<void> _dismissAnomaly(String invoiceId) async {
    await ref.read(anomalyFeedbackStoreProvider).dismiss(invoiceId);
    ref.invalidate(dismissedAnomalyIdsProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã ẩn cảnh báo này khỏi các lần phân tích sau.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(dashboardProvider);
    final insights = ref.watch(spendingInsightsProvider);
    final budgetAlertsEnabled =
        ref.watch(budgetAlertsEnabledProvider).value ?? true;
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final dismissedAnomalyIds =
        ref.watch(dismissedAnomalyIdsProvider).value ?? const <String>{};
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
              const SizedBox(width: 8),
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
              // Skeleton khớp hình học thật thay cho spinner giữa màn hình:
              // bố cục không nhảy khi dữ liệu về.
              loading: () => const SliverToBoxAdapter(
                child: Column(
                  children: [
                    SkeletonHero(),
                    SizedBox(height: 16),
                    SkeletonListRows(count: 2),
                    SizedBox(height: 24),
                    SkeletonChart(),
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
                  const SizedBox(height: 16),
                  _BudgetCard(
                    snapshot: snapshot,
                    alertsEnabled: budgetAlertsEnabled,
                    month: selectedMonth,
                    onViewBudgets: () => context.go('/budgets'),
                  ),
                  const SizedBox(height: 16),
                  _InsightsCard(
                    insights: insights,
                    dismissedAnomalyIds: dismissedAnomalyIds,
                    onDismissAnomaly: _dismissAnomaly,
                  ),
                  const SizedBox(height: 24),
                  const SectionHeader(title: 'Chi tiêu theo ngày'),
                  const SizedBox(height: 12),
                  _DailyChart(snapshot: snapshot, month: selectedMonth),
                  const SizedBox(height: 24),
                  const SectionHeader(title: 'Theo danh mục'),
                  const SizedBox(height: 12),
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

class _InsightsCard extends StatelessWidget {
  const _InsightsCard({
    required this.insights,
    required this.dismissedAnomalyIds,
    required this.onDismissAnomaly,
  });

  final AsyncValue<SpendingInsights> insights;
  final Set<String> dismissedAnomalyIds;
  final Future<void> Function(String invoiceId) onDismissAnomaly;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: EdgeInsets.zero,
        child: insights.when(
          loading: () => const Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Đang phân tích xu hướng…'),
            ],
          ),
          error: (error, _) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.insights_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Chưa thể tạo dự báo: ${friendlyMessage(error)}'),
              ),
            ],
          ),
          data: (data) {
            final recurring = data.recurringExpenses.take(3).toList();
            final anomalies = data.anomalies
                .where((item) => !dismissedAnomalyIds.contains(item.invoiceId))
                .take(3)
                .toList();
            return Semantics(
              container: true,
              label:
                  'Dự báo tổng chi ${MoneyFormatter.format(data.forecastTotalMinor)}, '
                  '${recurring.length} khoản định kỳ, ${anomalies.length} cảnh báo bất thường',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_graph_outlined,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Dự báo và chi định kỳ',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    MoneyFormatter.format(data.forecastTotalMinor),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    'Tổng chi dự kiến cuối tháng theo tốc độ hiện tại',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (recurring.isNotEmpty) ...[
                    const Divider(height: 28),
                    ...recurring.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.repeat, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.merchant,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${item.cadenceLabel} · ${item.occurrences} lần',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            Text(MoneyFormatter.format(item.averageMinor)),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (anomalies.isNotEmpty) ...[
                    const Divider(height: 28),
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Cảnh báo chi tiêu bất thường',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...anomalies.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              item.severity == SpendingAnomalySeverity.high
                                  ? Icons.error_outline
                                  : Icons.info_outline,
                              size: 20,
                              color:
                                  item.severity == SpendingAnomalySeverity.high
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.tertiary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.merchant),
                                  Text(
                                    '${item.explanation} · ${MoneyFormatter.format(item.amountMinor)}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  TextButton.icon(
                                    onPressed: () =>
                                        onDismissAnomaly(item.invoiceId),
                                    icon: const Icon(
                                      Icons.visibility_off_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('Báo nhầm, ẩn cảnh báo'),
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 32),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
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
              const SizedBox(height: AppSpacing.lg),
              Divider(color: scheme.onPrimary.withValues(alpha: 0.22)),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: AppIconSizes.sm,
                    color: scheme.onPrimary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Tổng quan đã cập nhật',
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: scheme.onPrimary),
                  ),
                ],
              ),
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
    required this.alertsEnabled,
    required this.month,
    required this.onViewBudgets,
  });

  final DashboardSnapshot snapshot;
  final bool alertsEnabled;
  final DateTime month;
  final VoidCallback onViewBudgets;

  @override
  Widget build(BuildContext context) {
    final hasBudget = snapshot.budgetLimitMinor > 0;
    final scheme = Theme.of(context).colorScheme;
    // Vạch nhịp "hôm nay": chỉ có nghĩa khi đang xem tháng hiện tại.
    final now = DateTime.now();
    final isCurrentMonth = now.year == month.year && now.month == month.month;
    final paceRatio = isCurrentMonth
        ? now.day / DateUtils.getDaysInMonth(month.year, month.month)
        : null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Ngân sách',
            subtitle: hasBudget
                ? 'Theo dõi nhịp chi trong ${MonthUtils.label(month)}'
                : 'Đặt hạn mức để kiểm soát tháng này',
            trailing: TextButton(
              onPressed: onViewBudgets,
              child: const Text('Xem'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (hasBudget)
            // BudgetMeter lo cả ba tầng (an toàn / sắp chạm 80% / đã vượt),
            // đuôi tràn và vạch nhịp. Trước đây `clamp(0, 1)` làm 110% và 400%
            // trông y hệt nhau, và tầng 80% mà BudgetAlertPolicy dùng để bắn
            // thông báo thì không màn hình nào render.
            BudgetMeter(
              spentMinor: snapshot.totalMinor,
              limitMinor: snapshot.budgetLimitMinor,
              paceRatio: paceRatio,
            )
          else
            Text(
              'Chưa thiết lập ngân sách tháng này.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          if (alertsEnabled && hasBudget && snapshot.budgetProgress >= 0.8) ...[
            const SizedBox(height: AppSpacing.lg),
            AppCallout(
              liveRegion: true,
              tone: snapshot.budgetProgress > 1
                  ? CalloutTone.danger
                  : CalloutTone.warning,
              message: snapshot.budgetProgress > 1
                  ? 'Bạn đã vượt ngân sách tháng này.'
                  : 'Bạn đã dùng ${(snapshot.budgetProgress * 100).round()}% ngân sách tháng này.',
            ),
          ],
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
    if (snapshot.dailyTotals.isEmpty) {
      return const AppCard(
        child: AppEmptyState(
          icon: Icons.show_chart,
          title: 'Chưa có dữ liệu chi tiêu',
          message: 'Biểu đồ sẽ xuất hiện sau khi bạn xác nhận hóa đơn.',
        ),
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = DateUtils.getDaysInMonth(month.year, month.month);

    // LÀM DÀY chuỗi dữ liệu: một điểm cho MỌI ngày trong tháng, 0 cho ngày
    // không chi. Trước đây biểu đồ chỉ vẽ những ngày CÓ hóa đơn và âm thầm bỏ
    // tất cả trừ 12 điểm cuối, nên trục hoành không tương ứng với thời gian.
    var running = 0;
    final spots = <FlSpot>[];
    for (var day = 1; day <= days; day++) {
      running += snapshot.dailyTotals[day] ?? 0;
      spots.add(FlSpot(day.toDouble(), running.toDouble()));
    }

    // Nhịp của tháng trước, vẽ tuyến tính. Phân biệt bằng KIỂU NÉT (đứt) chứ
    // không bằng màu, nên an toàn với người mù màu ngay từ cấu trúc.
    final previous = snapshot.previousMonthTotalMinor;
    final paceSpots = previous > 0
        ? [FlSpot(1, 0), FlSpot(days.toDouble(), previous.toDouble())]
        : const <FlSpot>[];

    final maxY = math.max(running, previous).toDouble();

    return Semantics(
      label:
          'Biểu đồ chi tiêu cộng dồn theo ngày. '
          'Tổng cuối kỳ ${MoneyFormatter.format(running)}.'
          '${previous > 0 ? ' Tháng trước ${MoneyFormatter.format(previous)}.' : ''}',
      child: AppCard(
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: LineChart(
            LineChartData(
              minX: 1,
              maxX: days.toDouble(),
              minY: 0,
              maxY: maxY <= 0 ? 1 : maxY * 1.12,
              // Trước đây mọi tham chiếu định lượng đều bị tắt: không lưới,
              // không nhãn trục tung. Biểu đồ chỉ còn là trang trí.
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY <= 0 ? 1 : maxY / 3,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
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
                    showTitles: true,
                    reservedSize: 56,
                    interval: maxY <= 0 ? 1 : maxY / 3,
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
                    // Mặc định 22dp không đủ cho bodySmall ở textScale lớn.
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) {
                      final day = value.round();
                      if (day < 1 || day > days) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('$day', style: theme.textTheme.bodySmall),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => scheme.inverseSurface,
                  getTooltipItems: (touched) => touched
                      .map((spot) {
                        final day = spot.x.round();
                        final label = spot.barIndex == 0
                            ? 'Cộng dồn tới ${day.toString().padLeft(2, '0')}/'
                                  '${month.month.toString().padLeft(2, '0')}'
                            : 'Nhịp tháng trước';
                        return LineTooltipItem(
                          '$label\n${MoneyFormatter.format(spot.y.round())}',
                          TextStyle(color: scheme.onInverseSurface),
                        );
                      })
                      .toList(growable: false),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: false,
                  color: scheme.primary,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: scheme.primary.withValues(alpha: 0.06),
                  ),
                ),
                if (paceSpots.isNotEmpty)
                  LineChartBarData(
                    spots: paceSpots,
                    isCurved: false,
                    color: scheme.outline,
                    barWidth: 1.5,
                    dashArray: const [3, 4],
                    dotData: const FlDotData(show: false),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.snapshot, required this.categories});

  final DashboardSnapshot snapshot;
  final List<CategoryEntity> categories;

  @override
  Widget build(BuildContext context) {
    if (snapshot.categoryTotals.isEmpty) {
      return const AppCard(
        child: AppEmptyState(
          icon: Icons.category_outlined,
          title: 'Chưa có danh mục nào',
          message: 'Chưa có dữ liệu danh mục trong tháng này.',
        ),
      );
    }
    final entries = snapshot.categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: entries.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final entry = entries[index];
          final category = categories
              .where((item) => item.id == entry.key)
              .firstOrNull;
          final ratio = total <= 0 ? 0.0 : entry.value / total;
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 6,
                          color: Theme.of(context).colorScheme.primary,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppSpacing.sm),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '${(ratio * 100).round()}%',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
