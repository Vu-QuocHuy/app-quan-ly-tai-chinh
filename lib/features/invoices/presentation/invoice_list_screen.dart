import '../../../shared/widgets/finmi_page_header.dart';
import '../../../shared/widgets/category_avatar.dart';
import '../../../app/theme/finmi_theme.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../shared/widgets/finmi_assistant_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../../app/theme/finance_colors.dart';
import '../../../core/utils/string_normalizer.dart';
import '../../debts/data/debt_notification_store.dart';
import '../../debts/data/debt_repository.dart';
import '../../debts/domain/debt_models.dart';
import '../../debts/domain/debt_notification.dart';
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
    this.initialTab,
  });

  final String? initialMonthKey;
  final String? initialCategoryId;
  final bool initialReview;
  final String? initialTab;

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
      _kind = _TransactionKind.review;
    }
    if (widget.initialTab != null) {
      _applyTab(widget.initialTab!);
    }
  }

  void _applyTab(String tab) {
    switch (tab) {
      case 'debts':
        _kind = _TransactionKind.debts;
        _status = null;
        break;
      case 'income':
        _kind = _TransactionKind.income;
        _status = null;
        break;
      case 'expense':
        _kind = _TransactionKind.expense;
        _status = null;
        break;
      case 'review':
        _status = InvoiceStatus.needsReview;
        _kind = _TransactionKind.review;
        break;
      case 'all':
      default:
        _kind = _TransactionKind.all;
        _status = null;
        break;
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
      if (widget.initialReview) _kind = _TransactionKind.review;
      _selectedInvoiceIds.clear();
      _selectionMode = false;
    }
    if (widget.initialTab != oldWidget.initialTab && widget.initialTab != null) {
      _applyTab(widget.initialTab!);
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
    final tr = context.tr;
    final isEn = tr.isEn;
    final debts = ref.watch(debtsListProvider);
    final debtNotifs = ref.watch(debtNotificationsProvider).valueOrNull ?? const [];

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
                      ? tr.selectedCount(_selectedInvoiceIds.length)
                      : (isEn ? 'History' : 'Lịch sử'),
                ),
                leading: IconButton(
                  tooltip: _selectionMode
                      ? tr.cancelSelection
                      : canPop
                      ? tr.back
                      : tr.backToOverview,
                  onPressed: _selectionMode
                      ? _leaveSelectionMode
                      : () => canPop ? context.pop() : context.go('/'),
                  icon: Icon(_selectionMode ? Icons.close : Icons.chevron_left),
                ),
                actions: [
                  if (!_selectionMode && _kind != _TransactionKind.debts) ...[
                    FinmiHeaderAction(
                      tooltip: tr.selectMultipleExpenses,
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
                      reviewSelected: _status == InvoiceStatus.needsReview || _kind == _TransactionKind.review,
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
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: Text(tr.selectionHint),
                  ),
                ),
              if (!_selectionMode &&
                  reviewPending &&
                  _status != InvoiceStatus.needsReview &&
                  _kind != _TransactionKind.review &&
                  _kind != _TransactionKind.debts)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: AppCallout(
                      title: tr.transactionsNeedReviewTitle,
                      message: tr.transactionsNeedReviewDesc,
                      tone: CalloutTone.warning,
                      icon: Icons.fact_check_outlined,
                      actions: [
                        TextButton(
                          onPressed: _showReviewOnly,
                          child: Text(tr.viewNeedsReviewBtn),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_kind == _TransactionKind.debts)
                ..._buildDebtsSlivers(context, tr, debts, debtNotifs)
              else if (_kind != _TransactionKind.expense && _kind != _TransactionKind.review && incomes.isLoading)
                const SliverPadding(
                  padding: EdgeInsets.all(16),
                  sliver: SliverToBoxAdapter(child: SkeletonListRows(count: 3)),
                )
              else if (_kind != _TransactionKind.expense && _kind != _TransactionKind.review && incomes.hasError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppErrorState(
                    error: incomes.error!,
                    stackTrace: incomes.stackTrace,
                    title: tr.cannotLoadIncomes,
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
                  error: (error, stack) => SliverFillRemaining(
                    hasScrollBody: false,
                    child: AppErrorState(
                      error: error,
                      stackTrace: stack,
                      title: tr.cannotLoadHistory,
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
                                _kind != _TransactionKind.review &&
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
                          reviewOnly: _status == InvoiceStatus.needsReview || _kind == _TransactionKind.review,
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
                                        ? tr.deselectVisibleItems
                                        : tr.selectVisibleItems,
                                  ),
                                ),
                              ),
                            ),
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
                                    label: Text(
                                      isEn
                                          ? 'Load more transactions'
                                          : 'Tải thêm giao dịch',
                                    ),
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
                          isEn
                              ? 'Change category · ${_selectedInvoiceIds.length}'
                              : 'Đổi danh mục · ${_selectedInvoiceIds.length}',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
      floatingActionButton: _selectionMode || ref.watch(hasActiveModalProvider).hasModal
          ? null
          : const FinmiAssistantButton(),
    );
  }

  List<Widget> _buildDebtsSlivers(
    BuildContext context,
    AppStrings tr,
    AsyncValue<List<DebtRecord>> debts,
    List<DebtInAppNotification> debtNotifs,
  ) {
    if (debts.isLoading) {
      return const [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 112),
          sliver: SliverToBoxAdapter(child: SkeletonListRows(count: 4)),
        ),
      ];
    }
    if (debts.hasError) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: AppErrorState(
            error: debts.error!,
            stackTrace: debts.stackTrace,
            title: tr.cannotLoadHistory,
            onRetry: () => ref.invalidate(debtsListProvider),
          ),
        ),
      ];
    }
    final allDebts = debts.valueOrNull ?? const [];
    final q = _query.trim().toLowerCase();
    final filteredDebts = allDebts.where((d) {
      if (q.isEmpty) return true;
      return d.personName.toLowerCase().contains(q) ||
          (d.notes ?? '').toLowerCase().contains(q);
    }).toList();
    final filteredNotifs = debtNotifs.where((n) {
      if (q.isEmpty) return true;
      return n.senderName.toLowerCase().contains(q) ||
          (n.notes ?? '').toLowerCase().contains(q);
    }).toList();

    if (filteredDebts.isEmpty && filteredNotifs.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.handshake_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  tr.noDebtsYet,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => context.push('/debts'),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text(
                    tr.isEn ? 'Open Debts Manager' : 'Mở mục Quản lý Nợ',
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 112),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            if (filteredNotifs.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 4),
                child: Text(
                  tr.isEn
                      ? 'Debt Notifications (${filteredNotifs.length})'
                      : 'Thông báo nợ nhận được (${filteredNotifs.length})',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final n in filteredNotifs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _DebtNotificationRow(notification: n),
                ),
              const SizedBox(height: 12),
            ],
            if (filteredDebts.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 4),
                child: Text(
                  tr.isEn
                      ? 'My Debt Records (${filteredDebts.length})'
                      : 'Khoản nợ của tôi (${filteredDebts.length})',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final d in filteredDebts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _DebtRecordRow(debt: d),
                ),
            ],
          ]),
        ),
      ),
    ];
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
      _kind = _TransactionKind.review;
      _status = InvoiceStatus.needsReview;
      _sourceType = null;
      _limit = 50;
      _selectedInvoiceIds.clear();
      _selectionMode = false;
    });
  }

  void _toggleReviewFilter() {
    if (_status == InvoiceStatus.needsReview || _kind == _TransactionKind.review) {
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
      if (_kind == _TransactionKind.income || _kind == _TransactionKind.debts) {
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
    final tr = context.tr;
    final isEn = tr.isEn;
    final categories =
        ref.read(categoriesProvider).valueOrNull ?? const <CategoryEntity>[];
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEn
                ? 'No expense categories available.'
                : 'Chưa có danh mục chi để chọn.',
          ),
        ),
      );
      return;
    }
    ref.read(hideFloatingAssistantProvider.notifier).state = true;
    final String? categoryId;
    try {
      categoryId = await showModalBottomSheet<String>(
        context: context,
        useRootNavigator: true,
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
                        isEn
                            ? 'Change category for ${_selectedInvoiceIds.length} expenses'
                            : 'Đổi danh mục cho ${_selectedInvoiceIds.length} khoản chi',
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isEn
                            ? 'Individual line items will be preserved. Needs-review items still require verification.'
                            : 'Danh mục từng dòng hóa đơn được giữ lại. Khoản cần kiểm tra vẫn phải xác nhận riêng.',
                        style: Theme.of(sheetContext).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                for (final category in categories)
                  ListTile(
                    leading: CategoryAvatar(category: category),
                    title: Text(
                      tr.categoryName(category.name, categoryId: category.id),
                    ),
                    onTap: () => Navigator.pop(sheetContext, category.id),
                  ),
              ],
            ),
          ),
        ),
      );
    } finally {
      ref.read(hideFloatingAssistantProvider.notifier).state = false;
    }

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
        SnackBar(
          content: Text(
            isEn
                ? 'Changed category for $changed expenses.'
                : 'Đã đổi danh mục cho $changed khoản chi.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEn
                ? 'Could not change category: ${friendlyMessage(error)}'
                : 'Không thể đổi danh mục: ${friendlyMessage(error)}',
          ),
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
      if (kind == _TransactionKind.review) {
        _status = InvoiceStatus.needsReview;
      } else {
        _status = null;
      }
      _sourceType = null;
    });
  }

  bool _matchesIncome(IncomeEntry income, List<CategoryEntity> categories) {
    final query = StringNormalizer.merchant(_query);
    if (query.isEmpty) return true;
    final tr = context.tr;
    final category = findCategory(categories, income.categoryId);
    final categoryName = category != null
        ? tr.categoryName(category.name, categoryId: category.id)
        : tr.unclassified;
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
    final tr = context.tr;
    final isEn = tr.isEn;
    ref.read(hideFloatingAssistantProvider.notifier).state = true;
    final ({
      InvoiceStatus? status,
      InvoiceSourceType? sourceType,
      String? categoryId,
      DateTime? month,
    })? result;

    try {
      result =
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
                          isEn ? 'Transaction Filters' : 'Bộ lọc giao dịch',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (_kind != _TransactionKind.income) ...[
                          const SizedBox(height: 20),
                          Text(
                            isEn ? 'Status' : 'Trạng thái',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: Text(tr.tabAll),
                                selected: status == null,
                                onSelected: (_) =>
                                    setSheetState(() => status = null),
                              ),
                              ChoiceChip(
                                label: Text(tr.tabNeedsReview),
                                selected: status == InvoiceStatus.needsReview,
                                onSelected: (_) => setSheetState(
                                  () => status = InvoiceStatus.needsReview,
                                ),
                              ),
                              ChoiceChip(
                                label: Text(isEn ? 'Confirmed' : 'Đã xác nhận'),
                                selected: status == InvoiceStatus.confirmed,
                                onSelected: (_) => setSheetState(
                                  () => status = InvoiceStatus.confirmed,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            isEn ? 'Source' : 'Nguồn nhập',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final (type, label) in [
                                (null, tr.tabAll),
                                (InvoiceSourceType.manual, isEn ? 'Manual' : 'Thủ công'),
                                (InvoiceSourceType.imageOcr, isEn ? 'Image OCR' : 'Ảnh / QR'),
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
                                ? (isEn ? 'Income Category' : 'Danh mục thu')
                                : (isEn ? 'Expense Category' : 'Danh mục chi'),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: '',
                              child: Text(isEn ? 'All categories' : 'Tất cả danh mục'),
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
                                child: Text(
                                  tr.categoryName(
                                    category.name,
                                    categoryId: category.id,
                                  ),
                                ),
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
                          title: Text(isEn ? 'Month' : 'Tháng', maxLines: 3),
                          subtitle: Text(
                            month == null
                                ? (isEn ? 'All months' : 'Tất cả các tháng')
                                : MonthUtils.label(month!, isEn: isEn),
                          ),
                          trailing: month == null
                              ? const Icon(Icons.chevron_right)
                              : IconButton(
                                  tooltip: isEn ? 'Clear month filter' : 'Bỏ lọc tháng',
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
                              helpText: isEn ? 'Select month to filter' : 'Chọn tháng cần lọc',
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
                              child: Text(tr.clearFilters),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () => Navigator.pop(sheetContext, (
                                status: status,
                                sourceType: sourceType,
                                categoryId: categoryId,
                                month: month,
                              )),
                              child: Text(isEn ? 'Apply' : 'Áp dụng'),
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
    } finally {
      ref.read(hideFloatingAssistantProvider.notifier).state = false;
    }

    final applied = result;
    if (applied == null || !mounted) return;
    _changeFilter(() {
      _status = applied.status;
      _sourceType = applied.sourceType;
      _categoryId = applied.categoryId;
      _month = applied.month;
    });
  }
}

enum _TransactionKind { all, expense, income, debts, review }

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
    final tr = context.tr;
    final isEn = tr.isEn;

    final search = SearchBar(
      constraints: const BoxConstraints(minHeight: 56),
      controller: controller,
      hintText: tr.searchTransactionsHint,
      leading: const Icon(Icons.search),
      onChanged: onQueryChanged,
      trailing: [
        if (query.isNotEmpty)
          IconButton(
            tooltip: isEn ? 'Clear search text' : 'Xóa nội dung tìm kiếm',
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
      label: Text(tr.filterBtn),
    );

    final tabs = [
      (_TransactionKind.all, tr.tabAll),
      (_TransactionKind.expense, tr.tabExpenses),
      (_TransactionKind.income, tr.tabIncome),
      (_TransactionKind.debts, tr.tabDebts),
      (_TransactionKind.review, tr.tabNeedsReview),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in tabs)
              ChoiceChip(
                label: Text(option.$2),
                selected: kind == option.$1,
                onSelected: (_) => onKindChanged(option.$1),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              avatar: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(tr.thisMonth),
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
            child: TextButton(onPressed: onClear, child: Text(tr.resetFilter)),
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
    final tr = context.tr;
    final isEn = tr.isEn;
    final finance = Theme.of(context).extension<AppFinanceColors>()!;
    final categories =
        ref.watch(incomeCategoriesProvider).valueOrNull ?? const [];
    final category = categories
        .where((item) => item.id == entry.categoryId)
        .firstOrNull;
    final categoryName = category != null
        ? tr.categoryName(category.name, categoryId: category.id)
        : tr.unclassified;

    return EntityListRow(
      leading: null,
      outlined: true,
      title: entry.note.isEmpty ? categoryName : entry.note,
      subtitle: isEn
          ? 'Income · $categoryName · ${AppDateFormat.shortDate(entry.receivedAt)}'
          : 'Khoản thu · $categoryName · ${AppDateFormat.shortDate(entry.receivedAt)}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('+', style: TextStyle(color: finance.income.color)),
          Flexible(child: MoneyText(entry.amountMinor, tone: finance.income)),
        ],
      ),
      semanticLabel:
          '$categoryName, ${isEn ? 'income' : 'khoản thu'}, ${AppDateFormat.shortDate(entry.receivedAt)}, '
          '${MoneyFormatter.format(entry.amountMinor)}',
      onTap: () => showModalBottomSheet<bool>(
        context: context,
        useRootNavigator: true,
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
    final tr = context.tr;
    final isEn = tr.isEn;
    final scheme = Theme.of(context).colorScheme;
    final date = invoice.issuedAt ?? invoice.createdAt;
    final needsReview = invoice.status == InvoiceStatus.needsReview;
    final canSelect = needsReview || invoice.status == InvoiceStatus.confirmed;
    final seller = invoice.sellerName.isEmpty
        ? tr.noSeller
        : invoice.sellerName;
    final categoryName = category != null
        ? tr.categoryName(category!.name, categoryId: category!.id)
        : tr.unclassified;

    return EntityListRow(
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
          ? StatusPill(
              icon: Icons.fact_check_outlined,
              label: tr.tabNeedsReview,
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
          Tooltip(
            message: _sourceLabel(invoice.sourceType, isEn: isEn),
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
      semanticLabel:
          '$seller, $categoryName, ${AppDateFormat.shortDate(date)}, '
          '${isEn ? 'spent' : 'chi'} ${MoneyFormatter.format(invoice.totalMinor)}, '
          '${isEn ? 'source' : 'nguồn'} ${_sourceLabel(invoice.sourceType, isEn: isEn)}'
          '${needsReview ? (isEn ? ', needs review' : ', cần kiểm tra') : ''}'
          '${selectionMode ? ', ${selected ? (isEn ? 'selected' : 'đã chọn') : (isEn ? 'unselected' : 'chưa chọn')}' : ''}',
    );
  }
}

class _DebtNotificationRow extends ConsumerWidget {
  const _DebtNotificationRow({required this.notification});

  final DebtInAppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = context.tr;
    final isEn = tr.isEn;

    final senderDisplay = (notification.senderPhone != null &&
            notification.senderPhone!.isNotEmpty &&
            notification.senderName != notification.senderPhone)
        ? '${notification.senderName} (${notification.senderPhone})'
        : (notification.senderPhone ?? notification.senderName);

    final title = isEn
        ? 'Debt notice from $senderDisplay'
        : 'Thông báo nợ từ $senderDisplay';

    final badge = notification.isSaved
        ? StatusPill(
            icon: Icons.check_circle_outline,
            label: isEn ? 'Saved to debts' : 'Đã lưu vào nợ',
            tone: StatusTone.safe,
            dense: true,
          )
        : notification.isRead
            ? StatusPill(
                icon: Icons.hourglass_top_rounded,
                label: isEn ? 'Pending' : 'Chờ xác nhận',
                tone: StatusTone.neutral,
                dense: true,
              )
            : StatusPill(
                icon: Icons.mark_email_unread_outlined,
                label: isEn ? 'New' : 'Mới',
                tone: StatusTone.warn,
                dense: true,
              );

    return EntityListRow(
      leading: CircleAvatar(
        backgroundColor: notification.isSaved
            ? const Color(0xFFDCFCE7)
            : const Color(0xFFFEF3C7),
        child: Icon(
          notification.isSaved
              ? Icons.check_circle_outline_rounded
              : Icons.notifications_active_outlined,
          color: notification.isSaved
              ? const Color(0xFF16A34A)
              : const Color(0xFFD97706),
          size: 20,
        ),
      ),
      outlined: true,
      title: title,
      subtitle:
          '${notification.notes?.isNotEmpty == true ? '${notification.notes} · ' : ''}${AppDateFormat.shortDate(notification.createdAt)}',
      badge: badge,
      trailing: MoneyText(notification.amountMinor),
      onTap: () async {
        if (!notification.isRead) {
          await DebtNotificationStore.markAsRead(notification.id);
          ref.invalidate(debtNotificationsProvider);
        }
        if (context.mounted) {
          if (notification.isSaved &&
              notification.savedDebtId != null &&
              notification.savedDebtId!.isNotEmpty) {
            context.push('/debts?debtId=${notification.savedDebtId}');
          } else if (notification.isSaved) {
            context.push('/debts');
          } else {
            _showConfirmSaveDebtSheet(context, ref, notification);
          }
        }
      },
    );
  }
}

Future<void> _showConfirmSaveDebtSheet(
  BuildContext context,
  WidgetRef ref,
  DebtInAppNotification notification,
) {
  final tr = context.tr;
  final isEn = tr.isEn;
  final theme = Theme.of(context);
  final finance = theme.extension<AppFinanceColors>()!;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (modalCtx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: finance.expense.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.handshake_rounded,
                      color: finance.expense.color,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEn ? 'Confirm Debt Notice' : 'Xác nhận thông báo nợ',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isEn
                              ? 'Record this into your debt manager'
                              : 'Lưu khoản nợ này vào mục Quản lý nợ của bạn',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  children: [
                    _buildDebtInfoRow(
                      context,
                      label: isEn ? 'Sender (Lender)' : 'Người gửi (Chủ nợ)',
                      value: notification.senderName,
                      isBold: true,
                    ),
                    if (notification.senderPhone != null &&
                        notification.senderPhone!.isNotEmpty) ...[
                      const Divider(height: 16),
                      _buildDebtInfoRow(
                        context,
                        label: isEn ? 'Sender Phone' : 'Số điện thoại',
                        value: notification.senderPhone!,
                      ),
                    ],
                    const Divider(height: 16),
                    _buildDebtInfoRow(
                      context,
                      label: isEn ? 'Amount to pay' : 'Số tiền cần trả',
                      value: MoneyFormatter.format(notification.amountMinor),
                      valueColor: finance.expense.color,
                      isBold: true,
                      fontSize: 16,
                    ),
                    if (notification.notes != null &&
                        notification.notes!.trim().isNotEmpty) ...[
                      const Divider(height: 16),
                      _buildDebtInfoRow(
                        context,
                        label: isEn ? 'Reason / Notes' : 'Lý do / Ghi chú',
                        value: notification.notes!,
                      ),
                    ],
                    if (notification.dueDate != null) ...[
                      const Divider(height: 16),
                      _buildDebtInfoRow(
                        context,
                        label: isEn ? 'Due date' : 'Hạn trả',
                        value: DateFormat('dd/MM/yyyy').format(notification.dueDate!),
                      ),
                    ],
                    const Divider(height: 16),
                    _buildDebtInfoRow(
                      context,
                      label: isEn ? 'Sent at' : 'Thời gian gửi',
                      value: DateFormat('dd/MM/yyyy HH:mm').format(notification.createdAt),
                      isDimmed: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isEn
                            ? 'Will be saved under "To Pay" (You owe ${notification.senderName}). The sender will see that you have saved it.'
                            : 'Khoản nợ sẽ được lưu vào mục "Cần trả" (Bạn nợ ${notification.senderName}). Bên người gửi sẽ thấy trạng thái bạn đã lưu nợ.',
                        style: TextStyle(fontSize: 11.5, color: theme.colorScheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(modalCtx),
                      child: Text(isEn ? 'Later' : 'Để sau'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                      label: Text(isEn ? 'Save to My Debts' : 'Lưu vào khoản nợ của tôi'),
                      onPressed: () async {
                        final newDebt = DebtRecord(
                          id: 'debt-${DateTime.now().millisecondsSinceEpoch}',
                          personName: notification.senderName,
                          phoneNumber: notification.senderPhone,
                          type: DebtType.iOwe,
                          amountMinor: notification.amountMinor,
                          paidAmountMinor: 0,
                          notes: notification.notes,
                          dueDate: notification.dueDate,
                          createdAt: DateTime.now(),
                        );

                        await ref.read(debtsListProvider.notifier).addOrUpdate(newDebt);
                        await DebtNotificationStore.confirmAndSaveNotification(
                          notifId: notification.id,
                          savedDebtId: newDebt.id,
                        );

                        ref.invalidate(debtNotificationsProvider);
                        ref.invalidate(debtsListProvider);

                        if (modalCtx.mounted) {
                          Navigator.pop(modalCtx);
                        }

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                isEn
                                    ? 'Saved to your debts (To Pay)'
                                    : 'Đã lưu vào danh sách nợ cần trả của bạn!',
                              ),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                          context.push('/debts?debtId=${newDebt.id}');
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _buildDebtInfoRow(
  BuildContext context, {
  required String label,
  required String value,
  Color? valueColor,
  bool isBold = false,
  bool isDimmed = false,
  double? fontSize,
}) {
  final theme = Theme.of(context);
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: TextStyle(
            fontSize: fontSize ?? 13,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            color: valueColor ??
                (isDimmed
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface),
          ),
        ),
      ),
    ],
  );
}

class _DebtRecordRow extends StatelessWidget {
  const _DebtRecordRow({required this.debt});

  final DebtRecord debt;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final isEn = tr.isEn;
    final finance = Theme.of(context).extension<AppFinanceColors>()!;
    final isReceivable = debt.type == DebtType.theyOwe;
    final typeLabel = isReceivable
        ? (isEn ? 'To collect' : 'Cần thu')
        : (isEn ? 'To pay' : 'Cần trả');
    final tone = isReceivable ? finance.income : finance.expense;

    return EntityListRow(
      leading: CircleAvatar(
        backgroundColor: tone.color.withValues(alpha: 0.12),
        child: Icon(
          isReceivable ? Icons.call_received_rounded : Icons.call_made_rounded,
          color: tone.color,
          size: 20,
        ),
      ),
      outlined: true,
      title: debt.personName,
      subtitle:
          '$typeLabel · ${debt.notes?.isNotEmpty == true ? '${debt.notes} · ' : ''}${AppDateFormat.shortDate(debt.dueDate ?? debt.createdAt)}',
      badge: debt.isSettled
          ? StatusPill(
              icon: Icons.check_circle_outline,
              label: isEn ? 'Settled' : 'Đã thanh toán',
              tone: StatusTone.safe,
              dense: true,
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isReceivable ? '+' : '−',
            style: TextStyle(color: tone.color, fontWeight: FontWeight.bold),
          ),
          Flexible(child: MoneyText(debt.remainingMinor, tone: tone)),
        ],
      ),
      onTap: () => context.push('/debts'),
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
    final tr = context.tr;
    final isEn = tr.isEn;

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
                ? tr.noIncomesYet
                : reviewOnly
                ? tr.allReviewed
                : filtered
                ? tr.noTransactionsFound
                : tr.noTransactionsYet,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            incomeOnly
                ? (isEn
                    ? 'Select Add +/- in Utilities to record income.'
                    : 'Chọn Thêm thu/chi trong Tiện ích để ghi khoản thu.')
                : reviewOnly
                ? (isEn
                    ? 'New expenses needing confirmation will appear here.'
                    : 'Các khoản chi mới cần xác nhận sẽ xuất hiện tại đây.')
                : filtered
                ? (query.trim().isEmpty
                      ? (isEn
                          ? 'Try adjusting filters to see more results.'
                          : 'Thử bỏ bớt bộ lọc để xem thêm kết quả.')
                      : (isEn
                          ? 'No results for “${query.trim()}”. Try another keyword.'
                          : 'Không có kết quả cho “${query.trim()}”. Hãy thử từ khóa khác.'))
                : (isEn
                    ? 'Select Add +/- or Scan on the Overview page to get started.'
                    : 'Chọn Thêm thu/chi hoặc Quét ở trang Tổng quan để bắt đầu.'),
            textAlign: TextAlign.center,
          ),
          if (filtered && onClear != null) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: Text(tr.clearFilters),
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

String _sourceLabel(InvoiceSourceType source, {bool isEn = false}) => switch (source) {
  InvoiceSourceType.xml => 'XML',
  InvoiceSourceType.pdfText => 'PDF',
  InvoiceSourceType.imageOcr => isEn ? 'Image OCR' : 'Ảnh OCR',
  InvoiceSourceType.manual => isEn ? 'Manual' : 'Thủ công',
};
