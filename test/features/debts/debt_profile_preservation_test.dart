// SupabaseClient subscribes to this stream during construction.
// ignore_for_file: invalid_use_of_internal_member

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/auth/data/personal_profile_store.dart';
import 'package:hoadon_insight/features/debts/data/debt_notification_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Auth extends Mock implements GoTrueClient {}

class _ProfileClient extends SupabaseClient {
  _ProfileClient(this.testAuth, http.Client transport)
    : super('https://example.supabase.co', 'test-key', httpClient: transport);

  final GoTrueClient testAuth;

  @override
  GoTrueClient get auth => testAuth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('caching a loaded phone does not write the cloud profile', () async {
    final requests = <http.Request>[];
    final auth = _Auth();
    when(
      () => auth.onAuthStateChangeSync,
    ).thenAnswer((_) => const Stream.empty());
    when(() => auth.currentUser).thenReturn(
      const User(
        id: 'user-1',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '',
      ),
    );
    final client = _ProfileClient(
      auth,
      MockClient((request) async {
        requests.add(request);
        return http.Response('null', 200);
      }),
    );
    await DebtNotificationStore.setCurrentUserPhone(
      '0912345678',
      client: client,
      syncProfile: false,
    );
    expect(requests, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('finmi.user_phone.user-1.v1'), '0912345678');
  });

  test(
    'updating a phone preserves the name stored in the cloud profile',
    () async {
      final requests = <http.Request>[];
      final auth = _Auth();
      when(
        () => auth.onAuthStateChangeSync,
      ).thenAnswer((_) => const Stream.empty());
      when(() => auth.currentUser).thenReturn(
        const User(
          id: 'user-1',
          appMetadata: {},
          userMetadata: {'full_name': 'Old OAuth name'},
          aud: 'authenticated',
          createdAt: '',
        ),
      );
      final client = _ProfileClient(
        auth,
        MockClient((request) async {
          requests.add(request);
          return http.Response(
            request.method == 'GET'
                ? jsonEncode({
                    'display_name': 'Tên đã sửa',
                    'phone': '0900000000',
                  })
                : 'null',
            200,
            request: request,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      expect(
        (await PersonalProfileStore(client).load()).displayName,
        'Tên đã sửa',
      );
      requests.clear();
      await DebtNotificationStore.setCurrentUserPhone(
        '0912345678',
        client: client,
      );
      expect(requests.map((request) => request.method), ['GET', 'POST']);
      expect(jsonDecode(requests.last.body), {
        'p_display_name': 'Tên đã sửa',
        'p_phone': '0912345678',
      });
    },
  );
}
