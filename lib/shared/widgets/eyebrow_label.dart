import 'package:flutter/material.dart';

/// Nhãn lề kiểu nghề in: một dòng `labelMedium` / `onSurfaceVariant`, CÂU
/// THƯỜNG, đặt phía trên con số mà nó đặt tên, canh cùng mép quang học.
///
/// Đây là thứ cho phép các con số to mà không mơ hồ, và nó xoá nhu cầu dùng
/// icon + chip màu để giải thích từng figure.
///
/// Cố ý KHÔNG viết hoa: `.toUpperCase()` trên tiếng Việt đẩy dấu chồng vào
/// vùng ascender nơi Roboto có ít khoảng trống nhất, và cũng rộng hơn ~30% —
/// điều đáng kể ở textScale 2.0.
class EyebrowLabel extends StatelessWidget {
  const EyebrowLabel(this.text, {this.color, super.key});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(
        color: color ?? theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
