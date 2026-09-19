import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/formatting/category_icons.dart';
import '../domain/invoice_models.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/dialogs/confirm_dialog.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../sharing/presentation/invoice_share_dialog.dart';

class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({required this.invoiceId, super.key});

  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final detail = ref.watch(invoiceDetailProvider(invoiceId));
    final invoice = detail.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết hóa đơn'),
        actions: [
          if (invoice != null) ...[
            IconButton(
              tooltip: 'Chỉnh sửa',
              onPressed: () => context.push('/review', extra: invoice),
              icon: const Icon(Icons.edit_outlined),
            ),
            if (ref.watch(sharedBillServiceProvider) != null)
              IconButton(
                tooltip: 'Chia sẻ hóa đơn',
                onPressed: () => _shareInvoice(context, ref, invoice),
                icon: const Icon(Icons.share_outlined),
              ),
            IconButton(
              tooltip: 'Xóa hóa đơn',
              onPressed: () => _deleteInvoice(context, ref, invoice),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ],
      ),
      // Ba trạng thái KHÁC NHAU, không còn gộp thành một câu sai:
      // đang tải / lỗi đọc được kèm retry / hóa đơn không còn tồn tại.
      body: switch (detail) {
        AsyncError(:final error, :final stackTrace) => AppErrorState(
          error: error,
          stackTrace: stackTrace,
          title: 'Không đọc được hóa đơn',
          onRetry: () => ref.invalidate(invoiceDetailProvider(invoiceId)),
        ),
        AsyncLoading() => const Center(child: CircularProgressIndicator()),
        _ when invoice == null => AppEmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Hóa đơn không còn tồn tại',
          message: 'Hóa đơn này có thể đã bị xóa trên thiết bị khác.',
          action: FilledButton.icon(
            onPressed: () => context.go('/invoices'),
            icon: const Icon(Icons.list_alt_outlined),
            label: const Text('Quay lại danh sách'),
          ),
        ),
        _ => _InvoiceDetail(
          invoice: invoice,
          category: _findCategory(categories, invoice.categoryId),
        ),
      },
    );
  }

  Future<void> _shareInvoice(
    BuildContext context,
    WidgetRef ref,
    InvoiceEntity invoice,
  ) async {
    final shared = await showInvoiceShareDialog(context, invoice);
    if (shared != true || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã tạo chia sẻ hóa đơn trên cloud.')),
    );
    ref.invalidate(directBillSharesProvider);
    ref.invalidate(expenseGroupsProvider);
  }

  Future<void> _deleteInvoice(
    BuildContext context,
    WidgetRef ref,
    InvoiceEntity invoice,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Xóa hóa đơn?',
      message:
          'Hóa đơn của ${invoice.sellerName} sẽ bị xóa khỏi thiết bị. '
          'Thao tác này không thể hoàn tác.',
      confirmLabel: 'Xóa',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(invoiceRepositoryProvider).deleteInvoice(invoice.id);
      if (context.mounted) context.go('/invoices');
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể xóa hóa đơn: ${friendlyMessage(error)}'),
        ),
      );
    }
  }
}

class _InvoiceDetail extends StatelessWidget {
  const _InvoiceDetail({required this.invoice, this.category});

  final InvoiceEntity invoice;
  final CategoryEntity? category;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invoice.sellerName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (invoice.sellerTaxCode != null)
                  Text('MST: ${invoice.sellerTaxCode}'),
                if (invoice.invoiceNumber != null)
                  Text('Số hóa đơn: ${invoice.invoiceNumber}'),
                if (invoice.issuedAt != null)
                  Text(
                    'Ngày: ${DateFormat('dd/MM/yyyy').format(invoice.issuedAt!)}',
                  ),
                if (category != null) ...[
                  const SizedBox(height: 12),
                  Chip(
                    avatar: Icon(
                      categoryIconFor(category!.iconName),
                      size: 18,
                      color: Color(category!.colorValue),
                    ),
                    label: Text(category!.name),
                  ),
                ],
                if (invoice.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: invoice.tags
                        .map(
                          (tag) => Chip(
                            avatar: const Icon(Icons.sell_outlined, size: 16),
                            label: Text(tag),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
                if (invoice.notes case final notes?) ...[
                  const SizedBox(height: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.notes_outlined, size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Text(notes)),
                        ],
                      ),
                    ),
                  ),
                ],
                const Divider(height: 32),
                _MoneyRow(label: 'Trước thuế', value: invoice.subtotalMinor),
                _MoneyRow(label: 'Thuế', value: invoice.taxMinor),
                const Divider(),
                _MoneyRow(
                  label: 'Tổng thanh toán',
                  value: invoice.totalMinor,
                  emphasized: true,
                ),
              ],
            ),
          ),
        ),
        if (invoice.lines.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Hàng hóa, dịch vụ',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Card(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: invoice.lines.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final line = invoice.lines[index];
                return ListTile(
                  title: Text(line.description),
                  subtitle: line.quantity == null
                      ? null
                      : Text('SL: ${line.quantity}'),
                  trailing: Text(MoneyFormatter.format(line.totalMinor)),
                );
              },
            ),
          ),
        ],
        if (invoice.evidence.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Nguồn dữ liệu', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: invoice.evidence
                    .map(
                      (item) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.fieldName),
                        subtitle: Text(item.source.name.toUpperCase()),
                        trailing: Text('${(item.confidence * 100).round()}%'),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

CategoryEntity? _findCategory(
  List<CategoryEntity> categories,
  String? categoryId,
) {
  if (categoryId == null) return null;
  for (final category in categories) {
    if (category.id == categoryId) return category;
  }
  return null;
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final int value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleLarge
        : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(MoneyFormatter.format(value), style: style),
        ],
      ),
    );
  }
}
