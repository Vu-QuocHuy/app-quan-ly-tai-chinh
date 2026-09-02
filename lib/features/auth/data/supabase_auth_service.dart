import 'package:supabase_flutter/supabase_flutter.dart';

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

  Future<void> sendPasswordResetEmail(String email) {
    return _client.auth.resetPasswordForEmail(email.trim());
  }

  Future<UserResponse> updatePassword(String password) {
    return _client.auth.updateUser(UserAttributes(password: password));
  }

  Future<void> signOut() => _client.auth.signOut();
}
