import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';

/// MỘT thẻ chứa N dòng, phân tách bằng kẻ tóc THỤT LỀ TREO canh theo cột chữ
/// (indent 68) chứ không theo avatar dẫn đầu.
///
/// Đây là lý do danh sách hóa đơn không còn là 50 cái thẻ chồng lên nhau: nó
/// trở thành một thẻ với các dòng có kẻ tóc.
class AppListSection extends StatelessWidget {
  const AppListSection({
    required this.children,
    this.header,
    this.dividerIndent = AppSpacing.dividerIndent,
    super.key,
  });

  final List<Widget> children;
  final Widget? header;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: scheme.cardSurface,
      shape: AppShapes.card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: header,
            ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: scheme.outlineVariant,
                indent: dividerIndent,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Phiên bản sliver để danh sách dài giữ được tính lười của `SliverList`.
///
/// Hình dạng thẻ được vẽ bằng một `DecoratedSliver` bao ngoài thay vì bọc mọi
/// dòng trong một `Card` — nghĩa là các dòng ngoài viewport vẫn không được dựng.
class SliverAppListSection extends StatelessWidget {
  const SliverAppListSection({
    required this.itemCount,
    required this.itemBuilder,
    this.dividerIndent = AppSpacing.dividerIndent,
    super.key,
  });

  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedSliver(
      decoration: ShapeDecoration(
        color: scheme.cardSurface,
        shape: AppShapes.card,
      ),
      sliver: SliverList.separated(
        itemCount: itemCount,
        itemBuilder: itemBuilder,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          thickness: 1,
          color: scheme.outlineVariant,
          indent: dividerIndent,
        ),
      ),
    );
  }
}
