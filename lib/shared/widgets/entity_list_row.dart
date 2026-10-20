import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';

/// Một dòng thực thể trong danh sách: avatar/icon dẫn đầu, tiêu đề, phụ đề,
/// giá trị đuôi và badge tuỳ chọn.
///
/// Thay sáu cách dựng dòng khác nhau và chuẩn hoá chiều cao tối thiểu (trước
/// đây là 72 ở Ngân sách, 64 ở sheet nguồn nhập, mặc định ở những nơi còn lại).
class EntityListRow extends StatelessWidget {
  const EntityListRow({
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.badge,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.outlined = false,
    super.key,
  });

  final Widget? leading;
  final bool outlined;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? badge;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Một câu duy nhất cho TalkBack. Trước đây dòng hóa đơn đọc thành 4 mảnh rời.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final stack =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) / 14 >= 1.3;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: outlined
              ? theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                )
              : theme.textTheme.titleMedium,
        ),
        if (badge != null) ...[const SizedBox(height: 4), badge!],
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style:
                (outlined
                        ? theme.textTheme.bodySmall
                        : theme.textTheme.bodyMedium)
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        if (stack && trailing != null) ...[
          const SizedBox(height: 8),
          trailing!,
        ],
      ],
    );
    final row = InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(child: details),
              if (!stack && trailing != null) ...[
                const SizedBox(width: AppSpacing.md),
                Flexible(child: trailing!),
              ],
            ],
          ),
        ),
      ),
    );

    final surface = outlined
        ? Card(margin: const EdgeInsets.only(bottom: 8), child: row)
        : row;
    if (semanticLabel == null) return surface;
    // `button: true` chỉ đặt CỜ; hành động tap đến từ `onTap:`. Bọc InkWell
    // trong ExcludeSemantics gỡ mất node duy nhất mang `SemanticsAction.tap`,
    // nên nếu không truyền lại onTap thì TalkBack đọc được dòng mà không kích
    // hoạt được nó.
    return Semantics(
      container: true,
      button: onTap != null,
      label: semanticLabel,
      onTap: onTap,
      onLongPress: onLongPress,
      child: ExcludeSemantics(child: surface),
    );
  }
}
