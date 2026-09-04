import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';

enum SectionHeaderSize { large, small }

/// Tiêu đề section. Hợp nhất hai quy ước đang cùng tồn tại: `Text(titleLarge)`
/// + `SizedBox(height: 12)` thủ công rải khắp các màn hình, và `_Section` dùng
/// `titleMedium` thụt 4px trong Cài đặt.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    this.size = SectionHeaderSize.large,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final SectionHeaderSize size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = switch (size) {
      SectionHeaderSize.large => theme.textTheme.titleLarge,
      SectionHeaderSize.small => theme.textTheme.titleSmall,
    };

    return Semantics(
      header: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: titleStyle?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.md),
            trailing!,
          ],
        ],
      ),
    );
  }
}
