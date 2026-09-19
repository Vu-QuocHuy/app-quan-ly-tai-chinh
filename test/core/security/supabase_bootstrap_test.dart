import 'package:flutter_test/flutter_test.dart';

import 'package:hoadon_insight/core/security/supabase_bootstrap.dart';

void main() {
  group('Supabase OAuth redirect validation', () {
    test('allows the native callback and HTTPS web callback', () {
      expect(
        SupabaseBootstrap.isSafeOAuthRedirectUri(
          'hoadoninsight://login-callback',
        ),
        isTrue,
      );
      expect(
        SupabaseBootstrap.isSafeOAuthRedirectUri(
          'https://app.example.com/auth/callback',
        ),
        isTrue,
      );
      expect(
        SupabaseBootstrap.isSafeOAuthRedirectUri(
          'http://localhost:8080/auth/callback',
        ),
        isTrue,
      );
    });

    test('rejects unsafe schemes and callback variations', () {
      for (final value in [
        'javascript:alert(1)',
        'hoadoninsight://other-host',
        'hoadoninsight://login-callback/path',
        'https://user:password@app.example.com/callback',
        'https://app.example.com/callback#token',
        'http://public.example.com/callback',
      ]) {
        expect(
          SupabaseBootstrap.isSafeOAuthRedirectUri(value),
          isFalse,
          reason: value,
        );
      }
    });
  });
}
