import '../../../shared/widgets/finmi_page_header.dart';
import '../../../shared/widgets/finmi_text_field.dart';
import '../../../shared/widgets/category_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/utils/money_input_formatter.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/utils/month_utils.dart';
import '../../../shared/formatting/category_icons.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/dialogs/confirm_dialog.dart';

class CategoryManagementScreen extends ConsumerStatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  ConsumerState<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState
    extends ConsumerState<CategoryManagementScreen> {
  CategoryKind _kind = CategoryKind.expense;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final categoryProvider = _kind == CategoryKind.income
        ? incomeCategoriesProvider
        : categoriesProvider;
    final categoryState = ref.watch(categoryProvider);
    final categories = categoryState.asData?.value;
    final selectedMonth = ref.watch(selectedMonthProvider);
    final monthKey = MonthUtils.key(selectedMonth);
    final monthLabel = MonthUtils.label(selectedMonth, isEn: tr.isEn);
    return Scaffold(
      appBar: FinmiPageHeader(
        title: tr.manageCategories,
        actions: [
          FinmiHeaderAction(
            tooltip: tr.addCategory,
            onPressed: categories == null
                ? null
                : () => _editCategory(
                    context,
                    ref,
                    categories,
                    _kind,
                    monthKey,
                    monthLabel,
                  ),
            icon: Icons.add,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: SegmentedButton<CategoryKind>(
              segments: [
                ButtonSegment(
                  value: CategoryKind.expense,
                  label: Text(tr.expensesKind),
                ),
                ButtonSegment(
                  value: CategoryKind.income,
                  label: Text(tr.incomeKind),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (selection) =>
                  setState(() => _kind = selection.first),
            ),
          ),
          Expanded(
            child: switch (categoryState) {
              AsyncData(value: final items) => _CategoryList(
                categories: items,
                onEdit: (category) => _editCategory(
                  context,
                  ref,
                  items,
                  _kind,
                  monthKey,
                  monthLabel,
                  editing: category,
                ),
                onDelete: (category) => _deleteCategory(context, ref, category),
              ),
              AsyncError(:final error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline),
                      const SizedBox(height: 12),
                      Text('Không thể tải danh mục: ${friendlyMessage(error)}'),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => ref.invalidate(categoryProvider),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }

  Future<void> _editCategory(
    BuildContext context,
    WidgetRef ref,
    List<CategoryEntity> categories,
    CategoryKind kind,
    String monthKey,
    String monthLabel, {
    CategoryEntity? editing,
  }) async {
    final result = await _showCategoryDialog(
      context,
      categories: categories,
      kind: kind,
      monthLabel: monthLabel,
      editing: editing,
    );
    if (result == null || !context.mounted) return;

    var categorySaved = false;
    try {
      final repository = ref.read(invoiceRepositoryProvider);
      await repository.saveCategory(result.category);
      categorySaved = true;
      if (result.initialBudgetMinor case final limit?) {
        await repository.saveBudget(
          BudgetEntity(
            id: '$monthKey-${result.category.id}',
            monthKey: monthKey,
            categoryId: result.category.id,
            limitMinor: limit,
          ),
        );
      }
      if (!context.mounted) return;
      final message = editing == null
          ? result.initialBudgetMinor == null
                ? 'Đã thêm danh mục.'
                : 'Đã thêm danh mục và hạn mức tháng.'
          : 'Đã cập nhật danh mục.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on Object catch (error) {
      if (!context.mounted) return;
      final message = categorySaved && result.initialBudgetMinor != null
          ? 'Đã lưu danh mục nhưng chưa lưu được hạn mức: '
                '${friendlyMessage(error)}'
          : 'Không thể lưu danh mục: ${friendlyMessage(error)}';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _deleteCategory(
    BuildContext context,
    WidgetRef ref,
    CategoryEntity category,
  ) async {
    final tr = context.tr;
    final confirmed = await showConfirmDialog(
      context,
      title: tr.deleteCategoryPrompt(
        tr.categoryName(category.name, categoryId: category.id),
      ),
      message: category.kind == CategoryKind.income
          ? tr.deleteCategoryIncomeDesc
          : tr.deleteCategoryExpenseDesc,
      confirmLabel: tr.deleteCategory,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(invoiceRepositoryProvider).deleteCategory(category.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr.isEn ? 'Category deleted.' : 'Đã xóa danh mục.'),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr.isEn
                ? 'Cannot delete category: ${friendlyMessage(error)}'
                : 'Không thể xóa danh mục: ${friendlyMessage(error)}',
          ),
        ),
      );
    }
  }
}

Future<CategoryEntity?> createCategoryFromEntry(
  BuildContext context,
  WidgetRef ref,
  List<CategoryEntity> categories,
  CategoryKind kind,
) async {
  final month = ref.read(selectedMonthProvider);
  final tr = context.tr;
  final result = await _showCategoryDialog(
    context,
    categories: categories,
    kind: kind,
    monthLabel: MonthUtils.label(month),
  );
  if (result == null || !context.mounted) return null;
  try {
    final repository = ref.read(invoiceRepositoryProvider);
    await repository.saveCategory(result.category);
    if (result.initialBudgetMinor case final limit?) {
      try {
        await repository.saveBudget(
          BudgetEntity(
            id: '${MonthUtils.key(month)}-${result.category.id}',
            monthKey: MonthUtils.key(month),
            categoryId: result.category.id,
            limitMinor: limit,
          ),
        );
      } on Object catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr.isEn
                    ? 'Category saved, but failed to save limit: ${friendlyMessage(error)}'
                    : 'Đã lưu danh mục nhưng chưa lưu được hạn mức: ${friendlyMessage(error)}',
              ),
            ),
          );
        }
      }
    }
    return result.category;
  } on Object catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr.isEn
                ? 'Cannot save category: ${friendlyMessage(error)}'
                : 'Không thể lưu danh mục: ${friendlyMessage(error)}',
          ),
        ),
      );
    }
    return null;
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({
    required this.categories,
    required this.onEdit,
    required this.onDelete,
  });

  final List<CategoryEntity> categories;
  final ValueChanged<CategoryEntity> onEdit;
  final ValueChanged<CategoryEntity> onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        if (categories.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                context.tr.isEn
                    ? 'No categories yet.'
                    : 'Chưa có danh mục nào.',
              ),
            ),
          )
        else
          for (final category in categories)
            Card(
              key: ValueKey('category-${category.id}'),
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                minTileHeight: 64,
                leading: CategoryAvatar(category: category, radius: 18),
                title: Text(
                  context.tr.categoryName(
                    category.name,
                    categoryId: category.id,
                  ),
                ),
                subtitle: Text(
                  category.isSystem
                      ? context.tr.defaultCategory
                      : context.tr.customCategory,
                ),
                onTap: () => onEdit(category),
                trailing: Wrap(
                  spacing: 0,
                  children: [
                    IconButton(
                      tooltip: context.tr.editCategory,
                      onPressed: () => onEdit(category),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    if (!category.isSystem)
                      IconButton(
                        tooltip: context.tr.deleteCategory,
                        onPressed: () => onDelete(category),
                        icon: const Icon(Icons.delete_outline),
                      ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

typedef _CategoryDialogResult = ({
  CategoryEntity category,
  int? initialBudgetMinor,
});

Future<_CategoryDialogResult?> _showCategoryDialog(
  BuildContext context, {
  required List<CategoryEntity> categories,
  required CategoryKind kind,
  required String monthLabel,
  CategoryEntity? editing,
}) {
  return showDialog<_CategoryDialogResult>(
    context: context,
    builder: (_) => _CategoryDialog(
      categories: categories,
      kind: kind,
      monthLabel: monthLabel,
      editing: editing,
    ),
  );
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({
    required this.categories,
    required this.kind,
    required this.monthLabel,
    this.editing,
  });

  final List<CategoryEntity> categories;
  final CategoryKind kind;
  final String monthLabel;
  final CategoryEntity? editing;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  static const _colorValues = [
    0xFF0F766E,
    0xFF16A34A,
    0xFF22C55E,
    0xFF059669,
    0xFF0284C7,
    0xFF2563EB,
    0xFF4F46E5,
    0xFF7C3AED,
    0xFF9333EA,
    0xFFDB2777,
    0xFFE11D48,
    0xFFDC2626,
    0xFFEA580C,
    0xFFD97706,
    0xFFCA8A04,
    0xFF64748B,
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _budgetController;
  late String _iconName;
  late int _colorValue;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.editing?.name);
    _budgetController = TextEditingController();
    _iconName = widget.editing?.iconName ?? 'category';
    _colorValue = widget.editing?.colorValue ?? _colorValues.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return AlertDialog(
      title: Text(widget.editing == null ? tr.addCategory : tr.editCategory),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FinmiTextField(
                key: const ValueKey('category-name-field'),
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: tr.categoryNameLabel,
                  hintText: tr.categoryNameHint,
                  prefixIcon: const Icon(Icons.category_outlined),
                ),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.isEmpty) return tr.pleaseEnterCategoryName;
                  final duplicate = widget.categories.any(
                    (item) =>
                        item.id != widget.editing?.id &&
                        item.name.trim().toLowerCase() == name.toLowerCase(),
                  );
                  return duplicate ? tr.categoryNameExists : null;
                },
              ),
              if (widget.kind == CategoryKind.expense &&
                  widget.editing == null) ...[
                const SizedBox(height: 16),
                FinmiTextField(
                  key: const ValueKey('category-budget-field'),
                  controller: _budgetController,
                  inputFormatters: [const MoneyInputFormatter()],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr.categoryLimitLabel(widget.monthLabel),
                    suffixText: '₫',
                    helperText: tr.categoryLimitHelper,
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return null;
                    final amount = MoneyFormatter.tryParse(text);
                    if (amount == null || amount < 0) {
                      return tr.isEn
                          ? 'Please enter a valid amount.'
                          : 'Hãy nhập hạn mức hợp lệ.';
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 20),
              Text(
                tr.categoryIcons,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in kCategoryIconNames)
                    ChoiceChip(
                      tooltip: categoryIconLabel(item),
                      label: Icon(
                        categoryIconFor(item),
                        size: 20,
                        semanticLabel: categoryIconLabel(item),
                      ),
                      selected: _iconName == item,
                      onSelected: (_) => setState(() => _iconName = item),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                tr.categoryColors,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final item in _colorValues)
                    InkWell(
                      onTap: () => setState(() => _colorValue = item),
                      borderRadius: BorderRadius.circular(24),
                      child: Semantics(
                        label: tr.isEn ? 'Pick color' : 'Chọn màu',
                        selected: _colorValue == item,
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: Color(item),
                          child: _colorValue == item
                              ? Icon(
                                  Icons.check,
                                  color: _checkColorOn(Color(item)),
                                )
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _cancel, child: Text(tr.cancel)),
        FilledButton(onPressed: _save, child: Text(tr.saveCategoryBtn)),
      ],
    );
  }

  Future<void> _cancel() async {
    final editing = widget.editing;
    final hasChanges =
        _nameController.text != (editing?.name ?? '') ||
        _budgetController.text.isNotEmpty ||
        _iconName != (editing?.iconName ?? 'category') ||
        _colorValue != (editing?.colorValue ?? _colorValues.first);
    if (hasChanges) {
      final discard = await showDiscardChangesDialog(context);
      if (!discard || !mounted) return;
    }
    Navigator.pop(context);
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final budgetText = _budgetController.text.trim();
    final initialBudgetMinor = budgetText.isEmpty
        ? null
        : MoneyFormatter.tryParse(budgetText);
    final editing = widget.editing;
    Navigator.pop(context, (
      category: CategoryEntity(
        id:
            editing?.id ??
            '${widget.kind == CategoryKind.income ? 'income-' : ''}custom-${const Uuid().v4()}',
        name: _nameController.text.trim(),
        iconName: _iconName,
        colorValue: _colorValue,
        isSystem: editing?.isSystem ?? false,
        kind: widget.kind,
      ),
      initialBudgetMinor: widget.kind == CategoryKind.expense && editing == null
          ? initialBudgetMinor
          : null,
    ));
  }
}

/// Đen hay trắng — chọn cái nào tương phản tốt hơn với ô màu bên dưới.
Color _checkColorOn(Color swatch) {
  final luminance = swatch.computeLuminance();
  final onWhite = 1.05 / (luminance + 0.05);
  final onBlack = (luminance + 0.05) / 0.05;
  return onBlack >= onWhite ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
}
