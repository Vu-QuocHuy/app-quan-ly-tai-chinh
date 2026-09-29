import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilePreferences {
  const ProfilePreferences({
    required this.themeMode,
    required this.budgetAlertsEnabled,
    this.preferredBankAppId,
  });

  final String themeMode;
  final bool budgetAlertsEnabled;
  final String? preferredBankAppId;

  factory ProfilePreferences.fromJson(Map<String, dynamic> json) {
    return ProfilePreferences(
      themeMode: json['theme_mode'] as String? ?? 'system',
      budgetAlertsEnabled: json['budget_alerts_enabled'] as bool? ?? true,
      preferredBankAppId: json['preferred_bank_app_id'] as String?,
    );
  }
}

class SupabaseProfilePreferencesStore {
  const SupabaseProfilePreferencesStore(this._client);

  final SupabaseClient _client;

  bool get canSync =>
      _client.auth.currentSession != null && _client.auth.currentUser != null;

  Future<ProfilePreferences> load() async {
    final userId = _requireUserId();
    final row = await _client
        .from('profiles')
        .select('theme_mode, budget_alerts_enabled, preferred_bank_app_id')
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) throw StateError('Không tìm thấy hồ sơ tài khoản.');
    return ProfilePreferences.fromJson(row);
  }

  Future<void> save({
    required String themeMode,
    required bool budgetAlertsEnabled,
  }) async {
    _requireUserId();
    await _client.rpc(
      'save_demo_profile_preferences',
      params: {
        'p_theme_mode': themeMode,
        'p_budget_alerts_enabled': budgetAlertsEnabled,
      },
    );
  }

  Future<void> savePreferredBankApp(String appId) async {
    _requireUserId();
    await _client.rpc(
      'save_demo_preferred_bank_app',
      params: {'p_bank_app_id': appId},
    );
  }

  String _requireUserId() {
    if (!canSync) {
      throw const AuthException('Hãy đăng nhập để dùng cài đặt cloud.');
    }
    return _client.auth.currentUser!.id;
  }
}
