import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../data/supabase_invoice_attachment_store.dart';
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
        title: Text(
          invoice?.sourceType == InvoiceSourceType.manual
              ? 'Chi tiết khoản chi'
              : 'Chi tiết hóa đơn',
        ),
        actions: [
          if (invoice != null) ...[
            if (invoice.sourceType != InvoiceSourceType.manual)
              IconButton(
                tooltip: 'Chứng từ gốc',
                onPressed: () =>
                    context.push('/invoices/$invoiceId/attachments'),
                icon: const Icon(Icons.attach_file_outlined),
              ),
            IconButton(
              tooltip: 'Chỉnh sửa',
              onPressed: () => context.push('/review', extra: invoice),
              icon: const Icon(Icons.edit_outlined),
            ),
            if (ref.watch(sharedBillServiceProvider) != null)
              IconButton(
                tooltip: invoice.sourceType == InvoiceSourceType.manual
                    ? 'Chia sẻ khoản chi'
                    : 'Chia sẻ hóa đơn',
                onPressed: () => _shareInvoice(context, ref, invoice),
                icon: const Icon(Icons.share_outlined),
              ),
            IconButton(
              tooltip: invoice.sourceType == InvoiceSourceType.manual
                  ? 'Xóa khoản chi'
                  : 'Xóa hóa đơn',
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
          title: 'Không đọc được giao dịch',
          onRetry: () => ref.invalidate(invoiceDetailProvider(invoiceId)),
        ),
        AsyncLoading() => const Center(child: CircularProgressIndicator()),
        _ when invoice == null => AppEmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Giao dịch không còn tồn tại',
          message: 'Giao dịch này có thể đã bị xóa trên thiết bị khác.',
          action: FilledButton.icon(
            onPressed: () => context.go('/invoices'),
            icon: const Icon(Icons.list_alt_outlined),
            label: const Text('Quay lại danh sách'),
          ),
        ),
        _ => _InvoiceDetail(
          invoice: invoice,
          categories: categories,
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
      title: invoice.sourceType == InvoiceSourceType.manual
          ? 'Xóa khoản chi?'
          : 'Xóa hóa đơn?',
      message:
          '${invoice.sourceType == InvoiceSourceType.manual ? 'Khoản chi' : 'Hóa đơn'} của ${invoice.sellerName} sẽ bị xóa khỏi thiết bị. '
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
          content: Text(
            'Không thể xóa ${invoice.sourceType == InvoiceSourceType.manual ? 'khoản chi' : 'hóa đơn'}: ${friendlyMessage(error)}',
          ),
        ),
      );
    }
  }
}

class _InvoiceDetail extends StatelessWidget {
  const _InvoiceDetail({
    required this.invoice,
    required this.categories,
    this.category,
  });

  final InvoiceEntity invoice;
  final List<CategoryEntity> categories;
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
                if (invoice.invoiceSymbol != null)
                  Text('Ký hiệu hóa đơn: ${invoice.invoiceSymbol}'),
                if (invoice.issuedAt != null || category != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (invoice.issuedAt != null)
                        Expanded(
                          child: Text(
                            'Ngày: ${DateFormat('dd/MM/yyyy').format(invoice.issuedAt!)}',
                          ),
                        ),
                      if (category != null) ...[
                        if (invoice.issuedAt != null) const SizedBox(width: 8),
                        Flexible(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Chip(
                              visualDensity: VisualDensity.compact,
                              avatar: Icon(
                                categoryIconFor(category!.iconName),
                                size: 18,
                                color: Color(category!.colorValue),
                              ),
                              label: Text(
                                category!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
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
                if (invoice.sourceType == InvoiceSourceType.manual)
                  _MoneyRow(
                    label: 'Số tiền',
                    value: invoice.totalMinor,
                    emphasized: true,
                  )
                else ...[
                  _MoneyRow(label: 'Trước thuế', value: invoice.subtotalMinor),
                  _MoneyRow(label: 'Thuế', value: invoice.taxMinor),
                  if (invoice.discountMinor > 0)
                    _MoneyRow(label: 'Giảm giá', value: -invoice.discountMinor),
                  const Divider(),
                  _MoneyRow(
                    label: 'Tổng thanh toán',
                    value: invoice.totalMinor,
                    emphasized: true,
                  ),
                ],
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
                final lineCategory = _findCategory(categories, line.categoryId);
                Widget metric(
                  String label,
                  String value,
                  Alignment alignment,
                ) => Expanded(
                  child: Column(
                    crossAxisAlignment: alignment.x < 0
                        ? CrossAxisAlignment.start
                        : alignment.x > 0
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: alignment,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: alignment,
                          child: Text(
                            value,
                            maxLines: 1,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ),
                    ],
                  ),
                );

                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              line.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          if (lineCategory != null) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Chip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: Icon(
                                    categoryIconFor(lineCategory.iconName),
                                    size: 16,
                                    color: Color(lineCategory.colorValue),
                                  ),
                                  label: Text(
                                    lineCategory.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          metric(
                            'Số lượng',
                            line.quantity?.toString() ?? '—',
                            Alignment.centerLeft,
                          ),
                          const SizedBox(width: 8),
                          metric(
                            'Đơn giá',
                            line.unitPriceMinor == null
                                ? '—'
                                : MoneyFormatter.format(line.unitPriceMinor!),
                            Alignment.center,
                          ),
                          const SizedBox(width: 8),
                          metric(
                            'Thành tiền',
                            MoneyFormatter.format(line.totalMinor),
                            Alignment.centerRight,
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
        if (invoice.sourceType == InvoiceSourceType.imageOcr)
          _OriginalReceiptPreview(invoiceId: invoice.id),
      ],
    );
  }
}

final _attachmentSignedUrlProvider = FutureProvider.autoDispose
    .family<Uri, InvoiceAttachment>((ref, attachment) {
      final store = ref.watch(invoiceAttachmentStoreProvider);
      if (store == null) throw StateError('Supabase chưa được cấu hình.');
      return store.signedUrl(attachment);
    });

class _OriginalReceiptPreview extends ConsumerWidget {
  const _OriginalReceiptPreview({required this.invoiceId});

  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachments = ref.watch(invoiceAttachmentsProvider(invoiceId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text('Ảnh hóa đơn', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        attachments.when(
          loading: () => const Card(
            child: SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (error, _) => Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_off_outlined),
              title: const Text('Không tải được ảnh hóa đơn'),
              subtitle: Text(friendlyMessage(error)),
              trailing: IconButton(
                tooltip: 'Thử tải lại',
                onPressed: () =>
                    ref.invalidate(invoiceAttachmentsProvider(invoiceId)),
                icon: const Icon(Icons.refresh),
              ),
            ),
          ),
          data: (items) {
            InvoiceAttachment? image;
            for (final item in items) {
              if (item.contentType.startsWith('image/')) {
                image = item;
                break;
              }
            }
            if (image == null) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Ảnh gốc chưa được lưu'),
                  subtitle: const Text('Mở chứng từ gốc để thêm ảnh hóa đơn.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/invoices/$invoiceId/attachments'),
                ),
              );
            }
            return _OriginalReceiptImage(
              invoiceId: invoiceId,
              attachment: image,
            );
          },
        ),
      ],
    );
  }
}

class _OriginalReceiptImage extends ConsumerWidget {
  const _OriginalReceiptImage({
    required this.invoiceId,
    required this.attachment,
  });

  final String invoiceId;
  final InvoiceAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(_attachmentSignedUrlProvider(attachment));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: url.when(
        loading: () => const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => ListTile(
          leading: const Icon(Icons.broken_image_outlined),
          title: const Text('Không mở được ảnh gốc'),
          subtitle: Text(friendlyMessage(error)),
          onTap: () => context.push('/invoices/$invoiceId/attachments'),
        ),
        data: (uri) => InkWell(
          onTap: () => context.push('/invoices/$invoiceId/attachments'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.network(
                uri.toString(),
                height: 240,
                fit: BoxFit.contain,
                cacheWidth: 1200,
                semanticLabel: 'Ảnh hóa đơn gốc ${attachment.fileName}',
                errorBuilder: (_, _, _) => const SizedBox(
                  height: 200,
                  child: Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
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
