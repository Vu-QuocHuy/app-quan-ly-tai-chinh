import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/utils/month_utils.dart';
import '../../../shared/formatting/category_icons.dart';
import '../../../shared/widgets/category_avatar.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/dialogs/confirm_dialog.dart';

class CategoryManagementScreen extends ConsumerWidget {
  const CategoryManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryState = ref.watch(categoriesProvider);
    final categories = categoryState.asData?.value;
    final selectedMonth = ref.watch(selectedMonthProvider);
    final monthKey = MonthUtils.key(selectedMonth);
    final monthLabel = MonthUtils.label(selectedMonth);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Danh mục'),
        actions: [
          IconButton(
            tooltip: 'Thêm danh mục',
            onPressed: categories == null
                ? null
                : () => _editCategory(
                    context,
                    ref,
                    categories,
                    monthKey,
                    monthLabel,
                  ),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: switch (categoryState) {
        AsyncData(value: final items) => _CategoryList(
          categories: items,
          onEdit: (category) => _editCategory(
            context,
            ref,
            items,
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
                  onPressed: () => ref.invalidate(categoriesProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại'),
                ),
              ],
            ),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Future<void> _editCategory(
    BuildContext context,
    WidgetRef ref,
    List<CategoryEntity> categories,
    String monthKey,
    String monthLabel, {
    CategoryEntity? editing,
  }) async {
    final result = await _showCategoryDialog(
      context,
      categories: categories,
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
    final confirmed = await showConfirmDialog(
      context,
      title: 'Xóa “${category.name}”?',
      message:
          'Hóa đơn đang dùng danh mục này sẽ chuyển về “Khác”. Ngân sách và '
          'quy tắc merchant của danh mục sẽ bị xóa.',
      confirmLabel: 'Xóa danh mục',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(invoiceRepositoryProvider).deleteCategory(category.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã xóa danh mục.')));
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể xóa danh mục: ${friendlyMessage(error)}'),
        ),
      );
    }
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
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text('Danh mục chi tiêu', style: textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Tùy chỉnh danh mục tại đây. Hạn mức có thể đặt khi thêm mới hoặc sửa trong trang Ngân sách.',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        if (categories.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('Chưa có danh mục nào.')),
          )
        else
          for (final category in categories)
            Card(
              key: ValueKey('category-${category.id}'),
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                minTileHeight: 64,
                leading: CategoryAvatar(category: category),
                title: Text(category.name),
                subtitle: Text(
                  category.isSystem
                      ? 'Danh mục mặc định'
                      : 'Danh mục tùy chỉnh',
                ),
                onTap: () => onEdit(category),
                trailing: Wrap(
                  spacing: 0,
                  children: [
                    IconButton(
                      tooltip: 'Chỉnh sửa danh mục',
                      onPressed: () => onEdit(category),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    if (!category.isSystem)
                      IconButton(
                        tooltip: 'Xóa danh mục',
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
  required String monthLabel,
  CategoryEntity? editing,
}) {
  return showDialog<_CategoryDialogResult>(
    context: context,
    builder: (_) => _CategoryDialog(
      categories: categories,
      monthLabel: monthLabel,
      editing: editing,
    ),
  );
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({
    required this.categories,
    required this.monthLabel,
    this.editing,
  });

  final List<CategoryEntity> categories;
  final String monthLabel;
  final CategoryEntity? editing;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  static const _colorValues = [
    0xFF0F766E,
    0xFF2563EB,
    0xFF7C3AED,
    0xFFEA580C,
    0xFFCA8A04,
    0xFFDC2626,
    0xFFDB2777,
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
    return AlertDialog(
      title: Text(
        widget.editing == null ? 'Thêm danh mục' : 'Chỉnh sửa danh mục',
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const ValueKey('category-name-field'),
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Tên danh mục',
                  hintText: 'Ví dụ: Văn phòng phẩm',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.isEmpty) return 'Hãy nhập tên danh mục.';
                  final duplicate = widget.categories.any(
                    (item) =>
                        item.id != widget.editing?.id &&
                        item.name.trim().toLowerCase() == name.toLowerCase(),
                  );
                  return duplicate ? 'Tên danh mục đã tồn tại.' : null;
                },
              ),
              if (widget.editing == null) ...[
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('category-budget-field'),
                  controller: _budgetController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Hạn mức tháng ${widget.monthLabel}',
                    suffixText: '₫',
                    helperText: 'Không bắt buộc; có thể chỉnh sửa sau.',
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return null;
                    final amount = MoneyFormatter.tryParse(text);
                    if (amount == null || amount < 0) {
                      return 'Hãy nhập hạn mức hợp lệ.';
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 20),
              Text('Biểu tượng', style: Theme.of(context).textTheme.titleSmall),
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
              Text('Màu sắc', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                children: [
                  for (final item in _colorValues)
                    InkWell(
                      onTap: () => setState(() => _colorValue = item),
                      borderRadius: BorderRadius.circular(24),
                      child: Semantics(
                        label: 'Chọn màu',
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
        TextButton(onPressed: _cancel, child: const Text('Hủy')),
        FilledButton(onPressed: _save, child: const Text('Lưu danh mục')),
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
        id: editing?.id ?? 'custom-${const Uuid().v4()}',
        name: _nameController.text.trim(),
        iconName: _iconName,
        colorValue: _colorValue,
        isSystem: editing?.isSystem ?? false,
      ),
      initialBudgetMinor: editing == null ? initialBudgetMinor : null,
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
