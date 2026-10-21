import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/utils/month_utils.dart';
import '../../../app/theme/finance_colors.dart';
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
import '../../income/data/income_repository.dart';

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

final dailyIncomeHistoryProvider = StreamProvider.autoDispose
    .family<List<IncomeEntry>, DateTime>((ref, date) {
      final day = DateTime(date.year, date.month, date.day);
      return ref
          .watch(incomeRepositoryProvider)
          .watchAll()
          .map(
            (incomes) => incomes
                .where((income) => DateUtils.isSameDay(income.receivedAt, day))
                .toList(growable: false),
          );
    });

class DailyExpenseHistoryScreen extends ConsumerWidget {
  const DailyExpenseHistoryScreen({required this.date, super.key});

  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(dailyExpenseHistoryProvider(date));
    final incomeHistory = ref.watch(dailyIncomeHistoryProvider(date));
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final incomeCategories =
        ref.watch(incomeCategoriesProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Thu chi ngày ${AppDateFormat.shortDate(date)}',
          maxLines: 3,
        ),
      ),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => AppErrorState(
          error: error,
          stackTrace: stack,
          title: 'Không tải được lịch sử thu chi',
          onRetry: () => ref.invalidate(dailyExpenseHistoryProvider(date)),
        ),
        data: (expenses) => incomeHistory.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => AppErrorState(
            error: error,
            stackTrace: stack,
            title: 'Không tải được lịch sử thu chi',
            onRetry: () => ref.invalidate(dailyIncomeHistoryProvider(date)),
          ),
          data: (incomes) => _buildDailyHistory(
            context,
            expenses: expenses,
            incomes: incomes,
            categories: categories,
            incomeCategories: incomeCategories,
          ),
        ),
      ),
    );
  }

  Widget _buildDailyHistory(
    BuildContext context, {
    required List<InvoiceEntity> expenses,
    required List<IncomeEntry> incomes,
    required List<CategoryEntity> categories,
    required List<CategoryEntity> incomeCategories,
  }) {
    if (expenses.isEmpty && incomes.isEmpty) {
      return const AppEmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Không có giao dịch trong ngày này',
        message: 'Khoản thu và chi của ngày sẽ được hiển thị tại đây.',
      );
    }
    final expenseTotal = expenses.fold<int>(
      0,
      (sum, invoice) => sum + invoice.totalMinor,
    );
    final incomeTotal = incomes.fold<int>(
      0,
      (sum, income) => sum + income.amountMinor,
    );
    final finance = Theme.of(context).extension<AppFinanceColors>()!;
    final net = incomeTotal - expenseTotal;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: AppCard(
              child: Row(
                children: [
                  _DailyTotal(
                    label: 'Thu',
                    amount: incomeTotal,
                    tone: finance.income,
                  ),
                  _DailyTotal(
                    label: 'Chi',
                    amount: expenseTotal,
                    tone: finance.expense,
                  ),
                  _DailyTotal(
                    label: net > 0
                        ? 'Dư'
                        : net < 0
                        ? 'Thiếu'
                        : 'Cân bằng',
                    amount: net.abs(),
                    tone: net > 0
                        ? finance.income
                        : net < 0
                        ? finance.budgetOver
                        : finance.expense,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (incomes.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Khoản thu (${incomes.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: SliverAppListSection(
              itemCount: incomes.length,
              itemBuilder: (context, index) => _DailyIncomeRow(
                income: incomes[index],
                category: findCategory(
                  incomeCategories,
                  incomes[index].categoryId,
                ),
              ),
            ),
          ),
        ],
        if (expenses.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Khoản chi (${expenses.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverAppListSection(
              itemCount: expenses.length,
              itemBuilder: (context, index) => _DailyExpenseRow(
                invoice: expenses[index],
                category: findCategory(categories, expenses[index].categoryId),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DailyTotal extends StatelessWidget {
  const _DailyTotal({
    required this.label,
    required this.amount,
    required this.tone,
  });

  final String label;
  final int amount;
  final FinanceTone tone;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        MoneyText(
          amount,
          emphasis: MoneyEmphasis.caption,
          tone: tone,
          fitToWidth: true,
        ),
      ],
    ),
  );
}

class _DailyIncomeRow extends StatelessWidget {
  const _DailyIncomeRow({required this.income, required this.category});

  final IncomeEntry income;
  final CategoryEntity? category;

  @override
  Widget build(BuildContext context) {
    final finance = Theme.of(context).extension<AppFinanceColors>()!;
    final time = TimeOfDay.fromDateTime(income.receivedAt).format(context);
    final categoryName = category?.name ?? 'Chưa phân loại';
    return EntityListRow(
      leading: CategoryAvatar(category: category),
      title: income.note.isEmpty ? categoryName : income.note,
      subtitle: '$categoryName · ${income.source.label} · $time',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('+'),
          MoneyText(income.amountMinor, tone: finance.income),
        ],
      ),
      semanticLabel:
          '$categoryName, thu ${MoneyFormatter.format(income.amountMinor)}',
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
