import '../../../shared/widgets/finmi_page_header.dart';
import '../../../shared/widgets/category_avatar.dart';
import '../../../app/theme/finmi_theme.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../shared/widgets/finmi_assistant_button.dart';
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
import '../../../shared/widgets/app_refresh.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/widgets/app_callout.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/entity_list_row.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/reading_pane.dart';
import '../../../shared/widgets/status_pill.dart';
import '../domain/invoice_filters.dart';
import '../domain/invoice_models.dart';

class InvoiceListScreen extends ConsumerStatefulWidget {
  const InvoiceListScreen({
    super.key,
    this.initialMonthKey,
    this.initialCategoryId,
    this.initialReview = false,
  });

  final String? initialMonthKey;
  final String? initialCategoryId;
  final bool initialReview;

  @override
  ConsumerState<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends ConsumerState<InvoiceListScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _categoryId;
  InvoiceStatus? _status;
  InvoiceSourceType? _sourceType;
  DateTime? _month;
  Timer? _searchDebounce;
  int _limit = 50;
  _TransactionKind _kind = _TransactionKind.all;
  bool _selectionMode = false;
  bool _bulkBusy = false;
  final Set<String> _selectedInvoiceIds = {};

  @override
  void initState() {
    super.initState();
    _month = _parseMonthKey(widget.initialMonthKey);
    _categoryId = widget.initialCategoryId;
    if (_categoryId != null) _kind = _TransactionKind.expense;
    if (widget.initialReview) {
      _status = InvoiceStatus.needsReview;
      _kind = _TransactionKind.expense;
    }
  }

  @override
  void didUpdateWidget(covariant InvoiceListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialMonthKey != oldWidget.initialMonthKey) {
      _month = _parseMonthKey(widget.initialMonthKey);
      _limit = 50;
      _selectedInvoiceIds.clear();
      _selectionMode = false;
    }
    if (widget.initialCategoryId != oldWidget.initialCategoryId) {
      _categoryId = widget.initialCategoryId;
      if (_categoryId != null) _kind = _TransactionKind.expense;
      _selectedInvoiceIds.clear();
      _selectionMode = false;
    }
    if (widget.initialReview != oldWidget.initialReview) {
      _status = widget.initialReview ? InvoiceStatus.needsReview : null;
      if (widget.initialReview) _kind = _TransactionKind.expense;
      _selectedInvoiceIds.clear();
      _selectionMode = false;
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
      _sourceType != null,
      _categoryId != null,
      _month != null,
    ].where((active) => active).length;
    final filter = InvoiceFilter(
      query: _query,
      monthKey: _month == null ? null : MonthUtils.key(_month!),
      categoryId: _categoryId,
      status: _status,
      sourceType: _sourceType,
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
    final reviewPending =
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
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      body: ReadingPane(
        child: AppRefreshIndicator(
          onRefresh: () => refreshFromCloud(context, ref),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                centerTitle: true,
                title: Text(
                  _selectionMode
                      ? 'Đã chọn ${_selectedInvoiceIds.length}'
                      : 'Lịch sử thu chi',
                ),
                leading: IconButton(
                  tooltip: _selectionMode
                      ? 'Hủy chọn'
                      : canPop
                      ? 'Quay lại'
                      : 'Về Tổng quan',
                  onPressed: _selectionMode
                      ? _leaveSelectionMode
                      : () => canPop ? context.pop() : context.go('/'),
                  icon: Icon(_selectionMode ? Icons.close : Icons.chevron_left),
                ),
                actions: [
                  if (!_selectionMode) ...[
                    FinmiHeaderAction(
                      tooltip: 'Chọn nhiều khoản chi',
                      onPressed: _enterSelectionMode,
                      icon: Icons.checklist_rounded,
                    ),
                  ],
                  const SizedBox(width: 8),
                ],
              ),
              if (!_selectionMode)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                    child: _FilterHeader(
                      controller: _searchController,
                      query: _query,
                      filterCount: activeFilterCount,
                      kind: _kind,
                      reviewSelected: _status == InvoiceStatus.needsReview,
                      onReviewTap: _toggleReviewFilter,
                      currentMonthSelected:
                          _month != null &&
                          MonthUtils.key(_month!) ==
                              MonthUtils.key(DateTime.now()),
                      onCurrentMonthTap: _toggleCurrentMonth,
                      onKindChanged: _changeKind,
                      onQueryChanged: _onQueryChanged,
                      onFilterTap: () => _showFilters(categories),
                      onClear:
                          filter.hasActiveFilters ||
                              _kind != _TransactionKind.all
                          ? _clearFilters
                          : null,
                    ),
                  ),
                ),
              if (_selectionMode)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: Text(
                      'Chọn các khoản chi đã xác nhận hoặc cần kiểm tra.',
                    ),
                  ),
                ),
              if (!_selectionMode &&
                  reviewPending &&
                  _status != InvoiceStatus.needsReview)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: AppCallout(
                      title: 'Giao dịch cần kiểm tra',
                      message:
                          'Có khoản chi chưa được xác nhận. Kiểm tra trước khi tính vào báo cáo và ngân sách.',
                      tone: CalloutTone.warning,
                      icon: Icons.fact_check_outlined,
                      actions: [
                        TextButton(
                          onPressed: _showReviewOnly,
                          child: const Text('Xem các khoản cần kiểm tra'),
                        ),
                      ],
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
                    sliver: SliverToBoxAdapter(
                      child: SkeletonListRows(count: 6),
                    ),
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
                        _kind != _TransactionKind.income &&
                        items.length > _limit;
                    final visibleInvoices = hasMore
                        ? items.take(_limit).toList(growable: false)
                        : items;
                    final selectableIds = visibleInvoices
                        .where(
                          (invoice) =>
                              invoice.status == InvoiceStatus.confirmed ||
                              invoice.status == InvoiceStatus.needsReview,
                        )
                        .map((invoice) => invoice.id)
                        .toSet();
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
                                  in incomes.valueOrNull ??
                                      const <IncomeEntry>[])
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
                          reviewOnly: _status == InvoiceStatus.needsReview,
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
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 112),
                      sliver: SliverMainAxisGroup(
                        slivers: [
                          if (_selectionMode && selectableIds.isNotEmpty)
                            SliverToBoxAdapter(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () =>
                                      _selectVisible(selectableIds),
                                  child: Text(
                                    _selectedInvoiceIds.containsAll(
                                              selectableIds,
                                            ) &&
                                            _selectedInvoiceIds.isNotEmpty
                                        ? 'Bỏ chọn các khoản đang hiển thị'
                                        : 'Chọn các khoản đang hiển thị',
                                  ),
                                ),
                              ),
                            ),
                          // MỘT thẻ với các dòng có kẻ tóc, thay vì 50 thẻ chồng lên
                          // nhau — xoá 49 viền khỏi cuộn dài nhất của app.
                          SliverList.separated(
                            separatorBuilder: (_, _) => const SizedBox.shrink(),
                            itemCount: records.length,
                            itemBuilder: (context, index) {
                              final record = records[index];
                              final income = record.income;
                              if (income != null) {
                                return _IncomeRow(entry: income);
                              }
                              final invoice = record.invoice!;
                              return _InvoiceRow(
                                invoice: invoice,
                                selectionMode: _selectionMode,
                                selected: _selectedInvoiceIds.contains(
                                  invoice.id,
                                ),
                                onSelect: () =>
                                    _toggleInvoiceSelection(invoice.id),
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
                                    onPressed: () =>
                                        setState(() => _limit += 50),
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
        ),
      ),
      bottomNavigationBar: _selectionMode
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _selectedInvoiceIds.isEmpty || _bulkBusy
                            ? null
                            : _assignSelectedCategory,
                        icon: _bulkBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.category_outlined),
                        label: Text(
                          'Đổi danh mục · ${_selectedInvoiceIds.length}',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
      floatingActionButton: _selectionMode
          ? null
          : const FinmiAssistantButton(),
    );
  }

  void _clearFilters() {
    _searchDebounce?.cancel();
    setState(() {
      _searchController.clear();
      _query = '';
      _categoryId = null;
      _status = null;
      _sourceType = null;
      _month = null;
      _kind = _TransactionKind.all;
      _limit = 50;
      _selectedInvoiceIds.clear();
      _selectionMode = false;
    });
  }

  void _showReviewOnly() {
    _searchDebounce?.cancel();
    setState(() {
      _searchController.clear();
      _query = '';
      _month = null;
      _categoryId = null;
      _kind = _TransactionKind.expense;
      _status = InvoiceStatus.needsReview;
      _sourceType = null;
      _limit = 50;
      _selectedInvoiceIds.clear();
      _selectionMode = false;
    });
  }

  void _toggleReviewFilter() {
    if (_status == InvoiceStatus.needsReview) {
      _clearFilters();
    } else {
      _showReviewOnly();
    }
  }

  void _toggleCurrentMonth() {
    _changeFilter(() {
      final now = MonthUtils.normalize(DateTime.now());
      _month = _month != null && MonthUtils.key(_month!) == MonthUtils.key(now)
          ? null
          : now;
    });
  }

  void _enterSelectionMode() {
    setState(() {
      if (_kind == _TransactionKind.income) {
        _searchDebounce?.cancel();
        _searchController.clear();
        _query = '';
        _categoryId = null;
      }
      _selectionMode = true;
      _kind = _TransactionKind.expense;
      _selectedInvoiceIds.clear();
    });
  }

  void _leaveSelectionMode() {
    if (_bulkBusy) return;
    setState(() {
      _selectionMode = false;
      _selectedInvoiceIds.clear();
    });
  }

  void _toggleInvoiceSelection(String id) {
    if (_bulkBusy) return;
    setState(() {
      _selectionMode = true;
      _kind = _TransactionKind.expense;
      if (!_selectedInvoiceIds.add(id)) _selectedInvoiceIds.remove(id);
    });
  }

  void _selectVisible(Set<String> ids) {
    if (_bulkBusy) return;
    setState(() {
      if (_selectedInvoiceIds.containsAll(ids)) {
        _selectedInvoiceIds.removeAll(ids);
      } else {
        _selectedInvoiceIds.addAll(ids);
      }
    });
  }

  Future<void> _assignSelectedCategory() async {
    final categories =
        ref.read(categoriesProvider).valueOrNull ?? const <CategoryEntity>[];
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có danh mục chi để chọn.')),
      );
      return;
    }
    final categoryId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Đổi danh mục cho ${_selectedInvoiceIds.length} khoản chi',
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Danh mục từng dòng hóa đơn được giữ lại. Khoản cần kiểm tra vẫn phải xác nhận riêng.',
                      style: Theme.of(sheetContext).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              for (final category in categories)
                ListTile(
                  leading: CategoryAvatar(category: category),
                  title: Text(category.name),
                  onTap: () => Navigator.pop(sheetContext, category.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (categoryId == null || !mounted) return;
    final ids = _selectedInvoiceIds.toList(growable: false);
    setState(() => _bulkBusy = true);
    try {
      final changed = await ref
          .read(invoiceRepositoryProvider)
          .assignCategoryToInvoices(ids, categoryId);
      if (!mounted) return;
      setState(() {
        _selectedInvoiceIds.clear();
        _selectionMode = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã đổi danh mục cho $changed khoản chi.')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể đổi danh mục: ${friendlyMessage(error)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  void _onQueryChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _changeFilter(() => _query = value);
    });
  }

  void _changeFilter(VoidCallback change) {
    _searchDebounce?.cancel();
    setState(() {
      _query = _searchController.text;
      change();
      _limit = 50;
      _selectedInvoiceIds.clear();
      _selectionMode = false;
    });
  }

  void _changeKind(_TransactionKind kind) {
    _changeFilter(() {
      _kind = kind;
      _categoryId = null;
      _status = null;
      _sourceType = null;
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
          ({
            InvoiceStatus? status,
            InvoiceSourceType? sourceType,
            String? categoryId,
            DateTime? month,
          })
        >(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          useRootNavigator: true,
          showDragHandle: true,
          builder: (sheetContext) {
            var status = _status;
            var sourceType = _sourceType;
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
                        const SizedBox(height: 16),
                        Text(
                          'Nguồn nhập',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final (type, label) in const [
                              (null, 'Tất cả'),
                              (InvoiceSourceType.manual, 'Thủ công'),
                              (InvoiceSourceType.imageOcr, 'Ảnh / QR'),
                              (InvoiceSourceType.pdfText, 'PDF'),
                              (InvoiceSourceType.xml, 'XML'),
                            ])
                              ChoiceChip(
                                label: Text(label),
                                selected: sourceType == type,
                                onSelected: (_) =>
                                    setSheetState(() => sourceType = type),
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
                        title: const Text('Tháng', maxLines: 3),
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
                              sourceType: null,
                              categoryId: null,
                              month: null,
                            )),
                            child: const Text('Xóa lọc'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () => Navigator.pop(sheetContext, (
                              status: status,
                              sourceType: sourceType,
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
      _sourceType = result.sourceType;
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
    required this.reviewSelected,
    required this.onReviewTap,
    required this.currentMonthSelected,
    required this.onCurrentMonthTap,
    required this.onKindChanged,
    required this.onQueryChanged,
    required this.onFilterTap,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final int filterCount;
  final _TransactionKind kind;
  final bool reviewSelected;
  final VoidCallback onReviewTap;
  final bool currentMonthSelected;
  final VoidCallback onCurrentMonthTap;
  final ValueChanged<_TransactionKind> onKindChanged;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onFilterTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final search = SearchBar(
      constraints: const BoxConstraints(minHeight: 56),
      controller: controller,
      hintText: 'Tìm giao dịch thu hoặc chi',
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
    );
    final filter = OutlinedButton.icon(
      key: const ValueKey('transaction-filter-button'),
      onPressed: onFilterTap,
      icon: Badge(
        isLabelVisible: filterCount > 0,
        label: Text('$filterCount'),
        child: const Icon(Icons.tune),
      ),
      label: const Text('Lọc'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (context.needsStackedLayout)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in const [
                (_TransactionKind.all, 'Tất cả'),
                (_TransactionKind.expense, 'Khoản chi'),
                (_TransactionKind.income, 'Khoản thu'),
              ])
                ChoiceChip(
                  label: Text(option.$2),
                  selected: kind == option.$1,
                  onSelected: (_) => onKindChanged(option.$1),
                ),
            ],
          )
        else
          SegmentedButton<_TransactionKind>(
            segments: const [
              ButtonSegment(value: _TransactionKind.all, label: Text('Tất cả')),
              ButtonSegment(
                value: _TransactionKind.expense,
                label: Text('Khoản chi'),
              ),
              ButtonSegment(
                value: _TransactionKind.income,
                label: Text('Khoản thu'),
              ),
            ],
            selected: {kind},
            onSelectionChanged: (value) => onKindChanged(value.first),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              avatar: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Cần kiểm tra'),
              selected: reviewSelected,
              onSelected: (_) => onReviewTap(),
            ),
            ChoiceChip(
              avatar: const Icon(Icons.calendar_today_outlined, size: 18),
              label: const Text('Tháng này'),
              selected: currentMonthSelected,
              onSelected: (_) => onCurrentMonthTap(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (context.needsStackedLayout) ...[
          search,
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight, child: filter),
        ] else
          Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 12),
              filter,
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
      leading: null,
      outlined: true,
      title: entry.note.isEmpty ? categoryName : entry.note,
      subtitle:
          'Khoản thu · $categoryName · ${AppDateFormat.shortDate(entry.receivedAt)}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('+', style: TextStyle(color: finance.income.color)),
          Flexible(child: MoneyText(entry.amountMinor, tone: finance.income)),
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
  const _InvoiceRow({
    required this.invoice,
    required this.category,
    required this.selectionMode,
    required this.selected,
    required this.onSelect,
  });

  final InvoiceEntity invoice;
  final CategoryEntity? category;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = invoice.issuedAt ?? invoice.createdAt;
    final needsReview = invoice.status == InvoiceStatus.needsReview;
    final canSelect = needsReview || invoice.status == InvoiceStatus.confirmed;
    final seller = invoice.sellerName.isEmpty
        ? 'Chưa có tên người bán'
        : invoice.sellerName;
    final categoryName = category?.name ?? 'Chưa phân loại';

    return EntityListRow(
      // Danh mục dẫn đầu, không phải phương thức import. Danh mục là trục tổ
      // chức của cả ngân sách lẫn dashboard; trước đây nó không xuất hiện ở
      // đây, trong khi nguồn import chiếm avatar 48dp.
      leading: selectionMode
          ? Checkbox(
              value: selected,
              onChanged: canSelect ? (_) => onSelect() : null,
            )
          : null,
      outlined: true,
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
          Flexible(child: MoneyText(invoice.totalMinor)),
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
      onTap: selectionMode
          ? (canSelect ? onSelect : null)
          : () => context.push('/invoices/${invoice.id}'),
      onLongPress: selectionMode || !canSelect ? null : onSelect,
      // Một câu duy nhất cho TalkBack, thay vì 4 mảnh rời.
      semanticLabel:
          '$seller, $categoryName, ${AppDateFormat.shortDate(date)}, '
          'chi ${MoneyFormatter.format(invoice.totalMinor)}, '
          'nguồn ${_sourceLabel(invoice.sourceType)}'
          '${needsReview ? ', cần kiểm tra' : ''}'
          '${selectionMode ? ', ${selected ? 'đã chọn' : 'chưa chọn'}' : ''}',
    );
  }
}

class _InvoiceEmptyState extends StatelessWidget {
  const _InvoiceEmptyState({
    required this.incomeOnly,
    required this.reviewOnly,
    required this.filtered,
    required this.query,
    this.onClear,
  });

  final bool filtered;
  final bool incomeOnly;
  final bool reviewOnly;
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
            reviewOnly
                ? Icons.task_alt_outlined
                : incomeOnly
                ? Icons.add_circle_outline
                : Icons.receipt_long_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 20),
          Text(
            incomeOnly
                ? 'Chưa có khoản thu'
                : reviewOnly
                ? 'Đã kiểm tra hết giao dịch'
                : filtered
                ? 'Không tìm thấy giao dịch'
                : 'Chưa có giao dịch',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            incomeOnly
                ? 'Chọn Thêm thu/chi trong Tiện ích để ghi khoản thu.'
                : reviewOnly
                ? 'Các khoản chi mới cần xác nhận sẽ xuất hiện tại đây.'
                : filtered
                ? (query.trim().isEmpty
                      ? 'Thử bỏ bớt bộ lọc để xem thêm kết quả.'
                      : 'Không có kết quả cho “${query.trim()}”. Hãy thử từ khóa khác.')
                : 'Chọn Thêm thu/chi hoặc Quét ở trang Tổng quan để bắt đầu.',
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
