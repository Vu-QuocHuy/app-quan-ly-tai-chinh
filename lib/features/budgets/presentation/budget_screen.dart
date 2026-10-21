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
import '../../../shared/widgets/section_header.dart';
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
          SliverAppBar(
            pinned: true,
            title: const Text('Ngân sách'),
            actions: [
              IconButton(
                tooltip: 'Quản lý danh mục',
                onPressed: () => context.push('/categories'),
                icon: const Icon(Icons.category_outlined),
              ),
            ],
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: MonthSelector(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: AppCard(
                padding: EdgeInsets.zero,
                onTap: () => context.push('/plans'),
                child: const ListTile(
                  leading: Icon(Icons.event_repeat),
                  title: Text('Khoản chi cố định'),
                  trailing: Icon(Icons.chevron_right),
                ),
              ),
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
        title: Text('Ngân sách ${category.name}'),
        content: TextFormField(
          initialValue: initialValue,
          onChanged: (text) => inputValue = text,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Hạn mức tháng',
            suffixText: '₫',
            helperText: 'Để trống hoặc nhập 0 để không giới hạn.',
          ),
        ),
        actions: [
          if (current != null)
            TextButton(
              onPressed: () async {
                final confirmed = await showConfirmDialog(
                  context,
                  title: 'Xóa hạn mức ngân sách?',
                  message:
                      'Danh mục “${category.name}” sẽ trở về không giới hạn.',
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
              if (inputValue.trim().isEmpty) {
                Navigator.pop(context, const _BudgetDialogResult.delete());
                return;
              }
              final parsed = MoneyFormatter.tryParse(inputValue);
              if (parsed == null || parsed < 0) return;
              Navigator.pop(
                context,
                parsed == 0
                    ? const _BudgetDialogResult.delete()
                    : _BudgetDialogResult.value(parsed),
              );
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result.delete) {
      if (current != null) {
        await ref.read(invoiceRepositoryProvider).deleteBudget(current.id);
      }
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
    // Danh mục chưa đặt hạn mức (hoặc hạn mức 0) mặc định là không giới hạn.
    final limit = budget?.limitMinor ?? 0;
    final unlimited = limit <= 0;
    final ratio = unlimited ? 0.0 : spentMinor / limit;
    final isOver = !unlimited && spentMinor > limit;
    final progressColor = isOver
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
                    if (isOver)
                      Tooltip(
                        message: 'Vượt hạn mức',
                        child: Icon(
                          Icons.warning_amber_rounded,
                          color: finance.budgetOver.color,
                        ),
                      ),
                    IconButton(
                      tooltip: 'Sửa ngân sách ${category.name}',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
                if (unlimited)
                  Text(
                    'Không giới hạn · Đã chi ${MoneyFormatter.format(spentMinor)}',
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
                    minHeight: 10,
                    color: progressColor,
                    backgroundColor: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppSpacing.sm),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    isOver
                        ? 'Vượt hạn mức ${MoneyFormatter.format(-remaining)}'
                        : 'Còn lại ${MoneyFormatter.format(remaining)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isOver
                          ? finance.budgetOver.color
                          : scheme.onSurfaceVariant,
                      fontWeight: isOver ? FontWeight.w600 : null,
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
          // Chỉ hiển thị tổng đã chi; cảnh báo vượt hạn mức nằm ở từng danh mục.
          data: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: 'Đã chi tháng này',
                subtitle: '${data.invoiceCount} giao dịch đã ghi nhận',
              ),
              const SizedBox(height: AppSpacing.lg),
              MoneyText(data.totalMinor, emphasis: MoneyEmphasis.title),
              Text(
                'Danh mục chưa đặt hạn mức được tính là không giới hạn.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
