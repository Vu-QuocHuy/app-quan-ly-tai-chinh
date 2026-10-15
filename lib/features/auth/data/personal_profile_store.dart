import 'package:supabase_flutter/supabase_flutter.dart';

class PersonalProfile {
  const PersonalProfile({required this.displayName, required this.phone});

  final String displayName;
  final String phone;
}

class PersonalProfileStore {
  const PersonalProfileStore(this.client);

  final SupabaseClient client;

  Future<PersonalProfile> load() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthException('Hãy đăng nhập để xem hồ sơ.');
    }
    final row = await client
        .from('profiles')
        .select('display_name, phone')
        .eq('user_id', userId)
        .single();
    return PersonalProfile(
      displayName: (row['display_name'] as String?) ?? '',
      phone: (row['phone'] as String?) ?? '',
    );
  }

  Future<void> save({
    required String displayName,
    required String phone,
  }) async {
    if (client.auth.currentUser == null) {
      throw const AuthException('Hãy đăng nhập để sửa hồ sơ.');
    }
    await client.rpc(
      'save_personal_profile',
      params: {'p_display_name': displayName.trim(), 'p_phone': phone.trim()},
    );
  }
}
