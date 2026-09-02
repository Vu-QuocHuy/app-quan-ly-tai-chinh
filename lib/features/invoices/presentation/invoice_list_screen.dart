import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/utils/month_utils.dart';
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
  InvoiceSourceType? _sourceType;
  DateTime? _month;
  Timer? _searchDebounce;
  int _limit = 50;

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
      sourceType: _sourceType,
    );
    final invoices = ref.watch(
      filteredInvoiceSummariesProvider(
        InvoiceListQuery(filter: filter, limit: _limit + 1),
      ),
    );
    final categories = ref.watch(categoriesProvider).value ?? const [];
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('Hóa đơn')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _FilterHeader(
                controller: _searchController,
                query: _query,
                categoryLabel: _categoryLabel(categories),
                sourceLabel: _sourceType == null
                    ? null
                    : _sourceLabel(_sourceType!),
                monthLabel: _month == null ? null : MonthUtils.label(_month!),
                status: _status,
                onQueryChanged: _onQueryChanged,
                onStatusChanged: (value) =>
                    _changeFilter(() => _status = value),
                onCategoryTap: () => _selectCategory(categories),
                onSourceTap: _selectSource,
                onMonthTap: _selectMonth,
                onClear: filter.hasActiveFilters ? _clearFilters : null,
              ),
            ),
          ),
          invoices.when(
            loading: () => const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stack) => SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('Không thể tải hóa đơn: $error')),
            ),
            data: (items) {
              final hasMore = items.length > _limit;
              final visible = hasMore
                  ? items.take(_limit).toList(growable: false)
                  : items;
              if (visible.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: _InvoiceEmptyState(
                    filtered: filter.hasActiveFilters,
                    query: _query,
                    onClear: filter.hasActiveFilters ? _clearFilters : null,
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
                sliver: SliverList.separated(
                  itemCount: visible.length + (hasMore ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (index == visible.length) {
                      return Center(
                        child: OutlinedButton.icon(
                          onPressed: () => setState(() => _limit += 50),
                          icon: const Icon(Icons.expand_more),
                          label: const Text('Tải thêm hóa đơn'),
                        ),
                      );
                    }
                    return _InvoiceCard(invoice: visible[index]);
                  },
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
      _sourceType = null;
      _month = null;
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

  Future<void> _selectSource() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const ListTile(
              title: Text('Lọc theo nguồn'),
              subtitle: Text('Chọn cách hóa đơn được nhập vào ứng dụng'),
            ),
            ListTile(
              leading: const Icon(Icons.all_inclusive),
              title: const Text('Tất cả nguồn'),
              selected: _sourceType == null,
              onTap: () => Navigator.pop(sheetContext, ''),
            ),
            ...InvoiceSourceType.values.map(
              (source) => ListTile(
                leading: Icon(_sourceIcon(source)),
                title: Text(_sourceLabel(source)),
                selected: source == _sourceType,
                onTap: () => Navigator.pop(sheetContext, source.name),
              ),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    _changeFilter(
      () => _sourceType = result.isEmpty
          ? null
          : InvoiceSourceType.values.byName(result),
    );
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

class _FilterHeader extends StatelessWidget {
  const _FilterHeader({
    required this.controller,
    required this.query,
    required this.categoryLabel,
    required this.sourceLabel,
    required this.monthLabel,
    required this.status,
    required this.onQueryChanged,
    required this.onStatusChanged,
    required this.onCategoryTap,
    required this.onSourceTap,
    required this.onMonthTap,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final String? categoryLabel;
  final String? sourceLabel;
  final String? monthLabel;
  final InvoiceStatus? status;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<InvoiceStatus?> onStatusChanged;
  final VoidCallback onCategoryTap;
  final VoidCallback onSourceTap;
  final VoidCallback onMonthTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SearchBar(
          controller: controller,
          hintText: 'Tìm người bán, MST hoặc số hóa đơn',
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Tất cả'),
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
            FilterChip(
              avatar: const Icon(Icons.input_outlined, size: 18),
              label: Text(sourceLabel ?? 'Nguồn'),
              selected: sourceLabel != null,
              onSelected: (_) => onSourceTap(),
            ),
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

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice});

  final InvoiceEntity invoice;

  @override
  Widget build(BuildContext context) {
    final date = invoice.issuedAt ?? invoice.createdAt;
    final needsReview = invoice.status == InvoiceStatus.needsReview;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push('/invoices/${invoice.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                child: Icon(_sourceIcon(invoice.sourceType)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.sellerName.isEmpty
                          ? 'Chưa có tên người bán'
                          : invoice.sellerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${DateFormat('dd/MM/yyyy').format(date)} · ${_sourceLabel(invoice.sourceType)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (needsReview) ...[
                      const SizedBox(height: 8),
                      const _ReviewBadge(),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                MoneyFormatter.format(invoice.totalMinor),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewBadge extends StatelessWidget {
  const _ReviewBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Hóa đơn cần kiểm tra',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            'Cần kiểm tra',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onErrorContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _InvoiceEmptyState extends StatelessWidget {
  const _InvoiceEmptyState({
    required this.filtered,
    required this.query,
    this.onClear,
  });

  final bool filtered;
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
            Icons.receipt_long_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 20),
          Text(
            filtered ? 'Không tìm thấy hóa đơn' : 'Chưa có hóa đơn',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            filtered
                ? (query.trim().isEmpty
                      ? 'Thử bỏ bớt bộ lọc để xem thêm kết quả.'
                      : 'Không có kết quả cho “${query.trim()}”. Hãy thử từ khóa khác.')
                : 'Nhấn “Thêm hóa đơn” để nhập XML, chụp ảnh hoặc nhập thủ công.',
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
  InvoiceSourceType.qr => Icons.qr_code,
  InvoiceSourceType.imageOcr => Icons.document_scanner_outlined,
  InvoiceSourceType.manual => Icons.edit_note,
};

String _sourceLabel(InvoiceSourceType source) => switch (source) {
  InvoiceSourceType.xml => 'XML',
  InvoiceSourceType.pdfText => 'PDF',
  InvoiceSourceType.qr => 'QR',
  InvoiceSourceType.imageOcr => 'Ảnh OCR',
  InvoiceSourceType.manual => 'Thủ công',
};
