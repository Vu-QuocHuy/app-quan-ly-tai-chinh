import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';
import '../../../app/theme/finance_colors.dart';
import '../../../core/utils/string_normalizer.dart';
import '../../income/data/income_repository.dart';
import '../../income/presentation/income_entry_sheet.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/utils/month_utils.dart';
import '../../../shared/formatting/app_date_format.dart';
import '../../../shared/formatting/category_lookup.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_list_section.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/category_avatar.dart';
import '../../../shared/widgets/entity_list_row.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/status_pill.dart';
import '../domain/invoice_filters.dart';
import '../domain/invoice_models.dart';

class InvoiceListScreen extends ConsumerStatefulWidget {
  const InvoiceListScreen({super.key, this.initialMonthKey});

  final String? initialMonthKey;

  @override
  ConsumerState<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends ConsumerState<InvoiceListScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _categoryId;
  InvoiceStatus? _status;
  DateTime? _month;
  Timer? _searchDebounce;
  int _limit = 50;
  _TransactionKind _kind = _TransactionKind.all;

  @override
  void initState() {
    super.initState();
    _month = _parseMonthKey(widget.initialMonthKey);
  }

  @override
  void didUpdateWidget(covariant InvoiceListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialMonthKey != oldWidget.initialMonthKey) {
      _month = _parseMonthKey(widget.initialMonthKey);
      _limit = 50;
    }
  }

  DateTime? _parseMonthKey(String? key) {
    if (key == null || !RegExp(r'^\d{4}-\d{2}$').hasMatch(key)) return null;
    final year = int.parse(key.substring(0, 4));
    final month = int.parse(key.substring(5));
    if (year < 2000 || year > 2100 || month < 1 || month > 12) return null;
    return DateTime(year, month);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeFilterCount = [
      _status != null,
      _categoryId != null,
      _month != null,
    ].where((active) => active).length;
    final filter = InvoiceFilter(
      query: _query,
      monthKey: _month == null ? null : MonthUtils.key(_month!),
      categoryId: _categoryId,
      status: _status,
    );
    final invoices = ref.watch(
      filteredInvoiceSummariesProvider(
        InvoiceListQuery(filter: filter, limit: _limit + 1),
      ),
    );
    final incomes = ref.watch(incomesProvider);
    final incomeCategories =
        ref.watch(incomeCategoriesProvider).value ?? const [];
    final invoiceResults = _kind == _TransactionKind.income
        ? const AsyncValue<List<InvoiceEntity>>.data([])
        : invoices;
    final categories = _kind == _TransactionKind.income
        ? incomeCategories
        : ref.watch(categoriesProvider).value ?? const [];
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: const Text('Giao dịch'),
            actions: [
              IconButton(
                tooltip: 'Mở trợ lý chi tiêu',
                onPressed: () => context.push('/chat'),
                icon: const Icon(Icons.chat_bubble_outline),
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: _FilterHeader(
                controller: _searchController,
                query: _query,
                filterCount: activeFilterCount,
                kind: _kind,
                onKindChanged: _changeKind,
                onQueryChanged: _onQueryChanged,
                onFilterTap: () => _showFilters(categories),
                onClear:
                    filter.hasActiveFilters || _kind != _TransactionKind.all
                    ? _clearFilters
                    : null,
              ),
            ),
          ),
          if (_kind != _TransactionKind.expense && incomes.isLoading)
            const SliverPadding(
              padding: EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(child: SkeletonListRows(count: 3)),
            )
          else if (_kind != _TransactionKind.expense && incomes.hasError)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AppErrorState(
                error: incomes.error!,
                stackTrace: incomes.stackTrace,
                title: 'Không tải được khoản thu',
                onRetry: () => ref.invalidate(incomesProvider),
              ),
            )
          else
            invoiceResults.when(
              loading: () => const SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 112),
                sliver: SliverToBoxAdapter(child: SkeletonListRows(count: 6)),
              ),
              // Trước đây nhánh này là ngõ cụt hoàn toàn: một câu có nội suy
              // exception, không nút nào.
              error: (error, stack) => SliverFillRemaining(
                hasScrollBody: false,
                child: AppErrorState(
                  error: error,
                  stackTrace: stack,
                  title: 'Không tải được lịch sử giao dịch',
                  onRetry: () => ref.invalidate(
                    filteredInvoiceSummariesProvider(
                      InvoiceListQuery(filter: filter, limit: _limit + 1),
                    ),
                  ),
                ),
              ),
              data: (items) {
                final hasMore =
                    _kind != _TransactionKind.income && items.length > _limit;
                final visibleInvoices = hasMore
                    ? items.take(_limit).toList(growable: false)
                    : items;
                final records =
                    <
                        ({
                          InvoiceEntity? invoice,
                          IncomeEntry? income,
                          DateTime date,
                        })
                      >[
                        if (_kind != _TransactionKind.income)
                          for (final invoice in visibleInvoices)
                            (
                              invoice: invoice,
                              income: null,
                              date: invoice.issuedAt ?? invoice.createdAt,
                            ),
                        if (_kind != _TransactionKind.expense &&
                            _status == null)
                          for (final income
                              in incomes.valueOrNull ?? const <IncomeEntry>[])
                            if ((_categoryId == null ||
                                    income.categoryId == _categoryId) &&
                                (_month == null ||
                                    MonthUtils.key(income.receivedAt) ==
                                        MonthUtils.key(_month!)) &&
                                _matchesIncome(income, incomeCategories))
                              (
                                invoice: null,
                                income: income,
                                date: income.receivedAt,
                              ),
                      ]
                      ..sort((a, b) => b.date.compareTo(a.date));
                if (records.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: _InvoiceEmptyState(
                      incomeOnly: _kind == _TransactionKind.income,
                      filtered:
                          filter.hasActiveFilters ||
                          _kind != _TransactionKind.all,
                      query: _query,
                      onClear:
                          filter.hasActiveFilters ||
                              _kind != _TransactionKind.all
                          ? _clearFilters
                          : null,
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
                  sliver: SliverMainAxisGroup(
                    slivers: [
                      // MỘT thẻ với các dòng có kẻ tóc, thay vì 50 thẻ chồng lên
                      // nhau — xoá 49 viền khỏi cuộn dài nhất của app.
                      SliverAppListSection(
                        itemCount: records.length,
                        itemBuilder: (context, index) {
                          final record = records[index];
                          final income = record.income;
                          if (income != null) return _IncomeRow(entry: income);
                          final invoice = record.invoice!;
                          return _InvoiceRow(
                            invoice: invoice,
                            category: findCategory(
                              categories,
                              invoice.categoryId,
                            ),
                          );
                        },
                      ),
                      if (hasMore)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Center(
                              child: OutlinedButton.icon(
                                onPressed: () => setState(() => _limit += 50),
                                icon: const Icon(Icons.expand_more),
                                label: const Text('Tải thêm giao dịch'),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _query = '';
      _categoryId = null;
      _status = null;
      _month = null;
      _kind = _TransactionKind.all;
      _limit = 50;
    });
  }

  void _onQueryChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _changeFilter(() => _query = value);
    });
  }

  void _changeFilter(VoidCallback change) {
    setState(() {
      change();
      _limit = 50;
    });
  }

  void _changeKind(_TransactionKind kind) {
    _changeFilter(() {
      _kind = kind;
      _categoryId = null;
      _status = null;
    });
  }

  bool _matchesIncome(IncomeEntry income, List<CategoryEntity> categories) {
    final query = StringNormalizer.merchant(_query);
    if (query.isEmpty) return true;
    final categoryName =
        findCategory(categories, income.categoryId)?.name ?? 'Chưa phân loại';
    final searchable = StringNormalizer.merchant(
      [
        categoryName,
        income.source.label,
        AppDateFormat.shortDate(income.receivedAt),
        income.amountMinor.toString(),
        MoneyFormatter.format(income.amountMinor),
      ].join(' '),
    );
    return searchable.contains(query);
  }

  Future<void> _showFilters(List<CategoryEntity> categories) async {
    final result =
        await showModalBottomSheet<
          ({InvoiceStatus? status, String? categoryId, DateTime? month})
        >(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          useRootNavigator: true,
          showDragHandle: true,
          builder: (sheetContext) {
            var status = _status;
            var categoryId = _categoryId;
            var month = _month;
            return StatefulBuilder(
              builder: (context, setSheetState) => SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Bộ lọc giao dịch',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (_kind != _TransactionKind.income) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Trạng thái',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Tất cả'),
                              selected: status == null,
                              onSelected: (_) =>
                                  setSheetState(() => status = null),
                            ),
                            ChoiceChip(
                              label: const Text('Cần kiểm tra'),
                              selected: status == InvoiceStatus.needsReview,
                              onSelected: (_) => setSheetState(
                                () => status = InvoiceStatus.needsReview,
                              ),
                            ),
                            ChoiceChip(
                              label: const Text('Đã xác nhận'),
                              selected: status == InvoiceStatus.confirmed,
                              onSelected: (_) => setSheetState(
                                () => status = InvoiceStatus.confirmed,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        key: const ValueKey('transaction-category-filter'),
                        initialValue: categoryId ?? '',
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: _kind == _TransactionKind.income
                              ? 'Danh mục thu'
                              : 'Danh mục chi',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Tất cả danh mục'),
                          ),
                          if (categoryId != null &&
                              !categories.any((item) => item.id == categoryId))
                            DropdownMenuItem(
                              value: categoryId!,
                              child: Text(categoryId!),
                            ),
                          ...categories.map(
                            (category) => DropdownMenuItem(
                              value: category.id,
                              child: Text(category.name),
                            ),
                          ),
                        ],
                        onChanged: (value) => setSheetState(
                          () => categoryId = value == null || value.isEmpty
                              ? null
                              : value,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.calendar_month_outlined),
                        title: const Text('Tháng'),
                        subtitle: Text(
                          month == null
                              ? 'Tất cả các tháng'
                              : MonthUtils.label(month!),
                        ),
                        trailing: month == null
                            ? const Icon(Icons.chevron_right)
                            : IconButton(
                                tooltip: 'Bỏ lọc tháng',
                                onPressed: () =>
                                    setSheetState(() => month = null),
                                icon: const Icon(Icons.close),
                              ),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: sheetContext,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                            initialDate: month ?? DateTime.now(),
                            helpText: 'Chọn tháng cần lọc',
                          );
                          if (picked != null) {
                            setSheetState(
                              () => month = MonthUtils.normalize(picked),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(sheetContext, (
                              status: null,
                              categoryId: null,
                              month: null,
                            )),
                            child: const Text('Xóa lọc'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () => Navigator.pop(sheetContext, (
                              status: status,
                              categoryId: categoryId,
                              month: month,
                            )),
                            child: const Text('Áp dụng'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
    if (result == null || !mounted) return;
    _changeFilter(() {
      _status = result.status;
      _categoryId = result.categoryId;
      _month = result.month;
    });
  }
}

enum _TransactionKind { all, income, expense }

class _FilterHeader extends StatelessWidget {
  const _FilterHeader({
    required this.controller,
    required this.query,
    required this.filterCount,
    required this.kind,
    required this.onKindChanged,
    required this.onQueryChanged,
    required this.onFilterTap,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final int filterCount;
  final _TransactionKind kind;
  final ValueChanged<_TransactionKind> onKindChanged;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onFilterTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Loại giao dịch', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<_TransactionKind>(
          segments: const [
            ButtonSegment(value: _TransactionKind.all, label: Text('Tất cả')),
            ButtonSegment(value: _TransactionKind.income, label: Text('Thu')),
            ButtonSegment(value: _TransactionKind.expense, label: Text('Chi')),
          ],
          selected: {kind},
          onSelectionChanged: (value) => onKindChanged(value.first),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SearchBar(
                constraints: const BoxConstraints(minHeight: 56),
                controller: controller,
                hintText: switch (kind) {
                  _TransactionKind.income => 'Tìm danh mục, ngày hoặc số tiền',
                  _TransactionKind.expense =>
                    'Tìm người bán, ký hiệu hoặc ghi chú',
                  _TransactionKind.all => 'Tìm giao dịch thu hoặc chi',
                },
                leading: const Icon(Icons.search),
                onChanged: onQueryChanged,
                trailing: [
                  if (query.isNotEmpty)
                    IconButton(
                      tooltip: 'Xóa nội dung tìm kiếm',
                      onPressed: () {
                        controller.clear();
                        onQueryChanged('');
                      },
                      icon: const Icon(Icons.clear),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              key: const ValueKey('transaction-filter-button'),
              onPressed: onFilterTap,
              icon: Badge(
                isLabelVisible: filterCount > 0,
                backgroundColor: Theme.of(context).colorScheme.primary,
                textColor: Theme.of(context).colorScheme.onPrimary,
                label: Text('$filterCount'),
                child: const Icon(Icons.tune),
              ),
              label: const Text('Lọc'),
            ),
          ],
        ),
        if (onClear != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onClear, child: const Text('Đặt lại')),
          ),
      ],
    );
  }
}

class _IncomeRow extends ConsumerWidget {
  const _IncomeRow({required this.entry});

  final IncomeEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final finance = Theme.of(context).extension<AppFinanceColors>()!;
    final categories =
        ref.watch(incomeCategoriesProvider).valueOrNull ?? const [];
    final category = categories
        .where((item) => item.id == entry.categoryId)
        .firstOrNull;
    final categoryName = category?.name ?? 'Chưa phân loại';
    return EntityListRow(
      leading: category == null
          ? CircleAvatar(
              radius: 20,
              backgroundColor: finance.income.container,
              child: Icon(Icons.add, color: finance.income.onContainer),
            )
          : CategoryAvatar(category: category),
      title: categoryName,
      subtitle: 'Khoản thu · ${AppDateFormat.shortDate(entry.receivedAt)}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('+', style: TextStyle(color: finance.income.color)),
          MoneyText(entry.amountMinor, tone: finance.income, compact: true),
        ],
      ),
      semanticLabel:
          '$categoryName, khoản thu, ${AppDateFormat.shortDate(entry.receivedAt)}, '
          '${MoneyFormatter.format(entry.amountMinor)}',
      onTap: () => showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => IncomeEntrySheet(entry: entry),
      ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({required this.invoice, required this.category});

  final InvoiceEntity invoice;
  final CategoryEntity? category;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = invoice.issuedAt ?? invoice.createdAt;
    final needsReview = invoice.status == InvoiceStatus.needsReview;
    final seller = invoice.sellerName.isEmpty
        ? 'Chưa có tên người bán'
        : invoice.sellerName;
    final categoryName = category?.name ?? 'Chưa phân loại';

    return EntityListRow(
      // Danh mục dẫn đầu, không phải phương thức import. Danh mục là trục tổ
      // chức của cả ngân sách lẫn dashboard; trước đây nó không xuất hiện ở
      // đây, trong khi nguồn import chiếm avatar 48dp.
      leading: CategoryAvatar(category: category),
      title: seller,
      subtitle: '$categoryName · ${AppDateFormat.shortDate(date)}',
      badge: needsReview
          // tone warn, KHÔNG phải danger: cần kiểm tra không phải là lỗi.
          ? const StatusPill(
              icon: Icons.fact_check_outlined,
              label: 'Cần kiểm tra',
              tone: StatusTone.warn,
              dense: true,
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('−'),
          MoneyText(invoice.totalMinor),
          const SizedBox(width: 6),
          // Nguồn import xuống hạng thành glyph nhỏ ở đuôi — nhưng chữ của nó
          // phải sống tiếp trong semanticLabel bên dưới, nếu không người dùng
          // đọc màn hình mất hẳn thông tin này (EntityListRow bọc cả dòng
          // trong ExcludeSemantics).
          Tooltip(
            message: _sourceLabel(invoice.sourceType),
            child: Icon(
              _sourceIcon(invoice.sourceType),
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      onTap: () => context.push('/invoices/${invoice.id}'),
      // Một câu duy nhất cho TalkBack, thay vì 4 mảnh rời.
      semanticLabel:
          '$seller, $categoryName, ${AppDateFormat.shortDate(date)}, '
          'chi ${MoneyFormatter.format(invoice.totalMinor)}, '
          'nguồn ${_sourceLabel(invoice.sourceType)}'
          '${needsReview ? ', cần kiểm tra' : ''}',
    );
  }
}

class _InvoiceEmptyState extends StatelessWidget {
  const _InvoiceEmptyState({
    required this.incomeOnly,
    required this.filtered,
    required this.query,
    this.onClear,
  });

  final bool filtered;
  final bool incomeOnly;
  final String query;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            incomeOnly ? Icons.add_circle_outline : Icons.receipt_long_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 20),
          Text(
            incomeOnly
                ? 'Chưa có khoản thu'
                : filtered
                ? 'Không tìm thấy giao dịch'
                : 'Chưa có giao dịch',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            incomeOnly
                ? 'Nhấn “Thêm giao dịch” để ghi khoản thu bằng số tiền.'
                : filtered
                ? (query.trim().isEmpty
                      ? 'Thử bỏ bớt bộ lọc để xem thêm kết quả.'
                      : 'Không có kết quả cho “${query.trim()}”. Hãy thử từ khóa khác.')
                : 'Nhấn “Thêm giao dịch” để ghi khoản thu, chụp hóa đơn hoặc nhập khoản chi.',
            textAlign: TextAlign.center,
          ),
          if (filtered && onClear != null) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Xóa bộ lọc'),
            ),
          ],
        ],
      ),
    );
  }
}

IconData _sourceIcon(InvoiceSourceType source) => switch (source) {
  InvoiceSourceType.xml => Icons.data_object,
  InvoiceSourceType.pdfText => Icons.picture_as_pdf_outlined,
  InvoiceSourceType.imageOcr => Icons.document_scanner_outlined,
  InvoiceSourceType.manual => Icons.edit_note,
};

String _sourceLabel(InvoiceSourceType source) => switch (source) {
  InvoiceSourceType.xml => 'XML',
  InvoiceSourceType.pdfText => 'PDF',
  InvoiceSourceType.imageOcr => 'Ảnh OCR',
  InvoiceSourceType.manual => 'Thủ công',
};
