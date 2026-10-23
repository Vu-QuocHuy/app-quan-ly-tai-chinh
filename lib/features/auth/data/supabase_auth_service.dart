import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/security/supabase_bootstrap.dart';

class SupabaseAuthService {
  const SupabaseAuthService(this._client);

  final SupabaseClient _client;

  String? get _oauthRedirectUri => kIsWeb
      ? SupabaseBootstrap.oauthRedirectUri
      : 'hoadoninsight://login-callback';

  User? get currentUser => _client.auth.currentUser;

  Stream<User?> watchUser() async* {
    yield currentUser;
    yield* _client.auth.onAuthStateChange.map((event) => event.session?.user);
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? displayName,
    String? phone,
  }) {
    return _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      },
    );
  }

  Future<bool> signInWithGoogle() async {
    // Kiểm tra trước xem Google OAuth Provider có được bật trên Supabase không
    // để tránh việc trình duyệt bị chuyển hướng sang trang trắng báo lỗi JSON 400.
    try {
      final origin = Uri.parse(_client.rest.url).origin;
      final checkUri = Uri.parse('$origin/auth/v1/authorize?provider=google');
      final client = http.Client();
      final response = await client
          .get(
            checkUri,
            headers: {
              if (_client.headers['apikey'] != null)
                'apikey': _client.headers['apikey']!,
            },
          )
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 400 &&
          (response.body.contains('provider is not enabled') ||
              response.body.contains('Unsupported provider'))) {
        throw const AuthException(
          'Unsupported provider: provider is not enabled',
          statusCode: '400',
        );
      }
    } on AuthException {
      rethrow;
    } catch (_) {
      // Bỏ qua nếu có lỗi mạng khi kiểm tra trước để không chặn luồng chính
    }

    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _oauthRedirectUri,
    );
  }

  Future<void> resendSignupConfirmation(String email) async {
    await _client.auth.resend(type: OtpType.signup, email: email.trim());
  }

  Future<bool> linkGoogleIdentity() {
    return _client.auth.linkIdentity(
      OAuthProvider.google,
      redirectTo: _oauthRedirectUri,
    );
  }

  Future<List<UserIdentity>> getUserIdentities() {
    return _client.auth.getUserIdentities();
  }

  Future<void> unlinkIdentity(UserIdentity identity) {
    return _client.auth.unlinkIdentity(identity);
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: SupabaseBootstrap.passwordRecoveryRedirectUri,
    );
  }

  Future<UserResponse> updatePassword(String password) {
    return _client.auth.updateUser(UserAttributes(password: password));
  }

  Future<void> deleteAccount() async {
    if (_client.auth.currentSession == null) {
      throw const AuthException('Hãy đăng nhập trước khi xóa tài khoản.');
    }
    try {
      final response = await _client.functions.invoke('delete-account');
      final data = response.data;
      if (data is! Map || data['deleted'] != true) {
        throw const FormatException('Máy chủ chưa xác nhận xóa tài khoản.');
      }
    } on AppException {
      rethrow;
    } on Object catch (error) {
      throw NetworkException(
        'Không thể xóa tài khoản trên máy chủ. Hãy thử lại.',
        cause: error,
      );
    }
  }

  Future<void> signOut() => _client.auth.signOut();
}
