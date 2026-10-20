import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeModeKey = 'app.themeMode';

/// Cho phép người dùng chọn sáng/tối/theo hệ thống.
///
/// Trước đây `ThemeMode.system` là tham chiếu `ThemeMode` duy nhất trong toàn
/// `lib/` — người dùng không có lối thoát nếu hệ điều hành ném họ vào theme họ
/// không thích.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  bool _changed = false;
  bool _disposed = false;
  @override
  ThemeMode build() {
    ref.onDispose(() => _disposed = true);
    _restore();
    return ThemeMode.light;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_themeModeKey);
    if (_changed || _disposed) return;
    state = switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    };
  }

  Future<void> set(ThemeMode mode) async {
    _changed = true;
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
