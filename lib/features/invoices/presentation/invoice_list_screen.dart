import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';
import '../../../app/theme/finance_colors.dart';
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
  const InvoiceListScreen({super.key});

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
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
    final invoiceResults = _kind == _TransactionKind.income
        ? const AsyncValue<List<InvoiceEntity>>.data([])
        : invoices;
    final categories = ref.watch(categoriesProvider).value ?? const [];
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _FilterHeader(
                controller: _searchController,
                query: _query,
                categoryLabel: _categoryLabel(categories),
                monthLabel: _month == null ? null : MonthUtils.label(_month!),
                status: _status,
                kind: _kind,
                onKindChanged: _changeKind,
                onQueryChanged: _onQueryChanged,
                onStatusChanged: (value) =>
                    _changeFilter(() => _status = value),
                onCategoryTap: () => _selectCategory(categories),
                onMonthTap: _selectMonth,
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
                            _query.trim().isEmpty &&
                            _categoryId == null &&
                            _status == null)
                          for (final income
                              in incomes.valueOrNull ?? const <IncomeEntry>[])
                            if (_month == null ||
                                MonthUtils.key(income.receivedAt) ==
                                    MonthUtils.key(_month!))
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

  String? _categoryLabel(List<CategoryEntity> categories) {
    final id = _categoryId;
    if (id == null) return null;
    return categories.where((item) => item.id == id).firstOrNull?.name ?? id;
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
      if (kind == _TransactionKind.income) {
        _searchController.clear();
        _query = '';
        _categoryId = null;
        _status = null;
      }
    });
  }

  Future<void> _selectCategory(List<CategoryEntity> categories) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const ListTile(
              title: Text('Lọc theo danh mục'),
              subtitle: Text('Chọn một danh mục để thu hẹp danh sách'),
            ),
            ListTile(
              leading: const Icon(Icons.all_inclusive),
              title: const Text('Tất cả danh mục'),
              selected: _categoryId == null,
              onTap: () => Navigator.pop(sheetContext, ''),
            ),
            ...categories.map(
              (category) => ListTile(
                leading: Icon(Icons.category_outlined),
                title: Text(category.name),
                selected: category.id == _categoryId,
                onTap: () => Navigator.pop(sheetContext, category.id),
              ),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    _changeFilter(() => _categoryId = result.isEmpty ? null : result);
  }

  Future<void> _selectMonth() async {
    final result = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _month ?? DateTime.now(),
      helpText: 'Chọn tháng cần lọc',
    );
    if (result == null) return;
    _changeFilter(() => _month = MonthUtils.normalize(result));
  }
}

enum _TransactionKind { all, income, expense }

class _FilterHeader extends StatelessWidget {
  const _FilterHeader({
    required this.controller,
    required this.query,
    required this.categoryLabel,
    required this.monthLabel,
    required this.status,
    required this.kind,
    required this.onKindChanged,
    required this.onQueryChanged,
    required this.onStatusChanged,
    required this.onCategoryTap,
    required this.onMonthTap,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final String? categoryLabel;
  final String? monthLabel;
  final InvoiceStatus? status;
  final _TransactionKind kind;
  final ValueChanged<_TransactionKind> onKindChanged;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<InvoiceStatus?> onStatusChanged;
  final VoidCallback onCategoryTap;
  final VoidCallback onMonthTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (kind != _TransactionKind.income)
          SearchBar(
            controller: controller,
            hintText: 'Tìm người bán, ký hiệu hoặc ghi chú',
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
        const SizedBox(height: 10),
        SegmentedButton<_TransactionKind>(
          segments: const [
            ButtonSegment(value: _TransactionKind.all, label: Text('Tất cả')),
            ButtonSegment(value: _TransactionKind.income, label: Text('Thu')),
            ButtonSegment(value: _TransactionKind.expense, label: Text('Chi')),
          ],
          selected: {kind},
          onSelectionChanged: (value) => onKindChanged(value.first),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (kind != _TransactionKind.income) ...[
              ChoiceChip(
                label: const Text('Mọi trạng thái'),
                selected: status == null,
                onSelected: (_) => onStatusChanged(null),
              ),
              ChoiceChip(
                label: const Text('Cần kiểm tra'),
                selected: status == InvoiceStatus.needsReview,
                onSelected: (_) => onStatusChanged(InvoiceStatus.needsReview),
              ),
              ChoiceChip(
                label: const Text('Đã xác nhận'),
                selected: status == InvoiceStatus.confirmed,
                onSelected: (_) => onStatusChanged(InvoiceStatus.confirmed),
              ),
              FilterChip(
                avatar: const Icon(Icons.category_outlined, size: 18),
                label: Text(categoryLabel ?? 'Danh mục'),
                selected: categoryLabel != null,
                onSelected: (_) => onCategoryTap(),
              ),
            ],
            FilterChip(
              avatar: const Icon(Icons.calendar_month_outlined, size: 18),
              label: Text(monthLabel ?? 'Tháng'),
              selected: monthLabel != null,
              onSelected: (_) => onMonthTap(),
            ),
            if (onClear != null)
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Xóa lọc'),
              ),
          ],
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
    return EntityListRow(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: finance.income.container,
        child: Icon(Icons.add, color: finance.income.onContainer),
      ),
      title: 'Khoản thu',
      subtitle: AppDateFormat.shortDate(entry.receivedAt),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('+', style: TextStyle(color: finance.income.color)),
          MoneyText(entry.amountMinor, tone: finance.income, compact: true),
        ],
      ),
      semanticLabel:
          'Khoản thu, ${AppDateFormat.shortDate(entry.receivedAt)}, '
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
          '${MoneyFormatter.format(invoice.totalMinor)}, '
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
