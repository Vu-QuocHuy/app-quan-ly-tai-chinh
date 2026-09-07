import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../app/theme/finance_colors.dart';

enum CalloutTone { info, safe, warning, danger, neutral }

/// Khối thông báo trong luồng nội dung.
///
/// Thay bảy implement callout với năm bán kính khác nhau. Quan trọng hơn:
/// `tone` khiến cảnh báo tư vấn thôi được vẽ bằng màu phá hủy. Trước đây màn
/// Review nhét cả cảnh báo tư vấn, lỗi chặn và lỗi hệ thống vào cùng một khối
/// đỏ — trong khi IMPLEMENTATION.md để dành `error` cho lỗi và hành động phá
/// hủy.
class AppCallout extends StatelessWidget {
  const AppCallout({
    required this.message,
    this.tone = CalloutTone.info,
    this.title,
    this.icon,
    this.actions = const [],
    this.liveRegion = false,
    this.onDismiss,
    super.key,
  });

  final String message;
  final CalloutTone tone;
  final String? title;
  final IconData? icon;
  final List<Widget> actions;
  final bool liveRegion;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finance = context.finance;
    final scheme = theme.colorScheme;

    final (background, foreground, defaultIcon) = switch (tone) {
      CalloutTone.info => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        Icons.info_outline,
      ),
      CalloutTone.safe => (
        finance.budgetSafe.container,
        finance.budgetSafe.onContainer,
        Icons.check_circle_outline,
      ),
      CalloutTone.warning => (
        finance.budgetWarn.container,
        finance.budgetWarn.onContainer,
        Icons.warning_amber_rounded,
      ),
      CalloutTone.danger => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline,
      ),
      CalloutTone.neutral => (
        scheme.surfaceContainerHigh,
        scheme.onSurface,
        Icons.notes_outlined,
      ),
    };

    final content = DecoratedBox(
      decoration: ShapeDecoration(color: background, shape: AppShapes.card),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon ?? defaultIcon, color: foreground, size: AppIconSizes.md),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null) ...[
                    Text(
                      title!,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: actions,
                    ),
                  ],
                ],
              ),
            ),
            if (onDismiss != null) ...[
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                onPressed: onDismiss,
                tooltip: 'Ẩn thông báo này',
                icon: Icon(Icons.close, color: foreground),
              ),
            ],
          ],
        ),
      ),
    );

    if (!liveRegion) return content;
    return Semantics(container: true, liveRegion: true, child: content);
  }
}
