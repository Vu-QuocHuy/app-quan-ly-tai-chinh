import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class SupabaseBootstrap {
  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static bool _initialized = false;

  static bool get isConfigured =>
      _url.trim().isNotEmpty && _publishableKey.trim().isNotEmpty;

  static SupabaseClient? get clientOrNull =>
      _initialized ? Supabase.instance.client : null;

  static Future<bool> initialize() async {
    if (!isConfigured) return false;
    if (_initialized) return true;
    await Supabase.initialize(url: _url, publishableKey: _publishableKey);
    _initialized = true;
    return true;
  }
}
