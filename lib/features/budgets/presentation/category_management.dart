import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/app_providers.dart';
import '../../../shared/formatting/category_icons.dart';
import '../../../shared/widgets/category_avatar.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/dialogs/confirm_dialog.dart';

class CategoryManagement extends ConsumerWidget {
  const CategoryManagement({required this.categories, super.key});

  final List<CategoryEntity> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Danh mục chi tiêu',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Tạo danh mục và tùy chỉnh ngay tại nơi đặt ngân sách.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('Thêm danh mục'),
                subtitle: const Text('Tên, biểu tượng và màu sắc'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _editCategory(context, ref),
              ),
              for (final category in categories)
                ListTile(
                  leading: CategoryAvatar(category: category),
                  title: Text(category.name),
                  subtitle: Text(
                    category.isSystem
                        ? 'Danh mục mặc định'
                        : 'Danh mục tùy chỉnh',
                  ),
                  trailing: Wrap(
                    spacing: 0,
                    children: [
                      IconButton(
                        tooltip: 'Chỉnh sửa danh mục',
                        onPressed: () => _editCategory(context, ref, category),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      if (!category.isSystem)
                        IconButton(
                          tooltip: 'Xóa danh mục',
                          onPressed: () =>
                              _deleteCategory(context, ref, category),
                          icon: const Icon(Icons.delete_outline),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _editCategory(
    BuildContext context,
    WidgetRef ref, [
    CategoryEntity? editing,
  ]) async {
    final category = await showCategoryDialog(
      context,
      categories: categories,
      editing: editing,
    );
    if (category == null || !context.mounted) return;
    try {
      await ref.read(invoiceRepositoryProvider).saveCategory(category);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            editing == null ? 'Đã thêm danh mục.' : 'Đã cập nhật danh mục.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể lưu danh mục: ${friendlyMessage(error)}'),
        ),
      );
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

Future<CategoryEntity?> showCategoryDialog(
  BuildContext context, {
  required List<CategoryEntity> categories,
  CategoryEntity? editing,
}) async {
  final nameController = TextEditingController(text: editing?.name);
  final formKey = GlobalKey<FormState>();
  var iconName = editing?.iconName ?? 'category';
  var colorValue = editing?.colorValue ?? 0xFF0F766E;
  const iconNames = kCategoryIconNames;
  const colorValues = [
    0xFF0F766E,
    0xFF2563EB,
    0xFF7C3AED,
    0xFFEA580C,
    0xFFCA8A04,
    0xFFDC2626,
    0xFFDB2777,
    0xFF64748B,
  ];
  try {
    return await showDialog<CategoryEntity>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(editing == null ? 'Thêm danh mục' : 'Chỉnh sửa danh mục'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: nameController,
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
                      final duplicate = categories.any(
                        (item) =>
                            item.id != editing?.id &&
                            item.name.trim().toLowerCase() ==
                                name.toLowerCase(),
                      );
                      return duplicate ? 'Tên danh mục đã tồn tại.' : null;
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Biểu tượng',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in iconNames)
                        ChoiceChip(
                          // Tooltip + semanticLabel: chip chỉ có icon vốn phơi
                          // ra tên rỗng cho trình đọc màn hình.
                          tooltip: categoryIconLabel(item),
                          label: Icon(
                            categoryIconFor(item),
                            size: 20,
                            semanticLabel: categoryIconLabel(item),
                          ),
                          selected: iconName == item,
                          onSelected: (_) => setState(() => iconName = item),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Màu sắc',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: [
                      for (final item in colorValues)
                        InkWell(
                          onTap: () => setState(() => colorValue = item),
                          borderRadius: BorderRadius.circular(24),
                          child: Semantics(
                            label: 'Chọn màu',
                            selected: colorValue == item,
                            child: CircleAvatar(
                              radius: 20,
                              backgroundColor: Color(item),
                              child: colorValue == item
                                  ? Icon(
                                      Icons.check,
                                      // Dấu check phải tương phản với chính ô
                                      // màu, không mặc định trắng.
                                      // Chọn theo TƯƠNG PHẢN thật, không theo
                                      // ngưỡng luminance áng chừng: ngưỡng 0.45
                                      // cho ra dấu trắng 2.94:1 trên ô amber,
                                      // dưới mức 3:1 mà WCAG 1.4.11 đòi.
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
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                Navigator.pop(
                  dialogContext,
                  CategoryEntity(
                    id: editing?.id ?? 'custom-${const Uuid().v4()}',
                    name: nameController.text.trim(),
                    iconName: iconName,
                    colorValue: colorValue,
                    isSystem: editing?.isSystem ?? false,
                  ),
                );
              },
              child: const Text('Lưu danh mục'),
            ),
          ],
        ),
      ),
    );
  } finally {
    nameController.dispose();
  }
}

/// Đen hay trắng — chọn cái nào tương phản tốt hơn với ô màu bên dưới.
Color _checkColorOn(Color swatch) {
  final luminance = swatch.computeLuminance();
  final onWhite = 1.05 / (luminance + 0.05);
  final onBlack = (luminance + 0.05) / 0.05;
  return onBlack >= onWhite ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
}
