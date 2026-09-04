import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';

/// Ràng nội dung một cột vào bề rộng đọc được và canh giữa.
///
/// Không có nó, khi `NavigationRail` xuất hiện ở 840dp thì mọi `ListTile`,
/// dòng hóa đơn và thẻ dashboard kéo dài hết chiều ngang cửa sổ — một dòng
/// Cài đặt rộng ~1300dp trên cửa sổ web 1440dp. Đây là kiểu xấu phổ biến nhất
/// của layout tablet/desktop.
class ReadingPane extends StatelessWidget {
  const ReadingPane({
    required this.child,
    this.maxWidth = AppBreakpoints.readingWidth,
    super.key,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
