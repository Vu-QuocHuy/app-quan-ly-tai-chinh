import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../app/theme/finance_colors.dart';

enum StatusTone { neutral, info, safe, warn, danger }

/// `icon` và `label` là THAM SỐ BẮT BUỘC. Không có đường đi nào qua API này
/// cho phép một trạng thái chỉ được truyền đạt bằng màu.
///
/// Mô tả một quy ước bằng văn xuôi thì yếu hơn ép nó bằng constructor —
/// IMPLEMENTATION.md đã tuyên bố "không dùng màu làm tín hiệu duy nhất" từ
/// trước và code vẫn vi phạm ở nav bar, thanh ngân sách và badge trạng thái.
///
/// Tiêu chí nghiệm thu: chụp màn hình đen trắng, mọi trạng thái vẫn đọc được.
class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.icon,
    required this.label,
    required this.tone,
    this.dense = false,
    this.semanticsLabel,
    super.key,
  });

  final IconData icon;
  final String label;
  final StatusTone tone;
  final bool dense;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finance = context.finance;
    final scheme = theme.colorScheme;

    final (background, foreground) = switch (tone) {
      StatusTone.neutral => (
        scheme.surfaceContainerHigh,
        scheme.onSurfaceVariant,
      ),
      StatusTone.info => (
        finance.syncPending.container,
        finance.syncPending.onContainer,
      ),
      StatusTone.safe => (
        finance.budgetSafe.container,
        finance.budgetSafe.onContainer,
      ),
      StatusTone.warn => (
        finance.budgetWarn.container,
        finance.budgetWarn.onContainer,
      ),
      StatusTone.danger => (
        finance.budgetOver.container,
        finance.budgetOver.onContainer,
      ),
    };

    return Semantics(
      container: true,
      label: semanticsLabel ?? label,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: ShapeDecoration(color: background, shape: AppShapes.pill),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: dense ? AppSpacing.sm : AppSpacing.md,
              vertical: dense ? 2 : AppSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: dense ? 14 : AppIconSizes.sm,
                  color: foreground,
                ),
                SizedBox(width: dense ? AppSpacing.xs : 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (dense
                                ? theme.textTheme.labelSmall
                                : theme.textTheme.labelMedium)
                            ?.copyWith(color: foreground),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
