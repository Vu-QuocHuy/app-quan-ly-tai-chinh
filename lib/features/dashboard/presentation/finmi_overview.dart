import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/shell/finmi_actions.dart';
import '../../../app/theme/finance_colors.dart';
import '../../../app/theme/finmi_theme.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/utils/month_utils.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_refresh.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/finmi_brand.dart';
import '../../../shared/widgets/finmi_page_header.dart';
import '../../../shared/widgets/month_picker_sheet.dart';
import '../../export/presentation/report_export_sheet.dart';
import '../../income/presentation/transaction_entry_sheet.dart';
import '../../ingestion/presentation/import_source_sheet.dart';
import '../../invoices/domain/invoice_filters.dart';
import '../../invoices/domain/invoice_models.dart';

final todayDashboardProvider = StreamProvider.autoDispose
    .family<DashboardSnapshot, String>(
      (ref, month) =>
          ref.watch(invoiceRepositoryProvider).watchDashboard(month),
    );

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profileSize =
        40.0 * (MediaQuery.textScalerOf(context).scale(12) / 12).clamp(1, 1.6);
    final user = ref.watch(authUserProvider).valueOrNull;
    final fullName =
        (user?.userMetadata?['display_name'] as String?)?.trim() ?? '';
    final words = fullName
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final initials = words.isEmpty
        ? null
        : '${words.length > 1 ? words[words.length - 2].characters.first : ''}${words.last.characters.first}'
              .toUpperCase();
    final snapshot = ref.watch(dashboardProvider);
    final incomes = ref.watch(incomesProvider);
    final month = ref.watch(selectedMonthProvider);
    final recent = ref.watch(
      filteredInvoiceSummariesProvider(
        const InvoiceListQuery(filter: InvoiceFilter(), limit: 5),
      ),
    );
    final pending = ref.watch(
      filteredInvoiceSummariesProvider(
        const InvoiceListQuery(
          filter: InvoiceFilter(status: InvoiceStatus.needsReview),
          limit: 1,
        ),
      ),
    );
    final now = DateTime.now();
    final today = ref.watch(todayDashboardProvider(MonthUtils.key(now)));
    final actions = FinmiActions.maybeOf(context);
    final incomeTotal = incomes.valueOrNull
        ?.where((e) => MonthUtils.key(e.receivedAt) == MonthUtils.key(month))
        .fold<int>(0, (sum, e) => sum + e.amountMinor);
    ref.listen(dashboardProvider, (_, next) {
      if (next.valueOrNull case final data?) {
        ref.read(budgetNotificationServiceProvider).notifyIfNeeded(data);
      }
    });
    void quickAdd() => showTransactionEntry(context);

    final utilities = <(IconData, String, VoidCallback?)>[
      (CupertinoIcons.money_dollar_circle, 'Thêm thu/chi', quickAdd),
      (CupertinoIcons.chart_bar, 'Thống kê', () => context.push('/statistics')),
      (
        CupertinoIcons.arrow_2_circlepath,
        'Thu chi định kỳ',
        () => context.push('/plans'),
      ),
      (CupertinoIcons.creditcard, 'Ngân sách', () => context.go('/budgets')),
      (CupertinoIcons.group, 'Nhóm', () => context.go('/groups')),
      (CupertinoIcons.camera, 'Quét', actions?.scanReceipt),
      (CupertinoIcons.tag, 'Danh mục', () => context.push('/categories')),
      (
        CupertinoIcons.doc_text,
        'Xuất báo cáo',
        () => showReportExportSheet(context),
      ),
    ];
    return Scaffold(
      body: AppRefreshIndicator(
        onRefresh: () => refreshFromCloud(context, ref),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 16, 4),
                child: Row(
                  children: [
                    const FinmiBrand(width: 112),
                    const Spacer(),
                    FinmiHeaderAction(
                      icon: CupertinoIcons.bell,
                      tooltip: 'Thông báo',
                      badge: pending.valueOrNull?.isNotEmpty ?? false,
                      onPressed: () => context.push('/invoices?review=1'),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: profileSize + 8,
                      height: profileSize + 8,
                      child: Center(
                        child: IconButton(
                          tooltip: 'Hồ sơ cá nhân',
                          onPressed: () => context.push('/settings/account'),
                          style: IconButton.styleFrom(
                            fixedSize: Size.square(profileSize),
                            minimumSize: Size.square(profileSize),
                            padding: EdgeInsets.zero,
                            side: BorderSide(
                              color: context.finmi.border,
                              width: 1.25,
                            ),
                            shape: const CircleBorder(),
                          ),
                          icon: initials == null
                              ? const Icon(CupertinoIcons.person, size: 18)
                              : Text(
                                  initials,
                                  style: theme.textTheme.bodySmall,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
              sliver: SliverList.list(
                children: [
                  _Greeting(
                    name: words.isEmpty ? 'bạn' : words.last,
                    month: month,
                    onMonth: () async {
                      final selected = await showMonthPickerSheet(
                        context,
                        selected: month,
                      );
                      if (selected != null) {
                        ref.read(selectedMonthProvider.notifier).state =
                            selected;
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  snapshot.when(
                    loading: () => const SkeletonHero(),
                    error: (e, st) => AppErrorState(
                      error: e,
                      stackTrace: st,
                      compact: true,
                      onRetry: () => ref.invalidate(dashboardProvider),
                    ),
                    data: (data) => _BalanceCard(
                      snapshot: data,
                      income: incomeTotal,
                      incomeError: incomes.hasError,
                      onRetry: () => ref.invalidate(incomesProvider),
                      onHistory: () => context.push(
                        '/invoices?month=${MonthUtils.key(month)}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  today.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, st) => AppErrorState(
                      error: e,
                      stackTrace: st,
                      compact: true,
                      onRetry: () => ref.invalidate(
                        todayDashboardProvider(MonthUtils.key(now)),
                      ),
                    ),
                    data: (data) => _TodayStrip(
                      snapshot: data,
                      today: now,
                      onTap: () => context.push(
                        '/invoices/day/${DateFormat('yyyy-MM-dd').format(now)}',
                      ),
                    ),
                  ),
                  if (snapshot.valueOrNull?.overBudgetCategories
                      case final over? when over.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _BudgetWarningCard(
                      overBudget: over,
                      onTap: () => context.go('/budgets'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FinmiSectionLabel(
                    'Tiện ích',
                    trailing: Text(
                      'Quản lý theo cách của bạn',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = context.needsStackedLayout ? 2 : 4;
                      final width =
                          (constraints.maxWidth - (columns - 1) * 8) / columns;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final item in utilities)
                            SizedBox(
                              width: width,
                              child: _Utility(
                                icon: item.$1,
                                label: item.$2,
                                onTap: item.$3,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  _ScanBanner(onTap: actions?.scanReceipt),
                  const SizedBox(height: 20),
                  FinmiSectionLabel(
                    'Giao dịch gần đây',
                    trailing: TextButton(
                      onPressed: () => context.push('/invoices'),
                      child: const Text('Lịch sử thu chi ›'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  recent.when(
                    loading: () => const SkeletonHero(),
                    error: (e, st) => AppErrorState(
                      error: e,
                      stackTrace: st,
                      compact: true,
                      onRetry: () =>
                          ref.invalidate(filteredInvoiceSummariesProvider),
                    ),
                    data: (entries) => entries.isEmpty
                        ? AppEmptyState(
                            icon: CupertinoIcons.doc_text,
                            title: 'Chưa có khoản chi nào',
                            message:
                                'Thêm khoản chi đầu tiên hoặc quét một hóa đơn.',
                            action: OutlinedButton.icon(
                              onPressed: actions == null
                                  ? null
                                  : () =>
                                        actions.openSource(ImportSource.manual),
                              icon: const Icon(Icons.add),
                              label: const Text('Thêm khoản chi'),
                            ),
                          )
                        : Column(
                            children: [
                              for (final invoice in entries)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _RecentTransaction(invoice: invoice),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.name,
    required this.month,
    required this.onMonth,
  });
  final String name;
  final DateTime month;
  final VoidCallback onMonth;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final greeting = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Chào $name,', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Theo dõi chi tiêu mỗi ngày',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    final date = OutlinedButton(
      onPressed: onMonth,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        side: BorderSide(color: context.finmi.border, width: 1.25),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        'Tháng ${month.month}, ${month.year}',
        style: theme.textTheme.bodySmall,
      ),
    );
    return context.needsStackedLayout
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [greeting, const SizedBox(height: 8), date],
          )
        : Row(
            children: [
              Expanded(child: greeting),
              const SizedBox(width: 8),
              date,
            ],
          );
  }
}

class _BalanceCard extends StatefulWidget {
  const _BalanceCard({
    required this.snapshot,
    required this.income,
    required this.incomeError,
    required this.onRetry,
    required this.onHistory,
  });
  final DashboardSnapshot snapshot;
  final int? income;
  final bool incomeError;
  final VoidCallback onRetry, onHistory;
  @override
  State<_BalanceCard> createState() => _BalanceCardState();
}

class _BalanceCardState extends State<_BalanceCard> {
  bool hidden = false;
  @override
  Widget build(BuildContext context) {
    final t = context.finmi;
    final theme = Theme.of(context);
    final darkHero = t.heroBackground.computeLuminance() < .25;
    final incomeColor = darkHero
        ? const Color(0xFFBDE6C5)
        : const Color(0xFF236447);
    final style = theme.textTheme.bodySmall?.copyWith(color: t.heroSecondary);
    final statStyle = theme.textTheme.bodySmall?.copyWith(
      color: t.heroText,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget metric(String label, int? value, bool isIncome) => InkWell(
      onTap: widget.onHistory,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${isIncome ? '↓' : '↑'}  $label', style: style),
            const SizedBox(height: 4),
            Text(
              hidden
                  ? '••••••'
                  : value == null
                  ? (widget.incomeError ? 'Không tải được' : 'Đang tải…')
                  : '${isIncome ? '+' : '-'} ${MoneyFormatter.format(value)}',
              style: statStyle?.copyWith(
                color: isIncome ? incomeColor : t.heroText,
              ),
            ),
          ],
        ),
      ),
    );
    final thu = metric('Thu nhập tháng này', widget.income, true);
    final chi = metric('Chi tiêu tháng này', widget.snapshot.totalMinor, false);
    return AppCard(
      color: t.heroBackground,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.heroRadius),
        side: BorderSide(color: t.heroBackground, width: 1.25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message:
                      'Thu nhập trừ chi tiêu đã ghi nhận trong tháng đang chọn',
                  child: Text(
                    'Tổng số dư',
                    style: style?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              IconButton(
                tooltip: hidden ? 'Hiện số tiền' : 'Ẩn số tiền',
                onPressed: () => setState(() => hidden = !hidden),
                style: IconButton.styleFrom(
                  foregroundColor: t.heroSecondary,
                  side: BorderSide(
                    color: t.heroSecondary.withValues(alpha: .5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: Icon(
                  hidden ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                  size: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.income == null)
            Text(
              widget.incomeError
                  ? 'Không tải được khoản thu'
                  : 'Đang tải số dư…',
              style: theme.textTheme.titleMedium?.copyWith(color: t.heroText),
            )
          else
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: hidden
                        ? '••••••'
                        : MoneyFormatter.format(
                                widget.income! - widget.snapshot.totalMinor,
                              )
                              .replaceAll(RegExp(r'\s*₫'), '')
                              .replaceAll('.', '.\u200B'),
                  ),
                  TextSpan(
                    text: ' ₫',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: t.heroSecondary,
                    ),
                  ),
                ],
              ),
              style: theme.textTheme.displayLarge?.copyWith(
                fontSize: 34,
                fontWeight: FontWeight.w600,
                color: t.heroText,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              semanticsLabel: hidden
                  ? 'Số dư đã ẩn'
                  : MoneyFormatter.format(
                      widget.income! - widget.snapshot.totalMinor,
                    ),
            ),
          if (widget.incomeError)
            TextButton(
              onPressed: widget.onRetry,
              style: TextButton.styleFrom(foregroundColor: t.heroText),
              child: const Text('Thử lại khoản thu'),
            ),
          const SizedBox(height: 16),
          Divider(indent: 0, color: t.heroSecondary.withValues(alpha: .4)),
          const SizedBox(height: 12),
          if (context.needsStackedLayout) ...[
            thu,
            const SizedBox(height: 8),
            chi,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: thu),
                const SizedBox(width: 8),
                Expanded(child: chi),
              ],
            ),
        ],
      ),
    );
  }
}

class _TodayStrip extends StatelessWidget {
  const _TodayStrip({
    required this.snapshot,
    required this.today,
    required this.onTap,
  });
  final DashboardSnapshot snapshot;
  final DateTime today;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = [
      for (var day = today.day - 6; day <= today.day; day++)
        snapshot.dailyTotals[day] ?? 0,
    ];
    final maximum = values.fold<int>(0, (a, b) => a > b ? a : b);
    final bars = ExcludeSemantics(
      child: SizedBox(
        height: 36,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < values.length; i++)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Container(
                  width: 5,
                  height: maximum == 0 ? 3 : 3 + 29 * values[i] / maximum,
                  decoration: BoxDecoration(
                    color: i == 6
                        ? theme.colorScheme.primary
                        : context.finmi.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    final description = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(CupertinoIcons.clock, size: 14),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                'Chi tiêu hôm nay',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Đã chi ${MoneyFormatter.format(snapshot.dailyTotals[today.day] ?? 0)} · Chạm để xem',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    return AppCard(
      onTap: onTap,
      color: theme.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.all(13),
      child: context.needsStackedLayout
          ? description
          : Row(
              children: [
                Expanded(child: description),
                const SizedBox(width: 8),
                bars,
              ],
            ),
    );
  }
}

class _Utility extends StatelessWidget {
  const _Utility({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(1, 12, 1, 9),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 77),
        child: Column(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: theme.colorScheme.onPrimary, size: 20),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cảnh báo theo từng danh mục: top 3 danh mục vượt hạn mức nhiều nhất.
/// Danh mục chưa đặt hạn mức là không giới hạn nên không có cảnh báo tổng.
class _BudgetWarningCard extends StatelessWidget {
  const _BudgetWarningCard({required this.overBudget, required this.onTap});

  static const _maxWarnings = 3;

  final List<CategoryBudgetStatus> overBudget;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final over = context.finance.budgetOver;
    final hiddenCount = overBudget.length - _maxWarnings;
    return AppCard(
      key: const ValueKey('budget-warning-card'),
      onTap: onTap,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 20, color: over.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${overBudget.length} danh mục vượt hạn mức',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: over.color,
                  ),
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          for (final item in overBudget.take(_maxWarnings)) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.categoryName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${MoneyFormatter.format(item.spentMinor)} / '
                        '${MoneyFormatter.format(item.limitMinor)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Vượt ${MoneyFormatter.format(item.overMinor)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: over.color,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
          if (hiddenCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              'và $hiddenCount mục khác vượt hạn mức',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScanBanner extends StatelessWidget {
  const _ScanBanner({this.onTap});
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const ValueKey('finmi-banner'),
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Semantics(
          label:
              'Theo dõi chi tiêu mỗi ngày. Quét hóa đơn, ghi lại khoản chi. Chạm để quét hóa đơn.',
          image: true,
          child: Image.asset(
            'assets/branding/finmi/banner.png',
            width: double.infinity,
            fit: BoxFit.fitWidth,
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
  }
}

class _RecentTransaction extends StatelessWidget {
  const _RecentTransaction({required this.invoice});
  final InvoiceEntity invoice;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          invoice.sellerName,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          DateFormat(
            'dd/MM/yyyy',
          ).format(invoice.issuedAt ?? invoice.createdAt),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    final figures = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '- ${MoneyFormatter.format(invoice.totalMinor, currencyCode: invoice.currencyCode)}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          invoice.status == InvoiceStatus.confirmed
              ? 'Khoản chi đã lưu'
              : 'Cần kiểm tra',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    return AppCard(
      onTap: () => context.push('/invoices/${invoice.id}'),
      padding: const EdgeInsets.all(13),
      child: context.needsStackedLayout
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [details, const SizedBox(height: 8), figures],
            )
          : Row(
              children: [
                Expanded(child: details),
                const SizedBox(width: 10),
                Flexible(child: figures),
              ],
            ),
    );
  }
}
