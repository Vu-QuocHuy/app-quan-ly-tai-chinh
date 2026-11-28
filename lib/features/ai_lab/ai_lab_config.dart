import 'package:flutter/foundation.dart';

/// Công tắc AI Lab. Chỉ bật khi build debug *và* có `--dart-define=AI_LAB=true`;
/// bản release luôn tắt.
abstract final class AiLabConfig {
  static final bool enabled = kDebugMode && const bool.fromEnvironment('AI_LAB');

  /// Giá trị `--dart-define=AI_FLAG_PROFILE` (`b0`, `b1`, `only:...`, `server`).
  static const String flagProfile = String.fromEnvironment(
    'AI_FLAG_PROFILE',
    defaultValue: 'server',
  );
}
