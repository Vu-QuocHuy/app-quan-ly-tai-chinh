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

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: titleStyle?.copyWith(color: theme.colorScheme.onSurface),
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
    );
    final stack =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) / 14 >= 1.3;
    return Semantics(
      header: true,
      child: stack
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [heading, ?trailing],
            )
          : Row(
              children: [
                Expanded(child: heading),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.md),
                  trailing!,
                ],
              ],
            ),
    );
  }
}
