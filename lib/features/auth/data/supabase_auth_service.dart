import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/security/supabase_bootstrap.dart';

class SupabaseAuthService {
  const SupabaseAuthService(this._client);

  final SupabaseClient _client;

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
  }) {
    return _client.auth.signUp(email: email.trim(), password: password);
  }

  Future<bool> signInWithGoogle() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: SupabaseBootstrap.oauthRedirectUri,
    );
  }

  Future<bool> linkGoogleIdentity() {
    return _client.auth.linkIdentity(
      OAuthProvider.google,
      redirectTo: SupabaseBootstrap.oauthRedirectUri,
    );
  }

  Future<List<UserIdentity>> getUserIdentities() {
    return _client.auth.getUserIdentities();
  }

  Future<void> unlinkIdentity(UserIdentity identity) {
    return _client.auth.unlinkIdentity(identity);
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _client.auth.resetPasswordForEmail(email.trim());
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
