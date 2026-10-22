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
import '../../../shared/widgets/finmi_assistant_button.dart';
import '../../../shared/widgets/month_picker_sheet.dart';
import '../../../core/localization/app_strings.dart';
import '../../debts/data/debt_repository.dart';
import '../../debts/data/debt_notification_store.dart';
import '../../debts/domain/debt_models.dart';
import '../../debts/domain/debt_notification.dart';
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
    final tr = context.tr;
    final currentLocale = ref.watch(appLocaleProvider);
    final isEn = currentLocale.languageCode == 'en';
    final debtNotifs = ref.watch(debtNotificationsProvider).valueOrNull ?? [];
    final hasUnreadDebts = debtNotifs.any((n) => !n.isRead);

    ref.listen(dashboardProvider, (_, next) {
      if (next.valueOrNull case final data?) {
        ref.read(budgetNotificationServiceProvider).notifyIfNeeded(data);
      }
    });
    void quickAdd() => showTransactionEntry(context);

    final utilities = <(IconData, String, VoidCallback?)>[
      (CupertinoIcons.money_dollar_circle, tr.utilAdd, quickAdd),
      (CupertinoIcons.chart_bar, tr.utilStats, () => context.push('/statistics')),
      (
        CupertinoIcons.arrow_2_circlepath,
        tr.utilPlans,
        () => context.push('/plans'),
      ),
      (CupertinoIcons.creditcard, tr.utilBudgets, () => context.go('/budgets')),
      (CupertinoIcons.group, tr.utilGroups, () => context.go('/groups')),
      (
        CupertinoIcons.arrow_right_arrow_left_circle,
        tr.utilDebts,
        () => context.push('/debts'),
      ),
      (CupertinoIcons.tag, tr.utilCategories, () => context.push('/categories')),
      (
        CupertinoIcons.doc_text,
        tr.utilReports,
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
                    InkWell(
                      onTap: () => ref.read(appLocaleProvider.notifier).toggle(),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          border: Border.all(color: context.finmi.border, width: 1.25),
                          borderRadius: BorderRadius.circular(16),
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.language, size: 14, color: theme.colorScheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              isEn ? 'EN' : 'VI',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    FinmiHeaderAction(
                      icon: CupertinoIcons.bell,
                      tooltip: tr.notifications,
                      badge: (pending.valueOrNull?.isNotEmpty ?? false) || hasUnreadDebts,
                      onPressed: () => context.push('/invoices?tab=debts'),
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
                      debtSummary: ref.watch(debtSummaryProvider),
                      onRetry: () => ref.invalidate(incomesProvider),
                      onHistory: () => context.push(
                        '/invoices?month=${MonthUtils.key(month)}',
                      ),
                      onDebts: () => context.push('/debts'),
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
                    tr.utilities,
                    trailing: Text(
                      tr.manageYourWay,
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
                    tr.recentTransactions,
                    trailing: TextButton(
                      onPressed: () => context.push('/invoices'),
                      child: Text('${tr.history} ›'),
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
                            title: tr.noTransactionsYet,
                            message: tr.addFirstTransaction,
                            action: OutlinedButton.icon(
                              onPressed: actions == null
                                  ? null
                                  : () =>
                                        actions.openSource(ImportSource.manual),
                              icon: const Icon(Icons.add),
                              label: Text(tr.addExpenseBtn),
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
    final tr = context.tr;
    final greeting = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr.greeting(name), style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          tr.trackDaily,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    final date = OutlinedButton(
      onPressed: onMonth,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        side: BorderSide(color: context.finmi.border, width: 1.25),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        tr.monthLabel(month.month, month.year),
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ),
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
    this.debtSummary,
    this.onDebts,
  });
  final DashboardSnapshot snapshot;
  final int? income;
  final bool incomeError;
  final VoidCallback onRetry, onHistory;
  final DebtSummary? debtSummary;
  final VoidCallback? onDebts;
  @override
  State<_BalanceCard> createState() => _BalanceCardState();
}

class _BalanceCardState extends State<_BalanceCard> {
  bool hidden = false;
  @override
  Widget build(BuildContext context) {
    final t = context.finmi;
    final theme = Theme.of(context);
    final tr = context.tr;
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
                  ? (widget.incomeError ? (tr.isEn ? 'Failed' : 'Không tải được') : tr.loading)
                  : '${isIncome ? '+' : '-'} ${MoneyFormatter.format(value)}',
              style: statStyle?.copyWith(
                color: isIncome ? incomeColor : t.heroText,
              ),
            ),
          ],
        ),
      ),
    );
    final thu = metric(tr.monthlyIncome, widget.income, true);
    final chi = metric(tr.monthlyExpense, widget.snapshot.totalMinor, false);

    final receivable = widget.debtSummary?.totalReceivableMinor ?? 0;
    final payable = widget.debtSummary?.totalPayableMinor ?? 0;
    Widget debtMetric() => InkWell(
      onTap: widget.onDebts,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('⇄  ${tr.netDebts}', style: style),
            const SizedBox(height: 4),
            Text(
              hidden
                  ? '••••••'
                  : (receivable == 0 && payable == 0)
                      ? tr.noActiveDebts
                      : '${receivable > 0 ? '+${MoneyFormatter.format(receivable)} ' : ''}${payable > 0 ? '-${MoneyFormatter.format(payable)}' : ''}'.trim(),
              style: statStyle?.copyWith(
                color: receivable >= payable ? incomeColor : const Color(0xFFF87171),
              ),
            ),
          ],
        ),
      ),
    );

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
                  message: tr.balanceTooltip,
                  child: Text(
                    tr.totalBalance,
                    style: style?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              IconButton(
                tooltip: hidden ? tr.showAmount : tr.hideAmount,
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
                  ? (tr.isEn ? 'Failed to load income' : 'Không tải được khoản thu')
                  : (tr.isEn ? 'Loading balance…' : 'Đang tải số dư…'),
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
                  ? (tr.isEn ? 'Hidden balance' : 'Số dư đã ẩn')
                  : MoneyFormatter.format(
                      widget.income! - widget.snapshot.totalMinor,
                    ),
            ),
          if (widget.incomeError)
            TextButton(
              onPressed: widget.onRetry,
              style: TextButton.styleFrom(foregroundColor: t.heroText),
              child: Text(tr.isEn ? 'Retry income' : 'Thử lại khoản thu'),
            ),
          const SizedBox(height: 16),
          Divider(indent: 0, color: t.heroSecondary.withValues(alpha: .4)),
          const SizedBox(height: 12),
          if (context.needsStackedLayout) ...[
            thu,
            const SizedBox(height: 8),
            chi,
            const SizedBox(height: 8),
            debtMetric(),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: thu),
                const SizedBox(width: 8),
                Expanded(child: chi),
                const SizedBox(width: 8),
                Expanded(child: debtMetric()),
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
    final tr = context.tr;
    final description = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(CupertinoIcons.clock, size: 14),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                tr.todaySpending,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          tr.todaySpent(MoneyFormatter.format(snapshot.dailyTotals[today.day] ?? 0)),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: theme.colorScheme.onPrimary, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: theme.colorScheme.onSurface,
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
          label: context.tr.bannerSemantics,
          image: true,
          child: Image.asset(
            context.tr.isEn
                ? 'assets/branding/finmi/banner-en.png'
                : 'assets/branding/finmi/banner.png',
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

Future<void> _showHomeNotificationsSheet(
  BuildContext context,
  WidgetRef ref,
  List<InvoiceEntity>? pendingInvoices,
  List<DebtInAppNotification> debtNotifs,
) async {
  final tr = context.tr;
  final theme = Theme.of(context);
  final unreadDebts = debtNotifs.where((n) => !n.isRead).toList();

  ref.read(hideFloatingAssistantProvider.notifier).state = true;
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr.notifications,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        context.push('/invoices');
                      },
                      icon: const Icon(Icons.history_rounded, size: 16),
                      label: Text(tr.viewHistoryPage),
                    ),
                  ],
                ),
                if (unreadDebts.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      for (final n in unreadDebts) {
                        await DebtNotificationStore.markAsRead(n.id);
                      }
                      ref.invalidate(debtNotificationsProvider);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: Text(tr.markAllRead),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if ((pendingInvoices == null || pendingInvoices.isEmpty) &&
                debtNotifs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(28),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.notifications_off_outlined,
                        size: 48,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tr.noNotifications,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          context.push('/invoices');
                        },
                        icon: const Icon(Icons.receipt_long_outlined, size: 18),
                        label: Text(tr.openHistoryTransactions),
                      ),
                    ],
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.6,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (pendingInvoices != null && pendingInvoices.isNotEmpty) ...[
                      ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFFEF3C7),
                          child: Icon(
                            Icons.receipt_long,
                            color: Color(0xFFD97706),
                          ),
                        ),
                        title: Text(
                          tr.receiptsNeedReview(pendingInvoices.length),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(tr.tapToVerifyAndApprove),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.pop(ctx);
                          context.push('/invoices?review=1');
                        },
                      ),
                      const Divider(height: 1),
                    ],
                    if (debtNotifs.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 6),
                        child: Text(
                          tr.debtNotificationsTitle,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      for (final notif in debtNotifs)
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: notif.isRead
                                ? theme.colorScheme.surfaceContainerHighest
                                : const Color(0xFFDCFCE7),
                            child: Icon(
                              Icons.handshake_outlined,
                              color: notif.isRead
                                  ? theme.colorScheme.onSurfaceVariant
                                  : const Color(0xFF16A34A),
                            ),
                          ),
                          title: Text(
                            '${notif.senderName}: ${MoneyFormatter.format(notif.amountMinor)}',
                            style: TextStyle(
                              fontWeight: notif.isRead
                                  ? FontWeight.normal
                                  : FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            [
                              if (notif.notes != null && notif.notes!.isNotEmpty)
                                notif.notes!,
                              if (notif.dueDate != null)
                                '${tr.duePrefix}${notif.dueDate!.day}/${notif.dueDate!.month}/${notif.dueDate!.year}',
                            ].join(' · '),
                          ),
                          trailing: notif.isRead
                              ? const Icon(Icons.chevron_right)
                              : Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                          onTap: () async {
                            if (!notif.isRead) {
                              await DebtNotificationStore.markAsRead(notif.id);
                              ref.invalidate(debtNotificationsProvider);
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                            context.push('/invoices?tab=debts');
                          },
                        ),
                    ],
                    const Divider(height: 16),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(
                          Icons.history_rounded,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      title: Text(
                        tr.openHistoryTransactions,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(ctx);
                        context.push('/invoices');
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  } finally {
    ref.read(hideFloatingAssistantProvider.notifier).state = false;
  }
}
