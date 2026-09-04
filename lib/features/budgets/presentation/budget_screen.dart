import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/utils/month_utils.dart';
import '../../../shared/widgets/month_selector.dart';
import '../../invoices/domain/invoice_models.dart';
import 'category_management.dart';

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    final budgets = ref.watch(budgetsProvider);
    final dashboard = ref.watch(dashboardProvider);
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
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _BudgetSummary(snapshot: dashboard),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
          if (categories case AsyncData(value: final categoryItems))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
                child: CategoryManagement(categories: categoryItems),
              ),
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
          child: Icon(categoryIcon(category.iconName), color: color),
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

class _BudgetSummary extends StatelessWidget {
  const _BudgetSummary({required this.snapshot});

  final AsyncValue<DashboardSnapshot> snapshot;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: snapshot.when(
          loading: () => const SizedBox(
            height: 76,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Row(
            children: [
              Icon(
                Icons.info_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('Chưa thể tải tổng quan: $error')),
            ],
          ),
          data: (data) {
            final hasBudget = data.budgetLimitMinor > 0;
            final progress = data.budgetProgress.clamp(0.0, 1.0);
            final remaining = data.budgetLimitMinor - data.totalMinor;
            final isOver = hasBudget && remaining < 0;
            final accent = isOver
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Tổng quan tháng',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${data.invoiceCount} giao dịch',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  MoneyFormatter.format(data.totalMinor),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasBudget
                      ? isOver
                            ? 'Vượt ngân sách ${MoneyFormatter.format(-remaining)}'
                            : 'Còn lại ${MoneyFormatter.format(remaining)}'
                      : 'Chưa đặt tổng hạn mức cho tháng này',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isOver ? Theme.of(context).colorScheme.error : null,
                  ),
                ),
                if (hasBudget) ...[
                  const SizedBox(height: 14),
                  LinearProgressIndicator(
                    value: progress,
                    color: accent,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Hạn mức ${MoneyFormatter.format(data.budgetLimitMinor)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
