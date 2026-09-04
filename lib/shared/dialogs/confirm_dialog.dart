import 'package:flutter/material.dart';

/// Dialog xác nhận dùng chung.
///
/// `destructive: true` cấp CẢ HAI: `FilledButton` màu error VÀ icon cảnh báo.
/// Trước đây chỉ 2/6 dialog phá hủy dùng màu error, nên "Xóa danh mục" trông
/// an toàn y hệt "Lưu" — chính sách bị đảo ngược.
///
/// Nó cũng chấm dứt việc M3 canh giữa dialog có `icon:` và canh trái dialog
/// không có (trước đây 5 có / 6 không, ngẫu nhiên).
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Xác nhận',
  String cancelLabel = 'Hủy',
  IconData? icon,
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final effectiveIcon =
      icon ?? (destructive ? Icons.warning_amber_rounded : null);

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: effectiveIcon == null
          ? null
          : Icon(
              effectiveIcon,
              color: destructive ? scheme.error : scheme.primary,
            ),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  return result ?? false;
}
