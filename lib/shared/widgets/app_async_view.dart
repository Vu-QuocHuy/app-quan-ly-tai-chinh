import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_tokens.dart';
import 'app_error_state.dart';

/// Bọc một `AsyncValue` với đủ bốn trạng thái: loading / data / empty / error
/// kèm recovery.
///
/// Cố ý dùng `valueOrNull` + `isLoading` thay vì `.when` mặc định, nên khi
/// reload nội dung cũ KHÔNG bị xoá trắng — đó là lý do app hiện chớp một
/// spinner giữa màn mỗi lần refresh.
class AppAsyncView<T> extends StatelessWidget {
  const AppAsyncView({
    required this.value,
    required this.data,
    this.skeleton,
    this.onRetry,
    this.isEmpty,
    this.empty,
    this.compactError = false,
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function(BuildContext, T) data;
  final Widget? skeleton;

  /// Truyền ở call site nếu nhánh lỗi có thể phục hồi. Đây là điều buộc mọi
  /// chỗ `.when(` phải cung cấp retry — lỗ hổng "recovery" mà
  /// IMPLEMENTATION.md hứa nhưng phần lớn nhánh lỗi không đáp ứng.
  final VoidCallback? onRetry;

  final bool Function(T)? isEmpty;
  final Widget? empty;
  final bool compactError;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.fast),
      switchInCurve: AppMotion.standardDecelerate,
      child: _child(context),
    );
  }

  Widget _child(BuildContext context) {
    final current = value.valueOrNull;

    // Lỗi mà chưa từng có dữ liệu -> trạng thái lỗi toàn phần.
    if (value.hasError && current == null) {
      return AppErrorState(
        key: const ValueKey('async-error'),
        error: value.error!,
        stackTrace: value.stackTrace,
        onRetry: onRetry,
        compact: compactError,
      );
    }

    if (current == null) {
      return KeyedSubtree(
        key: const ValueKey('async-loading'),
        child:
            skeleton ??
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
      );
    }

    if (isEmpty != null && isEmpty!(current) && empty != null) {
      return KeyedSubtree(key: const ValueKey('async-empty'), child: empty!);
    }

    return KeyedSubtree(
      key: const ValueKey('async-data'),
      child: data(context, current),
    );
  }
}

/// Bản sliver cho các call site dùng `CustomScrollView`.
///
/// `data`, `skeleton` và `empty` ở đây phải trả về SLIVER (không phải box) —
/// đó là lý do nó tách khỏi [AppAsyncView] thay vì dùng chung một widget.
class AppAsyncSliver<T> extends StatelessWidget {
  const AppAsyncSliver({
    required this.value,
    required this.data,
    this.skeleton,
    this.onRetry,
    this.isEmpty,
    this.empty,
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function(BuildContext, T) data;
  final Widget? skeleton;
  final VoidCallback? onRetry;
  final bool Function(T)? isEmpty;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    final current = value.valueOrNull;

    if (value.hasError && current == null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: AppErrorState(
          error: value.error!,
          stackTrace: value.stackTrace,
          onRetry: onRetry,
        ),
      );
    }

    if (current == null) {
      return skeleton ??
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          );
    }

    if (isEmpty != null && isEmpty!(current) && empty != null) {
      return empty!;
    }

    return data(context, current);
  }
}
