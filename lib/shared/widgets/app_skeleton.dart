import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';

/// Khối skeleton TĨNH khớp hình học của widget thật. KHÔNG shimmer.
///
/// Animation lặp vô hạn làm `tester.pumpAndSettle()` treo và repo đã có test
/// gọi hàm đó. Crossfade sang nội dung thật do `AppAsyncView` lo (200ms).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    this.width,
    this.height = 16,
    this.radius = AppShapes.xs,
    super.key,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.insetSurface,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Khớp hình học của hero tổng chi trên Dashboard.
class SkeletonHero extends StatelessWidget {
  const SkeletonHero({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.cardSurface,
      shape: AppShapes.hero,
      child: const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SkeletonBox(width: 120, height: 12),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(width: 220, height: 40),
            SizedBox(height: AppSpacing.xl),
            SkeletonBox(height: 10, radius: 999),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(width: 160, height: 12),
          ],
        ),
      ),
    );
  }
}

class SkeletonListRows extends StatelessWidget {
  const SkeletonListRows({this.count = 5, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.cardSurface,
      shape: AppShapes.card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: scheme.outlineVariant,
                indent: AppSpacing.dividerIndent,
              ),
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.lg,
              ),
              child: Row(
                children: [
                  SkeletonBox(width: 40, height: 40, radius: 999),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 140, height: 14),
                        SizedBox(height: AppSpacing.sm),
                        SkeletonBox(width: 90, height: 12),
                      ],
                    ),
                  ),
                  SizedBox(width: AppSpacing.md),
                  SkeletonBox(width: 80, height: 16),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SkeletonChart extends StatelessWidget {
  const SkeletonChart({super.key});

  @override
  Widget build(BuildContext context) {
    // Chiều cao cột cố định, deterministic — không Random(), để golden test ổn.
    const heights = <double>[46, 78, 34, 92, 58, 70, 40];
    return Card(
      color: Theme.of(context).colorScheme.cardSurface,
      shape: AppShapes.card,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SizedBox(
          height: 140,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final height in heights)
                SkeletonBox(width: 18, height: height),
            ],
          ),
        ),
      ),
    );
  }
}

/// MỘT kích thước spinner trong nút. Trước đây là 18px ở màn Review và 20px ở
/// màn Tài khoản, nên nút đổi kích thước giữa các màn đúng lúc người dùng chờ.
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
