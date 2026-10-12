import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/utils/month_utils.dart';
import '../../../shared/formatting/app_date_format.dart';
import '../../../shared/formatting/category_lookup.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_list_section.dart';
import '../../../shared/widgets/category_avatar.dart';
import '../../../shared/widgets/entity_list_row.dart';
import '../../../shared/widgets/money_text.dart';
import '../domain/invoice_filters.dart';
import '../domain/invoice_models.dart';

final dailyExpenseHistoryProvider = StreamProvider.autoDispose
    .family<List<InvoiceEntity>, DateTime>((ref, date) {
      final day = DateTime(date.year, date.month, date.day);
      return ref
          .watch(invoiceRepositoryProvider)
          .watchInvoiceSummaries(
            filter: InvoiceFilter(
              monthKey: MonthUtils.key(day),
              status: InvoiceStatus.confirmed,
            ),
          )
          .map((invoices) {
            final items = invoices
                .where((invoice) {
                  final invoiceDate = invoice.issuedAt ?? invoice.createdAt;
                  return DateUtils.isSameDay(invoiceDate, day);
                })
                .toList(growable: false);
            items.sort((left, right) {
              final leftDate = left.issuedAt ?? left.createdAt;
              final rightDate = right.issuedAt ?? right.createdAt;
              return rightDate.compareTo(leftDate);
            });
            return items;
          });
    });

class DailyExpenseHistoryScreen extends ConsumerWidget {
  const DailyExpenseHistoryScreen({required this.date, super.key});

  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(dailyExpenseHistoryProvider(date));
    final categories = ref.watch(categoriesProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text('Chi tiêu ngày ${AppDateFormat.shortDate(date)}'),
      ),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => AppErrorState(
          error: error,
          stackTrace: stack,
          title: 'Không tải được lịch sử chi tiêu',
          onRetry: () => ref.invalidate(dailyExpenseHistoryProvider(date)),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const AppEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Không có khoản chi trong ngày này',
              message: 'Các khoản chi đã xác nhận sẽ được hiển thị ở đây.',
            );
          }

          final total = items.fold<int>(
            0,
            (sum, invoice) => sum + invoice.totalMinor,
          );
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: AppCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${items.length} khoản chi',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const Text('−'),
                        MoneyText(total, emphasis: MoneyEmphasis.title),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverAppListSection(
                  itemCount: items.length,
                  itemBuilder: (context, index) => _DailyExpenseRow(
                    invoice: items[index],
                    category: findCategory(categories, items[index].categoryId),
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

class _DailyExpenseRow extends StatelessWidget {
  const _DailyExpenseRow({required this.invoice, required this.category});

  final InvoiceEntity invoice;
  final CategoryEntity? category;

  @override
  Widget build(BuildContext context) {
    final date = invoice.issuedAt ?? invoice.createdAt;
    final seller = invoice.sellerName.trim().isEmpty
        ? 'Chưa có tên người bán'
        : invoice.sellerName;
    final categoryName = category?.name ?? 'Chưa phân loại';
    final time = TimeOfDay.fromDateTime(date).format(context);

    return EntityListRow(
      leading: CategoryAvatar(category: category),
      title: seller,
      subtitle: '$categoryName · $time',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [const Text('−'), MoneyText(invoice.totalMinor)],
      ),
      onTap: () => context.push('/invoices/${invoice.id}'),
      semanticLabel:
          '$seller, $categoryName, $time, chi '
          '${MoneyFormatter.format(invoice.totalMinor)}',
    );
  }
}
