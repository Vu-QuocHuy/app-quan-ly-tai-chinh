import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../errors/error_presenter.dart';

/// Trạng thái lỗi dùng chung.
///
/// Nhận object lỗi THÔ và tự chạy nó qua `friendlyMessage()`, rồi giấu chuỗi
/// gốc sau một `ExpansionTile` "Chi tiết kỹ thuật". Đây là cơ chế chấm dứt việc
/// nội suy `$error` thẳng vào copy tiếng Việt.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    required this.error,
    this.onRetry,
    this.retryLabel = 'Thử lại',
    this.title = 'Không tải được dữ liệu',
    this.compact = false,
    this.stackTrace,
    super.key,
  });

  /// Object lỗi THÔ — đừng gọi `.toString()` trước khi truyền vào.
  final Object error;

  final VoidCallback? onRetry;
  final String retryLabel;
  final String title;
  final StackTrace? stackTrace;

  /// true -> dạng Row inline (dùng trong thẻ / list tile).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = friendlyMessage(error);

    if (compact) {
      return Semantics(
        container: true,
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              color: theme.colorScheme.error,
              size: AppIconSizes.md,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // `title` nói CHỖ NÀO hỏng. Bỏ nó đi thì nhiều lỗi khác nhau
                  // cùng rơi về một câu chung của `friendlyMessage`, và hai lỗi
                  // đồng thời cho ra hai dòng giống hệt nhau từng byte.
                  if (title.isNotEmpty)
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(width: AppSpacing.sm),
              TextButton(onPressed: onRetry, child: Text(retryLabel)),
            ],
          ],
        ),
      );
    }

    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: AppIconSizes.lg,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(retryLabel),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            _TechnicalDetail(error: error, stackTrace: stackTrace),
          ],
        ),
      ),
    );
  }
}

class _TechnicalDetail extends StatelessWidget {
  const _TechnicalDetail({required this.error, this.stackTrace});

  final Object error;
  final StackTrace? stackTrace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      // Bỏ kẻ chia của ExpansionTile để nó không cắt ngang empty state.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(
          'Chi tiết kỹ thuật',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
        children: [
          SelectableText(
            technicalDetail(error, stackTrace),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
