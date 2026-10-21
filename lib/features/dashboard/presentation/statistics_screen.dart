import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/category_palette.dart';
import '../../../app/theme/finance_colors.dart';
import '../../../app/theme/finmi_theme.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/utils/month_utils.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_refresh.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/category_avatar.dart';
import '../../../shared/widgets/finmi_page_header.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/month_selector.dart';
import '../../export/presentation/report_export_sheet.dart';
import '../../income/data/income_repository.dart';
import '../../income/presentation/income_entry_sheet.dart';
import '../../invoices/domain/invoice_models.dart';
import '../domain/transaction_period.dart';
import 'monthly_transaction_calendar.dart';

class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});
  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  bool _yearMode = false;
  DateTime? _day;
  int? _month;

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(selectedMonthProvider);
    ref.listen(
      selectedMonthProvider,
      (_, _) => setState(() {
        _day = null;
        _month = null;
      }),
    );
    final invoices = ref.watch(invoiceSummariesProvider);
    final incomes = ref.watch(incomesProvider);
    final categories =
        ref.watch(categoriesProvider).valueOrNull ?? const <CategoryEntity>[];
    final incomeCategories =
        ref.watch(incomeCategoriesProvider).valueOrNull ??
        const <CategoryEntity>[];
    final monthSnapshot = ref.watch(dashboardProvider);
    ref.listen(dashboardProvider, (_, next) {
      if (next.valueOrNull case final snapshot?) {
        ref.read(budgetNotificationServiceProvider).notifyIfNeeded(snapshot);
      }
    });
    final period = _yearMode
        ? (_month == null
              ? TransactionPeriod.year(month.year)
              : TransactionPeriod.month(DateTime(month.year, _month!)))
        : (_day == null
              ? TransactionPeriod.month(month)
              : TransactionPeriod.day(_day!));
    final label = _yearMode
        ? (_month == null ? 'Năm ${month.year}' : 'Tháng $_month/${month.year}')
        : (_day == null
              ? 'Tháng ${month.month}/${month.year}'
              : 'Ngày ${DateFormat('dd/MM/yyyy').format(_day!)}');
    final data = PeriodTransactions(
      period: period,
      incomes: incomes.valueOrNull ?? [],
      expenses: invoices.valueOrNull ?? [],
    );
    final calendarData = PeriodTransactions(
      period: TransactionPeriod.month(month),
      incomes: incomes.valueOrNull ?? [],
      expenses: invoices.valueOrNull ?? [],
    );
    final snapshot = DashboardSnapshot(
      monthKey: MonthUtils.key(month),
      totalMinor: calendarData.expense,
      invoiceCount: calendarData.expenses.length,
      categoryTotals: calendarData.categories(false),
      dailyTotals: calendarData.dailyExpenses,
      budgetLimitMinor: monthSnapshot.valueOrNull?.budgetLimitMinor ?? 0,
    );
    final error = invoices.error ?? incomes.error;
    final loading = !invoices.hasValue || !incomes.hasValue;
    return Scaffold(
      body: AppRefreshIndicator(
        onRefresh: () => refreshFromCloud(context, ref),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            FinmiSliverHeader(
              title: 'Thống kê thu chi',
              actions: [
                FinmiHeaderAction(
                  tooltip: 'Xuất báo cáo',
                  icon: Icons.file_download_outlined,
                  onPressed: () => showReportExportSheet(context),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 112),
              sliver: error != null
                  ? SliverToBoxAdapter(
                      child: AppErrorState(
                        error: error,
                        onRetry: () {
                          ref.invalidate(invoiceSummariesProvider);
                          ref.invalidate(incomesProvider);
                        },
                      ),
                    )
                  : loading
                  ? const SliverToBoxAdapter(child: SkeletonHero())
                  : SliverList.list(
                      children: [
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: false,
                              label: Text('Theo tháng'),
                            ),
                            ButtonSegment(value: true, label: Text('Theo năm')),
                          ],
                          selected: {_yearMode},
                          showSelectedIcon: false,
                          onSelectionChanged: (value) => setState(() {
                            _yearMode = value.single;
                            _day = null;
                            _month = null;
                          }),
                        ),
                        const SizedBox(height: 12),
                        if (!_yearMode)
                          const MonthSelector()
                        else
                          AppCard(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: 'Năm trước',
                                  onPressed: () => _setYear(month.year - 1),
                                  icon: const Icon(Icons.chevron_left),
                                ),
                                Expanded(
                                  child: TextButton(
                                    onPressed: () => _pickYear(month.year),
                                    child: Text(
                                      'Năm ${month.year}',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Năm sau',
                                  onPressed: () => _setYear(month.year + 1),
                                  icon: const Icon(Icons.chevron_right),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        _PeriodSummary(data: data, label: label),
                        const SizedBox(height: 16),
                        if (_yearMode)
                          _YearGrid(
                            year: month.year,
                            selected: _month,
                            invoices: invoices.valueOrNull ?? [],
                            incomes: incomes.valueOrNull ?? [],
                            onSelect: (value) => setState(() => _month = value),
                          )
                        else
                          MonthlyTransactionCalendar(
                            month: month,
                            snapshot: snapshot,
                            incomes: incomes.valueOrNull ?? [],
                            selectedDay: _day,
                            onSelectDay: (value) =>
                                setState(() => _day = value),
                          ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => setState(() {
                                _day = null;
                                _month = null;
                              }),
                              icon: const Icon(Icons.date_range_outlined),
                              label: Text(
                                _yearMode ? 'Xem toàn năm' : 'Xem toàn tháng',
                              ),
                            ),
                            if (_yearMode && _month != null)
                              TextButton.icon(
                                onPressed: () {
                                  final selected = DateTime(
                                    month.year,
                                    _month!,
                                  );
                                  ref
                                          .read(selectedMonthProvider.notifier)
                                          .state =
                                      selected;
                                  setState(() {
                                    _yearMode = false;
                                    _day = null;
                                    _month = null;
                                  });
                                },
                                icon: const Icon(Icons.calendar_month_outlined),
                                label: const Text('Xem các ngày trong tháng'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Biểu đồ · $label',
                          key: const ValueKey('statistics-period'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        _PeriodFlowChart(
                          data: data,
                          yearly: _yearMode && _month == null,
                          daily: !_yearMode && _day != null,
                        ),
                        const SizedBox(height: 16),
                        _PeriodPie(
                          data: data,
                          categories: categories,
                          incomeCategories: incomeCategories,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Giao dịch · $label',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        if (data.incomes.isEmpty && data.expenses.isEmpty)
                          const AppCard(
                            child: AppEmptyState(
                              icon: Icons.receipt_long_outlined,
                              title: 'Chưa có giao dịch',
                              message:
                                  'Không có khoản thu hoặc chi đã lưu trong khoảng này.',
                            ),
                          ),
                        ..._transactionRows(
                          context,
                          data,
                          categories,
                          incomeCategories,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _setYear(int year) {
    if (year < 1900 || year > 2100) return;
    ref.read(selectedMonthProvider.notifier).state = DateTime(
      year,
      ref.read(selectedMonthProvider).month,
    );
  }

  Future<void> _pickYear(int year) async {
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chọn năm'),
        content: SizedBox(
          width: 320,
          height: 360,
          child: YearPicker(
            firstDate: DateTime(1900),
            lastDate: DateTime(2100),
            selectedDate: DateTime(year),
            onChanged: (value) => Navigator.pop(context, value.year),
          ),
        ),
      ),
    );
    if (value != null && mounted) _setYear(value);
  }

  List<Widget> _transactionRows(
    BuildContext context,
    PeriodTransactions data,
    List<CategoryEntity> expenses,
    List<CategoryEntity> incomes,
  ) {
    final rows =
        <
            ({
              DateTime date,
              int amount,
              String title,
              CategoryEntity? category,
              VoidCallback tap,
            })
          >[
            for (final e in data.incomes)
              (
                date: e.receivedAt,
                amount: e.amountMinor,
                title: e.note.isEmpty ? 'Khoản thu' : e.note,
                category: incomes
                    .where((c) => c.id == e.categoryId)
                    .firstOrNull,
                tap: () => showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  showDragHandle: true,
                  builder: (_) => IncomeEntrySheet(entry: e),
                ),
              ),
            for (final e in data.expenses)
              (
                date: e.issuedAt ?? e.createdAt,
                amount: -e.totalMinor,
                title: e.sellerName,
                category: expenses
                    .where((c) => c.id == e.categoryId)
                    .firstOrNull,
                tap: () => context.push('/invoices/${e.id}'),
              ),
          ]
          ..sort((a, b) => b.date.compareTo(a.date));
    return [
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            onTap: row.tap,
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CategoryAvatar(category: row.category, radius: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.title,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${row.amount >= 0 ? 'Thu' : 'Chi'} · ${row.category?.name ?? 'Khác'} · ${DateFormat('dd/MM/yyyy').format(row.date)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${row.amount >= 0 ? '+' : '−'}${MoneyFormatter.format(row.amount.abs())}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: row.amount >= 0
                              ? context.finance.income.color
                              : context.finance.expense.color,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }
}

class _PeriodSummary extends StatelessWidget {
  const _PeriodSummary({required this.data, required this.label});
  final PeriodTransactions data;
  final String label;
  @override
  Widget build(BuildContext context) {
    Widget value(String title, int amount, FinanceTone tone) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        MoneyText(amount, emphasis: MoneyEmphasis.body, tone: tone),
      ],
    );
    final income = value('↓ Tổng thu', data.income, context.finance.income);
    final expense = value('↑ Tổng chi', data.expense, context.finance.expense);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 16),
          if (context.needsStackedLayout ||
              data.income >= 100000000 ||
              data.expense >= 100000000) ...[
            income,
            const SizedBox(height: 12),
            expense,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: income),
                const SizedBox(width: 12),
                Expanded(child: expense),
              ],
            ),
          const Divider(height: 28),
          Text(
            'Chênh lệch thu − chi',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          MoneyText(
            data.net,
            tone: data.net >= 0
                ? context.finance.income
                : context.finance.expense,
          ),
        ],
      ),
    );
  }
}

class _YearGrid extends StatelessWidget {
  const _YearGrid({
    required this.year,
    required this.selected,
    required this.invoices,
    required this.incomes,
    required this.onSelect,
  });
  final int year;
  final int? selected;
  final List<InvoiceEntity> invoices;
  final List<IncomeEntry> incomes;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = context.needsStackedLayout ? 2 : 3;
      final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var month = 1; month <= 12; month++)
            SizedBox(
              width: width,
              child: Builder(
                builder: (context) {
                  final data = PeriodTransactions(
                    period: TransactionPeriod.month(DateTime(year, month)),
                    incomes: incomes,
                    expenses: invoices,
                  );
                  return Semantics(
                    selected: selected == month,
                    child: AppCard(
                      onTap: () => onSelect(month),
                      color: selected == month
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tháng $month',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            compactNet(data.net),
                            semanticsLabel:
                                'Chênh lệch ${MoneyFormatter.format(data.net)}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: data.net >= 0
                                      ? context.finance.income.color
                                      : context.finance.expense.color,
                                ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      );
    },
  );
}

class _PeriodFlowChart extends StatelessWidget {
  const _PeriodFlowChart({
    required this.data,
    required this.yearly,
    required this.daily,
  });
  final PeriodTransactions data;
  final bool yearly, daily;
  @override
  Widget build(BuildContext context) {
    final count = daily
        ? 1
        : yearly
        ? 12
        : DateUtils.getDaysInMonth(
            data.period.start.year,
            data.period.start.month,
          );
    final buckets = List.generate(count, (index) {
      final date = yearly
          ? DateTime(data.period.start.year, index + 1)
          : DateTime(
              data.period.start.year,
              data.period.start.month,
              daily ? data.period.start.day : index + 1,
            );
      return PeriodTransactions(
        period: yearly
            ? TransactionPeriod.month(date)
            : TransactionPeriod.day(date),
        incomes: data.incomes,
        expenses: data.expenses,
      );
    });
    final maximum = buckets.fold<int>(
      0,
      (v, b) => [v, b.income, b.expense].reduce((a, b) => a > b ? a : b),
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Dòng tiền', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              Text(
                '↓ Thu nhập',
                style: TextStyle(color: context.finance.income.color),
              ),
              Text(
                '↑ Chi tiêu',
                style: TextStyle(color: context.finance.expense.color),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (maximum == 0)
            const AppEmptyState(
              icon: Icons.bar_chart_outlined,
              title: 'Chưa có dữ liệu thu chi',
              message:
                  'Biểu đồ sẽ cập nhật khi có giao dịch trong mốc đã chọn.',
            )
          else
            Semantics(
              label:
                  'Biểu đồ dòng tiền. Tổng thu ${MoneyFormatter.format(data.income)}. Tổng chi ${MoneyFormatter.format(data.expense)}.',
              child: SizedBox(
                height: 180,
                child: BarChart(
                  BarChartData(
                    maxY: maximum * 1.2,
                    minY: 0,
                    alignment: BarChartAlignment.spaceAround,
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      horizontalInterval: maximum / 4,
                    ),
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                            BarTooltipItem(
                              '${yearly ? 'Tháng' : 'Ngày'} ${daily ? data.period.start.day : group.x + 1}\n${rodIndex == 0 ? 'Thu' : 'Chi'}: ${MoneyFormatter.format(rod.toY.round())}',
                              TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onInverseSurface,
                              ),
                            ),
                      ),
                    ),
                    barGroups: [
                      for (var index = 0; index < count; index++)
                        BarChartGroupData(
                          x: index,
                          barsSpace: 2,
                          barRods: [
                            BarChartRodData(
                              toY: buckets[index].income.toDouble(),
                              width: daily
                                  ? 28
                                  : yearly
                                  ? 7
                                  : 3,
                              color: context.finance.income.color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            BarChartRodData(
                              toY: buckets[index].expense.toDouble(),
                              width: daily
                                  ? 28
                                  : yearly
                                  ? 7
                                  : 3,
                              color: context.finance.expense.color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            daily
                ? 'Thu và chi trong ngày đã chọn'
                : yearly
                ? 'Tháng 1 → Tháng 12 · Chạm cột để xem số tiền'
                : 'Ngày 1 → Ngày $count · Chạm cột để xem số tiền',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PeriodPie extends StatefulWidget {
  const _PeriodPie({
    required this.data,
    required this.categories,
    required this.incomeCategories,
  });
  final PeriodTransactions data;
  final List<CategoryEntity> categories, incomeCategories;
  @override
  State<_PeriodPie> createState() => _PeriodPieState();
}

class _PeriodPieState extends State<_PeriodPie> {
  bool _income = false;
  @override
  Widget build(BuildContext context) {
    final categories = _income ? widget.incomeCategories : widget.categories;
    final entries =
        widget.data
            .categories(_income)
            .entries
            .where((e) => e.value > 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (v, e) => v + e.value);
    CategoryEntity? category(String id) =>
        categories.where((c) => c.id == id).firstOrNull;
    Color color(String id) => CategoryPalette.resolve(
      category(id)?.colorValue ?? 0xFF52665A,
      Theme.of(context).colorScheme,
    ).glyph;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Phân bổ thu chi',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Khoản chi')),
              ButtonSegment(value: true, label: Text('Khoản thu')),
            ],
            selected: {_income},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _income = v.single),
          ),
          const SizedBox(height: 16),
          if (total == 0)
            const AppEmptyState(
              icon: Icons.pie_chart_outline,
              title: 'Chưa có dữ liệu',
              message: 'Chọn mốc thời gian khác hoặc thêm giao dịch.',
            )
          else ...[
            Semantics(
              label:
                  'Biểu đồ tròn ${_income ? 'thu nhập' : 'chi tiêu'} theo mốc đang chọn',
              child: SizedBox(
                height: 180,
                child: PieChart(
                  PieChartData(
                    centerSpaceRadius: 42,
                    sectionsSpace: 3,
                    sections: [
                      for (final e in entries)
                        PieChartSectionData(
                          value: e.value.toDouble(),
                          color: color(e.key),
                          radius: 36,
                          showTitle: false,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CategoryAvatar(category: category(entry.key), radius: 14),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            category(entry.key)?.name ?? 'Khác',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Text(
                            '${MoneyFormatter.format(entry.value)} · ${(entry.value / total * 100).toStringAsFixed(1).replaceAll('.', ',')}%',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
