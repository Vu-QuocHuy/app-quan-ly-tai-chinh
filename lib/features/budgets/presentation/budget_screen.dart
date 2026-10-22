import '../../../shared/widgets/finmi_page_header.dart';
import '../../../shared/widgets/app_refresh.dart';
import '../../../shared/widgets/finmi_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_strings.dart';
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
    final tr = context.tr;
    final categories = ref.watch(categoriesProvider);
    final budgets = ref.watch(budgetsProvider);
    final dashboard = ref.watch(dashboardProvider);
    final selectedMonth = ref.watch(selectedMonthProvider);
    final monthKey = MonthUtils.key(selectedMonth);
    final dashboardSnapshot = dashboard.asData?.value;
    return Scaffold(
      body: AppRefreshIndicator(
        onRefresh: () => refreshFromCloud(context, ref),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            FinmiSliverHeader(
              title: tr.budgetLimits,
              actions: [
                FinmiHeaderAction(
                  tooltip: tr.manageCategories,
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
                        onEdit: () => _editBudget(
                          context,
                          ref,
                          category,
                          budget,
                          monthKey,
                        ),
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
    final tr = context.tr;
    final categoryTitle = tr.categoryName(
      category.name,
      categoryId: category.id,
    );
    final result = await showDialog<_BudgetDialogResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.budgetFor(categoryTitle), maxLines: 3),
        content: FinmiTextField(
          initialValue: initialValue,
          onChanged: (text) => inputValue = text,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: tr.monthlyLimit,
            suffixText: '₫',
            helperText: tr.budgetInputHelper,
          ),
        ),
        actions: [
          if (current != null)
            TextButton(
              onPressed: () async {
                final confirmed = await showConfirmDialog(
                  context,
                  title: tr.deleteBudgetTitle,
                  message: tr.deleteBudgetDesc(categoryTitle),
                  confirmLabel: tr.deleteLimitBtn,
                  destructive: true,
                );
                if (confirmed && context.mounted) {
                  Navigator.pop(context, const _BudgetDialogResult.delete());
                }
              },
              child: Text(
                tr.delete,
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
            child: Text(tr.cancel),
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
            child: Text(tr.save),
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr.categoryName(
                          category.name,
                          categoryId: category.id,
                        ),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (isOver)
                      Tooltip(
                        message: context.tr.isEn
                            ? 'Over budget'
                            : 'Vượt hạn mức',
                        child: Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: finance.budgetOver.color,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  unlimited
                      ? context.tr.unlimitedSpent(
                          MoneyFormatter.format(spentMinor),
                        )
                      : context.tr.budgetLimitSpent(
                          MoneyFormatter.format(limit),
                          MoneyFormatter.format(spentMinor),
                          (ratio * 100).round(),
                        ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (!unlimited) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: ratio.clamp(0, 1),
                    minHeight: 5,
                    color: progressColor,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isOver
                        ? (context.tr.isEn
                              ? 'Over by ${MoneyFormatter.format(-remaining)}'
                              : 'Vượt hạn mức ${MoneyFormatter.format(-remaining)}')
                        : (context.tr.isEn
                              ? 'Remaining ${MoneyFormatter.format(remaining)}'
                              : 'Còn lại ${MoneyFormatter.format(remaining)}'),
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
          IconButton(
            tooltip: context.tr.editBudgetFor(
              context.tr.categoryName(category.name, categoryId: category.id),
            ),
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
        ],
      ),
    );
  }
}

class _BudgetSummary extends StatefulWidget {
  const _BudgetSummary({required this.snapshot, required this.categories});

  final AsyncValue<DashboardSnapshot> snapshot;
  final List<CategoryEntity> categories;

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
          // Không cảnh báo theo tổng; chỉ liệt kê danh mục vượt hạn mức riêng.
          data: (data) {
            final tr = context.tr;
            final overBudget = data.overBudgetCategories;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr.monthlySpending,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: _expanded
                          ? tr.hideOverBudget
                          : tr.showOverBudget,
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
                  tone: context.finance.expense,
                ),
                const SizedBox(height: 6),
                if (overBudget.isNotEmpty)
                  Text(
                    tr.overBudgetCategoriesCount(overBudget.length),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.finance.budgetOver.color,
                    ),
                  ),
                if (_expanded) ...[
                  const Divider(height: 24),
                  Text(
                    tr.overBudgetCategories,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  if (overBudget.isEmpty) Text(tr.noOverBudgetCategories),
                  for (final item in overBudget)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CategoryAvatar(
                            category: widget.categories
                                .where((c) => c.id == item.categoryId)
                                .firstOrNull,
                            radius: 16,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr.categoryName(
                                    item.categoryName,
                                    categoryId: item.categoryId,
                                  ),
                                ),
                                Text(
                                  tr.overBy(
                                    MoneyFormatter.format(item.overMinor),
                                  ),
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
