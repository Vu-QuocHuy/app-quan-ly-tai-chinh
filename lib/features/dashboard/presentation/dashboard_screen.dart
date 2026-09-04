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
import '../../../shared/widgets/budget_meter.dart';
import '../../../shared/widgets/eyebrow_label.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/month_selector.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../../shared/errors/error_presenter.dart';

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
          SliverAppBar.medium(
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
              loading: () => const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
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
                  ),
                  const SizedBox(height: 16),
                  _InsightsCard(
                    insights: insights,
                    dismissedAnomalyIds: dismissedAnomalyIds,
                    onDismissAnomaly: _dismissAnomaly,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Chi tiêu theo ngày',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _DailyChart(snapshot: snapshot),
                  const SizedBox(height: 24),
                  Text(
                    'Theo danh mục',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
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
          // Gradient bị GIỚI HẠN trong MỘT họ vai. Trước đây nó chạy tới
          // `primaryContainer` (#DBE0FF) trong khi chữ vẫn là `onPrimary`
          // trắng -> góc dưới phải chỉ còn 1.31:1, không đọc được.
          // Nay: trắng trên #1E40AF = 8.72:1, trên #2A50CC = 6.74:1.
          gradient: LinearGradient(
            colors: [scheme.primary, scheme.onPrimaryFixedVariant],
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
              // CÂU THƯỜNG. Bỏ .toUpperCase() + letterSpacing: 1 — viết hoa đẩy
              // dấu chồng tiếng Việt vào vùng ascender và rộng hơn ~30%.
              EyebrowLabel(
                'Tổng chi ${MonthUtils.label(month)}',
                color: scheme.onPrimary,
              ),
              const SizedBox(height: AppSpacing.sm),
              // fitToWidth: "1.234.567.890 ₫" ở 36sp trong ~280dp trước đây
              // xuống dòng chỉ còn ký hiệu ₫.
              MoneyText(
                snapshot.totalMinor,
                emphasis: MoneyEmphasis.display,
                fitToWidth: true,
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
    required this.alertsEnabled,
    required this.month,
  });

  final DashboardSnapshot snapshot;
  final bool alertsEnabled;
  final DateTime month;

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
          Row(
            children: [
              Icon(Icons.savings_outlined, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Ngân sách',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
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
  const _DailyChart({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (snapshot.dailyTotals.isEmpty) {
      return const AppCard(
        child: AppEmptyState(
          icon: Icons.bar_chart,
          title: 'Chưa có dữ liệu chi tiêu',
          message: 'Biểu đồ sẽ xuất hiện sau khi bạn xác nhận hóa đơn.',
        ),
      );
    }
    final entries = snapshot.dailyTotals.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final visible = entries.length > 12
        ? entries.sublist(entries.length - 12)
        : entries;
    final maxValue = visible.fold<int>(
      0,
      (max, item) => math.max(max, item.value),
    );
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label:
          'Biểu đồ cột chi tiêu theo ngày. Có ${visible.length} ngày có chi tiêu.',
      child: Card(
        child: SizedBox(
          height: 240,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 24, 20, 12),
            child: BarChart(
              BarChartData(
                maxY: maxValue == 0 ? 1 : maxValue * 1.2,
                alignment: BarChartAlignment.spaceAround,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(enabled: true),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) => Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('${visible[value.toInt()].key}'),
                      ),
                    ),
                  ),
                ),
                barGroups: [
                  for (var index = 0; index < visible.length; index++)
                    BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: visible[index].value.toDouble(),
                          width: 14,
                          color: scheme.primary,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
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
    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(8),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final entry = entries[index];
          final category = categories
              .where((item) => item.id == entry.key)
              .firstOrNull;
          return ListTile(
            // CategoryAvatar suy dẫn màu theo brightness và bảo đảm glyph
            // >= 4.5:1 trên cả nền thẻ lẫn tint. Bản tint 14% + glyph nguyên
            // màu trước đây chỉ đạt 2.32:1 và mù theme.
            leading: CategoryAvatar(category: category),
            title: Text(category?.name ?? 'Khác'),
            trailing: MoneyText(entry.value),
          );
        },
      ),
    );
  }
}
