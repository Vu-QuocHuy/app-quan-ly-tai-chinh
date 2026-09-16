import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/utils/month_utils.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/theme/finance_colors.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/budget_meter.dart';
import '../../../shared/widgets/category_avatar.dart';
import '../../../shared/widgets/month_selector.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/section_header.dart';
import '../../invoices/domain/invoice_models.dart';
import 'category_management.dart';
import '../../../shared/errors/error_presenter.dart';

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    final budgets = ref.watch(budgetsProvider);
    final dashboard = ref.watch(dashboardProvider);
    final selectedMonth = ref.watch(selectedMonthProvider);
    final monthKey = MonthUtils.key(selectedMonth);
    final dashboardSnapshot = dashboard.asData?.value;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(pinned: true, title: Text('Ngân sách')),
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
                      spentMinor:
                          dashboardSnapshot?.categoryTotals[category.id] ?? 0,
                      onEdit: () =>
                          _editBudget(context, ref, category, budget, monthKey),
                    );
                  },
                ),
              (AsyncError(error: final error), _) ||
              (_, AsyncError(error: final error)) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'Không thể tải ngân sách: ${friendlyMessage(error)}',
                  ),
                ),
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
    required this.spentMinor,
    this.budget,
  });

  final CategoryEntity category;
  final BudgetEntity? budget;
  final int spentMinor;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final finance = context.finance;
    final limit = budget?.limitMinor ?? 0;
    final ratio = limit <= 0 ? 0.0 : spentMinor / limit;
    final progressColor = ratio >= 1
        ? finance.budgetOver.color
        : ratio >= 0.8
        ? finance.budgetWarn.color
        : scheme.primary;
    final remaining = limit - spentMinor;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CategoryAvatar(category: category),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        category.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Sửa ngân sách ${category.name}',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
                if (budget == null)
                  Text(
                    'Chưa đặt hạn mức · Đã chi ${MoneyFormatter.format(spentMinor)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(child: MoneyText(spentMinor)),
                      Text(
                        ' / ${MoneyFormatter.format(limit)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  LinearProgressIndicator(
                    value: ratio.clamp(0.0, 1.0),
                    minHeight: 8,
                    color: progressColor,
                    backgroundColor: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppSpacing.sm),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    remaining >= 0
                        ? 'Còn lại ${MoneyFormatter.format(remaining)}'
                        : 'Vượt ${MoneyFormatter.format(-remaining)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: remaining < 0
                          ? finance.budgetOver.color
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetSummary extends StatelessWidget {
  const _BudgetSummary({required this.snapshot});

  final AsyncValue<DashboardSnapshot> snapshot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
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
              Expanded(
                child: Text(
                  'Chưa thể tải tổng quan: ${friendlyMessage(error)}',
                ),
              ),
            ],
          ),
          data: (data) {
            final hasBudget = data.budgetLimitMinor > 0;
            final remaining = data.budgetLimitMinor - data.totalMinor;
            final isOver = hasBudget && remaining < 0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: 'Tổng quan tháng',
                  subtitle: '${data.invoiceCount} giao dịch đã ghi nhận',
                ),
                const SizedBox(height: AppSpacing.lg),
                MoneyText(
                  data.totalMinor,
                  emphasis: MoneyEmphasis.title,
                  tone: isOver ? context.finance.budgetOver : null,
                ),
                Text(
                  hasBudget
                      ? isOver
                            ? 'Vượt ngân sách ${MoneyFormatter.format(-remaining)}'
                            : 'Còn lại ${MoneyFormatter.format(remaining)}'
                      : 'Chưa đặt tổng hạn mức cho tháng này',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isOver ? scheme.error : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: _BudgetMetric(
                        label: 'Đã chi',
                        value: MoneyFormatter.format(data.totalMinor),
                        icon: Icons.trending_down,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _BudgetMetric(
                        label: 'Hạn mức',
                        value: hasBudget
                            ? MoneyFormatter.format(data.budgetLimitMinor)
                            : 'Chưa đặt',
                        icon: Icons.savings_outlined,
                      ),
                    ),
                  ],
                ),
                if (hasBudget) ...[
                  const SizedBox(height: AppSpacing.lg),
                  BudgetMeter(
                    spentMinor: data.totalMinor,
                    limitMinor: data.budgetLimitMinor,
                    animate: false,
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

class _BudgetMetric extends StatelessWidget {
  const _BudgetMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: scheme.surfaceContainerLow,
        shape: AppShapes.control,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: AppIconSizes.sm, color: scheme.primary),
            const SizedBox(height: AppSpacing.xs),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}
