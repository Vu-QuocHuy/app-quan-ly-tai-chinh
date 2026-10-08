import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../invoices/domain/invoice_filters.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../../shared/formatting/app_date_format.dart';
import '../../../shared/formatting/category_lookup.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_list_section.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/category_avatar.dart';
import '../../../shared/widgets/entity_list_row.dart';
import '../../../shared/widgets/money_text.dart';

final qrPaymentHistoryProvider =
    StreamProvider.autoDispose<List<InvoiceEntity>>((ref) {
      final repository = ref.watch(invoiceRepositoryProvider);
      return repository
          .watchInvoiceSummaries(
            filter: const InvoiceFilter(
              query: 'qr-payment',
              status: InvoiceStatus.confirmed,
              sourceType: InvoiceSourceType.manual,
            ),
          )
          .map((items) {
            final payments = items
                .where(
                  (invoice) =>
                      invoice.status == InvoiceStatus.confirmed &&
                      invoice.tags.contains('qr-payment'),
                )
                .toList(growable: false);
            return payments..sort((left, right) {
              final leftDate =
                  left.confirmedAt ?? left.issuedAt ?? left.createdAt;
              final rightDate =
                  right.confirmedAt ?? right.issuedAt ?? right.createdAt;
              final byDate = rightDate.compareTo(leftDate);
              return byDate != 0 ? byDate : right.id.compareTo(left.id);
            });
          });
    });

class QrPaymentHistoryScreen extends ConsumerWidget {
  const QrPaymentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(qrPaymentHistoryProvider);
    final categories = ref.watch(categoriesProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử thanh toán QR')),
      body: history.when(
        loading: () => const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: SkeletonListRows(count: 6),
        ),
        error: (error, stack) => AppErrorState(
          error: error,
          stackTrace: stack,
          title: 'Không tải được lịch sử thanh toán',
          onRetry: () => ref.invalidate(qrPaymentHistoryProvider),
        ),
        data: (payments) {
          if (payments.isEmpty) {
            return AppEmptyState(
              icon: Icons.qr_code_2_outlined,
              title: 'Chưa có thanh toán QR',
              message:
                  'Khoản chi sẽ xuất hiện ở đây sau khi bạn xác nhận đã thanh toán.',
              action: FilledButton.icon(
                onPressed: () => context.go('/qr-payment'),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Quét mã QR'),
              ),
            );
          }

          final totalMinor = payments.fold<int>(
            0,
            (total, payment) => total + payment.totalMinor,
          );
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${payments.length} khoản đã xác nhận',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          MoneyText(totalMinor, emphasis: MoneyEmphasis.title),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Được ghi nhận sau khi bạn xác nhận đã thanh toán trong app.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverAppListSection(
                  itemCount: payments.length,
                  itemBuilder: (context, index) => _QrPaymentRow(
                    invoice: payments[index],
                    category: findCategory(
                      categories,
                      payments[index].categoryId,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _QrPaymentRow extends StatelessWidget {
  const _QrPaymentRow({required this.invoice, required this.category});

  final InvoiceEntity invoice;
  final CategoryEntity? category;

  @override
  Widget build(BuildContext context) {
    final date = invoice.confirmedAt ?? invoice.issuedAt ?? invoice.createdAt;
    final seller = invoice.sellerName.trim().isEmpty
        ? 'Chuyển khoản QR'
        : invoice.sellerName;
    final categoryName = category?.name ?? 'Chưa phân loại';
    final memo = invoice.notes?.trim();
    final dateLabel =
        '${AppDateFormat.shortDate(date)} · ${TimeOfDay.fromDateTime(date).format(context)}';

    return EntityListRow(
      leading: CategoryAvatar(category: category),
      title: seller,
      subtitle:
          '$categoryName · $dateLabel${memo?.isNotEmpty == true ? '\n$memo' : ''}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MoneyText(invoice.totalMinor),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Thanh toán QR đã xác nhận',
            child: Icon(
              Icons.qr_code_2,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      onTap: () => context.push('/invoices/${invoice.id}'),
      semanticLabel:
          'Thanh toán QR đã xác nhận cho $seller, $categoryName, $dateLabel, '
          '${MoneyFormatter.format(invoice.totalMinor)}'
          '${memo?.isNotEmpty == true ? ', nội dung $memo' : ''}',
    );
  }
}
