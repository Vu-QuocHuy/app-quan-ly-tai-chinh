import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/settings/data/supabase_profile_preferences_store.dart';
import 'package:hoadon_insight/features/settings/presentation/cloud_profile_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('restores cloud preferences without saving over them', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = _FakePreferencesStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith(
            (ref) => Stream.value(
              const User(
                id: 'user-1',
                appMetadata: {},
                userMetadata: {},
                aud: 'authenticated',
                createdAt: '2026-01-01T00:00:00Z',
              ),
            ),
          ),
          profilePreferencesStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(home: CloudProfileSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Giao diện đã lưu'), findsOneWidget);
    expect(find.text('Tối'), findsOneWidget);
    expect(find.text('Cảnh báo ngân sách đã lưu'), findsOneWidget);
    expect(find.byType(SegmentedButton<ThemeMode>), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);

    await tester.tap(find.text('Áp dụng trên thiết bị'));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('app.themeMode'), 'dark');
    expect(preferences.getBool('budget_alerts_enabled:user-1'), isFalse);
    expect(store.saved, isFalse);
  });
}

class _FakePreferencesStore extends Fake
    implements SupabaseProfilePreferencesStore {
  bool saved = false;

  @override
  bool get canSync => true;

  @override
  Future<ProfilePreferences> load() async =>
      const ProfilePreferences(themeMode: 'dark', budgetAlertsEnabled: false);

  @override
  Future<void> save({
    required String themeMode,
    required bool budgetAlertsEnabled,
  }) async {
    saved = true;
  }
}
