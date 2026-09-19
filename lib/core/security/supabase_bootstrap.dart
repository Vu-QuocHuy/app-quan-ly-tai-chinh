import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class SupabaseBootstrap {
  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const _oauthRedirectUri = String.fromEnvironment(
    'SUPABASE_OAUTH_REDIRECT_URI',
  );

  static bool _initialized = false;
  static bool _initializationFailed = false;

  static bool get isConfigured =>
      !_initializationFailed &&
      _isSafeUrl(_url) &&
      _isPublishableKey(_publishableKey);

  static String? get oauthRedirectUri {
    final redirectUri = _oauthRedirectUri.trim();
    return redirectUri.isEmpty || !isSafeOAuthRedirectUri(redirectUri)
        ? null
        : redirectUri;
  }

  static bool isSafeOAuthRedirectUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      return false;
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'hoadoninsight') {
      return uri.host.toLowerCase() == 'login-callback' &&
          uri.path.isEmpty &&
          !uri.hasQuery;
    }
    if (scheme == 'https') return true;
    return scheme == 'http' &&
        const {'localhost', '127.0.0.1', '::1'}.contains(uri.host);
  }

  static SupabaseClient? get clientOrNull =>
      _initialized ? Supabase.instance.client : null;

  static Future<bool> initialize() async {
    if (!isConfigured) return false;
    if (_initialized) return true;
    try {
      await Supabase.initialize(
        url: _url.trim(),
        publishableKey: _publishableKey.trim(),
      );
      _initialized = true;
      return true;
    } on Object {
      _initializationFailed = true;
      return false;
    }
  }

  static bool _isSafeUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      return false;
    }
    if (uri.scheme.toLowerCase() == 'https') return true;
    if (uri.scheme.toLowerCase() != 'http') return false;
    return const {'localhost', '127.0.0.1', '::1'}.contains(uri.host);
  }

  static bool _isPublishableKey(String value) {
    final key = value.trim();
    if (key.isEmpty ||
        key.length > 4096 ||
        key.contains(RegExp(r'[\u0000-\u001F\u007F]')) ||
        key.startsWith('sb_secret_')) {
      return false;
    }
    if (!key.contains('.')) return key.startsWith('sb_publishable_');
    final parts = key.split('.');
    if (parts.length != 3) return false;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is Map &&
          (payload['role'] == 'service_role' ||
              payload['role'] == 'supabase_admin')) {
        return false;
      }
    } on Object {
      return false;
    }
    return true;
  }
}
