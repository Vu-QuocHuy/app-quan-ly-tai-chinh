import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

/// `MaterialScrollBehavior` mặc định loại chuột khỏi `dragDevices`, nên trên
/// web/desktop người dùng không kéo-chuột để cuộn được. App này có target web
/// (thư mục `web/` và commit hỗ trợ web database) nên đó là lỗi thật.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };
}
