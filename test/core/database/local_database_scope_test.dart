import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/database/local_database_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const legacyUser = '11111111-1111-4111-8111-111111111111';
  const otherUser = '22222222-2222-4222-8222-222222222222';

  test('uses the legacy database for the first bound account', () {
    expect(
      LocalDatabaseScope.databaseNameFor(
        userId: legacyUser,
        cloudConfigured: true,
        legacyOwnerId: legacyUser,
      ),
      LocalDatabaseScope.legacyDatabaseName,
    );
  });

  test('isolates another account and signed-out cloud state', () {
    expect(
      LocalDatabaseScope.databaseNameFor(
        userId: otherUser,
        cloudConfigured: true,
        legacyOwnerId: legacyUser,
      ),
      'hoadon_insight_user_22222222222242228222222222222222',
    );
    expect(
      LocalDatabaseScope.databaseNameFor(
        userId: null,
        cloudConfigured: true,
        legacyOwnerId: legacyUser,
      ),
      LocalDatabaseScope.signedOutDatabaseName,
    );
  });

  test('keeps the local-first database when cloud is unavailable', () {
    expect(
      LocalDatabaseScope.databaseNameFor(
        userId: null,
        cloudConfigured: false,
        legacyOwnerId: null,
      ),
      LocalDatabaseScope.legacyDatabaseName,
    );
  });

  test('validates account ids before selecting a local database', () {
    expect(LocalDatabaseScope.isValidUserId(legacyUser), isTrue);
    expect(LocalDatabaseScope.isValidUserId('not-a-user-id'), isFalse);
    expect(LocalDatabaseScope.isValidUserId(null), isFalse);
  });

  test('tracks and releases the legacy database owner', () async {
    await LocalDatabaseScope.initialize(userId: legacyUser);

    expect(await LocalDatabaseScope.ownsLegacyDatabase(legacyUser), isTrue);
    expect(await LocalDatabaseScope.ownsLegacyDatabase(otherUser), isFalse);

    await LocalDatabaseScope.releaseLegacyDatabase(otherUser);
    expect(await LocalDatabaseScope.ownsLegacyDatabase(legacyUser), isTrue);

    await LocalDatabaseScope.releaseLegacyDatabase(legacyUser);
    expect(await LocalDatabaseScope.ownsLegacyDatabase(legacyUser), isFalse);
  });
}
