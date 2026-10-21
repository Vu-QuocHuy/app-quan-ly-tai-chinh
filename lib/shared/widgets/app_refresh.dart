import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/feature_flags.dart';
import '../../core/providers/app_providers.dart';
import '../errors/error_presenter.dart';

/// Pull-to-refresh dùng chung. Scroll view con nên dùng
/// [AlwaysScrollableScrollPhysics] để danh sách ngắn vẫn kéo được.
class AppRefreshIndicator extends StatelessWidget {
  const AppRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.edgeOffset = 0,
  });

  final Future<void> Function() onRefresh;
  final Widget child;
  final double edgeOffset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: onRefresh,
      edgeOffset: edgeOffset,
      color: scheme.primary,
      backgroundColor: scheme.surfaceContainerHigh,
      child: child,
    );
  }
}

/// Dữ liệu trên các màn là stream từ Drift nên chỉ cần kéo thay đổi từ cloud
/// về; stream sẽ tự cập nhật UI. Sync tắt hoặc chưa đăng nhập thì bỏ qua.
Future<void> refreshFromCloud(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  FeatureFlags flags;
  try {
    flags = await ref.read(featureFlagsProvider.future);
  } on Object {
    flags = FeatureFlags.defaults;
  }
  if (!flags.cloudSync) return;
  try {
    await ref.read(syncCoordinatorProvider).runOnce(batchSize: 100);
  } on Object catch (error) {
    messenger?.showSnackBar(
      SnackBar(content: Text('Không thể đồng bộ: ${friendlyMessage(error)}')),
    );
  }
}
