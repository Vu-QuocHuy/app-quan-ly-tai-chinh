import '../../../shared/widgets/finmi_page_header.dart';
import '../../../shared/widgets/finmi_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/utils/month_utils.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/theme/finance_colors.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/category_avatar.dart';
import '../../../shared/widgets/month_selector.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/dialogs/confirm_dialog.dart';
import '../../invoices/domain/invoice_models.dart';
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
          FinmiSliverHeader(
            title: 'Hạn mức ngân sách',
            actions: [
              FinmiHeaderAction(
                tooltip: 'Quản lý danh mục',
                onPressed: () => context.push('/categories'),
                icon: Icons.category_outlined,
              ),
            ],
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: MonthSelector(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: _BudgetSummary(
                snapshot: dashboard,
                categories: categories.valueOrNull ?? const [],
                budgets: budgets.valueOrNull ?? const [],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Không thể tải ngân sách: ${friendlyMessage(error)}',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () {
                          ref.invalidate(categoriesProvider);
                          ref.invalidate(budgetsProvider);
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
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
    final initialValue = current?.limitMinor.toString() ?? '';
    var inputValue = initialValue;
    final result = await showDialog<_BudgetDialogResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Ngân sách ${category.name}', maxLines: 3),
        content: FinmiTextField(
          initialValue: initialValue,
          onChanged: (text) => inputValue = text,
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
              onPressed: () async {
                final confirmed = await showConfirmDialog(
                  context,
                  title: 'Xóa hạn mức ngân sách?',
                  message: 'Hạn mức cho danh mục “${category.name}” sẽ bị xóa.',
                  confirmLabel: 'Xóa hạn mức',
                  destructive: true,
                );
                if (confirmed && context.mounted) {
                  Navigator.pop(context, const _BudgetDialogResult.delete());
                }
              },
              child: Text(
                'Xóa',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          TextButton(
            onPressed: () async {
              if (inputValue != initialValue) {
                final discard = await showDiscardChangesDialog(context);
                if (!discard || !context.mounted) return;
              }
              Navigator.pop(context);
            },
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = MoneyFormatter.tryParse(inputValue);
              if (parsed == null || parsed < 0) return;
              Navigator.pop(context, _BudgetDialogResult.value(parsed));
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
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
      onTap: onEdit,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        children: [
          CategoryAvatar(category: category, radius: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  budget == null
                      ? 'Chưa đặt hạn mức · Đã chi ${MoneyFormatter.format(spentMinor)}'
                      : 'Hạn mức: ${MoneyFormatter.format(limit)} · Đã chi ${MoneyFormatter.format(spentMinor)} (${(ratio * 100).round()}%)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (budget != null) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: ratio.clamp(0, 1),
                    minHeight: 5,
                    color: progressColor,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                  const SizedBox(height: 4),
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
          IconButton(
            tooltip: 'Sửa ngân sách ${category.name}',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
        ],
      ),
    );
  }
}

class _BudgetSummary extends StatefulWidget {
  const _BudgetSummary({
    required this.snapshot,
    required this.categories,
    required this.budgets,
  });

  final AsyncValue<DashboardSnapshot> snapshot;
  final List<CategoryEntity> categories;
  final List<BudgetEntity> budgets;

  @override
  State<_BudgetSummary> createState() => _BudgetSummaryState();
}

class _BudgetSummaryState extends State<_BudgetSummary> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: widget.snapshot.when(
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Chi tiêu tháng này',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      tooltip: _expanded
                          ? 'Ẩn danh mục vượt hạn mức'
                          : 'Xem danh mục vượt hạn mức',
                      onPressed: () => setState(() => _expanded = !_expanded),
                      icon: Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                      ),
                      isSelected: _expanded,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                MoneyText(
                  data.totalMinor,
                  emphasis: MoneyEmphasis.title,
                  tone: isOver
                      ? context.finance.budgetOver
                      : context.finance.expense,
                ),
                const SizedBox(height: 6),
                Text(
                  hasBudget
                      ? 'Hạn mức: ${MoneyFormatter.format(data.budgetLimitMinor)} · Đã dùng ${(data.totalMinor / data.budgetLimitMinor * 100).round()}% · ${isOver ? 'Vượt' : 'Còn lại'} ${MoneyFormatter.format(remaining.abs())}'
                      : 'Chưa đặt tổng hạn mức cho tháng này',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isOver ? scheme.error : scheme.onSurfaceVariant,
                  ),
                ),
                if (hasBudget) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: (data.totalMinor / data.budgetLimitMinor).clamp(
                      0,
                      1,
                    ),
                    minHeight: 6,
                    color: isOver ? scheme.error : scheme.primary,
                    backgroundColor: scheme.surfaceContainerHighest,
                    semanticsLabel: isOver ? 'Vượt hạn mức' : 'Trong hạn mức',
                  ),
                ],
                if (_expanded) ...[
                  const Divider(height: 24),
                  Text(
                    'Danh mục vượt hạn mức',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  if (!widget.budgets.any(
                    (b) =>
                        (data.categoryTotals[b.categoryId] ?? 0) > b.limitMinor,
                  ))
                    const Text('Chưa có danh mục nào vượt hạn mức.'),
                  for (final budget in widget.budgets.where(
                    (b) =>
                        (data.categoryTotals[b.categoryId] ?? 0) > b.limitMinor,
                  ))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CategoryAvatar(
                            category: widget.categories
                                .where((c) => c.id == budget.categoryId)
                                .firstOrNull,
                            radius: 16,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.categories
                                          .where(
                                            (c) => c.id == budget.categoryId,
                                          )
                                          .firstOrNull
                                          ?.name ??
                                      'Khác',
                                ),
                                Text(
                                  'Vượt ${MoneyFormatter.format((data.categoryTotals[budget.categoryId] ?? 0) - budget.limitMinor)}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: scheme.error),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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
