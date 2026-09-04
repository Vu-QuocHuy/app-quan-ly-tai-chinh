import 'package:flutter/material.dart';

import '../../app/theme/category_palette.dart';
import '../../features/invoices/domain/invoice_models.dart';
import '../formatting/category_icons.dart';

enum CategoryAvatarStyle { tinted, solid }

/// Avatar danh mục. `Colors.white` KHÔNG xuất hiện ở đây.
///
/// Thay ba cách vẽ khác nhau cho cùng một danh mục — trong đó bản nền-đặc +
/// glyph trắng đạt 2.94:1 trên seed amber, và bản tint 14% + glyph nguyên màu
/// đạt 2.32:1. Cả hai đều mù theme.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({
    required this.category,
    this.radius = 20,
    this.style = CategoryAvatarStyle.tinted,
    super.key,
  });

  final CategoryEntity? category;
  final double radius;
  final CategoryAvatarStyle style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = categoryIconFor(category?.iconName);

    if (category == null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: scheme.surfaceContainerHigh,
        child: Icon(icon, size: radius, color: scheme.onSurfaceVariant),
      );
    }

    final colors = CategoryPalette.resolve(category!.colorValue, scheme);
    final solid = style == CategoryAvatarStyle.solid;

    return CircleAvatar(
      radius: radius,
      backgroundColor: solid ? colors.glyph : colors.tint,
      child: Icon(
        icon,
        size: radius,
        color: solid ? colors.tint : colors.glyph,
      ),
    );
  }
}
