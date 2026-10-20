import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../app/theme/finmi_theme.dart';

/// Thẻ L1. Gộp bộ ba `Card > InkWell > Padding` và cặp `Card > Padding` thành
/// một widget.
///
/// Thẻ tĩnh và thẻ tương tác đều có viền Finmi 1.25 dp trên nền đặc.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.color,
    this.shape,
    this.clipBehavior,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final ShapeBorder? shape;

  /// Mặc định: chỉ clip khi thẻ CHẠM ĐƯỢC (để splash của InkWell tôn trọng
  /// bo góc). Thẻ tĩnh không clip — mỗi lần clip là một `saveLayer`, và với
  /// một danh sách dài thì đó là chi phí trả cho thứ không ai nhìn thấy.
  final Clip? clipBehavior;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final interactive = onTap != null;

    final tokens = context.finmi;
    final effectiveShape =
        shape ??
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.cardRadius),
          side: BorderSide(color: tokens.border, width: tokens.outlineWidth),
        );

    Widget content = Padding(padding: padding, child: child);

    if (interactive) {
      content = InkWell(
        onTap: onTap,
        borderRadius: AppShapes.cardRadius,
        child: content,
      );
    }

    final card = Card(
      color: color ?? scheme.cardSurface,
      shape: effectiveShape,
      clipBehavior: clipBehavior ?? (interactive ? Clip.antiAlias : Clip.none),
      child: content,
    );

    if (semanticLabel == null) return card;
    return Semantics(container: true, label: semanticLabel, child: card);
  }
}
