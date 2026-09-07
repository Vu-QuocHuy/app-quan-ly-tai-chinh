import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';

/// Dòng nhãn — giá trị. Dùng cho chi tiết hóa đơn, thống kê khôi phục và màn
/// so sánh xung đột.
class LabelledRow extends StatelessWidget {
  const LabelledRow({
    required this.label,
    required this.value,
    this.secondValue,
    this.labelWidth,
    this.isDifferent = false,
    this.onCopy,
    this.stackBelow = 360,
    super.key,
  });

  final String label;
  final Widget value;

  /// Cột thứ hai (dùng ở màn so sánh xung đột).
  final Widget? secondValue;

  final double? labelWidth;

  /// Tô nền + đánh dấu icon cho dòng THẬT SỰ khác nhau. Trước đây màn xung đột
  /// in đậm cột "local" cho MỌI dòng, giống hay khác cũng vậy.
  final bool isDifferent;

  final VoidCallback? onCopy;

  /// Dưới bề rộng này thì xếp dọc, để nhãn không bị bóp ở cỡ chữ lớn.
  final double stackBelow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final labelWidget = Text(
      label,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );

    final valueWidgets = <Widget>[
      Expanded(child: value),
      if (secondValue != null) ...[
        const SizedBox(width: AppSpacing.md),
        Expanded(child: secondValue!),
      ],
      if (onCopy != null)
        IconButton(
          onPressed: onCopy,
          tooltip: 'Sao chép $label',
          icon: const Icon(Icons.copy_outlined),
        ),
    ];

    final content = LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < stackBelow;

        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              labelWidget,
              const SizedBox(height: AppSpacing.xs),
              Row(children: valueWidgets),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: labelWidth ?? 120, child: labelWidget),
            const SizedBox(width: AppSpacing.md),
            ...valueWidgets,
          ],
        );
      },
    );

    if (!isDifferent) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: content,
      );
    }

    return Semantics(
      container: true,
      label: '$label — hai bản khác nhau',
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: scheme.insetSurface,
          shape: AppShapes.control,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: AppSpacing.sm),
                child: Icon(
                  Icons.compare_arrows,
                  size: AppIconSizes.sm,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Expanded(child: content),
            ],
          ),
        ),
      ),
    );
  }
}
