import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/utils/month_utils.dart';
import '../../../shared/widgets/month_selector.dart';
import '../../invoices/domain/invoice_models.dart';

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    final budgets = ref.watch(budgetsProvider);
    final selectedMonth = ref.watch(selectedMonthProvider);
    final monthKey = MonthUtils.key(selectedMonth);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('Ngân sách')),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: MonthSelector(),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
            sliver: switch ((categories, budgets)) {
              (
                AsyncData(value: final categoryItems),
                AsyncData(value: final budgetItems),
              ) =>
                SliverList.separated(
                  itemCount: categoryItems.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final category = categoryItems[index];
                    final budget = budgetItems
                        .where((item) => item.categoryId == category.id)
                        .firstOrNull;
                    return _BudgetTile(
                      category: category,
                      budget: budget,
                      onEdit: () =>
                          _editBudget(context, ref, category, budget, monthKey),
                    );
                  },
                ),
              (AsyncError(error: final error), _) ||
              (_, AsyncError(error: final error)) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Không thể tải ngân sách: $error')),
              ),
              _ => const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              ),
            },
          ),
        ],
      ),
    );
  }

  Future<void> _editBudget(
    BuildContext context,
    WidgetRef ref,
    CategoryEntity category,
    BudgetEntity? current,
    String monthKey,
  ) async {
    final controller = TextEditingController(
      text: current == null ? '' : current.limitMinor.toString(),
    );
    final result = await showDialog<_BudgetDialogResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Ngân sách ${category.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Hạn mức tháng',
            suffixText: '₫',
            helperText: 'Nhập số tiền không có phần thập phân.',
          ),
        ),
        actions: [
          if (current != null)
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, const _BudgetDialogResult.delete()),
              child: Text(
                'Xóa',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = MoneyFormatter.tryParse(controller.text);
              if (parsed == null || parsed < 0) return;
              Navigator.pop(context, _BudgetDialogResult.value(parsed));
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    if (result.delete && current != null) {
      await ref.read(invoiceRepositoryProvider).deleteBudget(current.id);
      return;
    }
    final value = result.value;
    if (value == null) return;
    await ref
        .read(invoiceRepositoryProvider)
        .saveBudget(
          BudgetEntity(
            id: '$monthKey-${category.id}',
            monthKey: monthKey,
            categoryId: category.id,
            limitMinor: value,
          ),
        );
  }
}

class _BudgetDialogResult {
  const _BudgetDialogResult.value(this.value) : delete = false;
  const _BudgetDialogResult.delete() : value = null, delete = true;

  final int? value;
  final bool delete;
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({
    required this.category,
    required this.onEdit,
    this.budget,
  });

  final CategoryEntity category;
  final BudgetEntity? budget;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.colorValue);
    return Card(
      child: ListTile(
        minTileHeight: 72,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          child: Icon(Icons.savings_outlined, color: color),
        ),
        title: Text(category.name),
        subtitle: Text(
          budget == null
              ? 'Chưa đặt hạn mức'
              : MoneyFormatter.format(budget!.limitMinor),
        ),
        trailing: IconButton(
          tooltip: 'Sửa ngân sách ${category.name}',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
        ),
      ),
    );
  }
}
