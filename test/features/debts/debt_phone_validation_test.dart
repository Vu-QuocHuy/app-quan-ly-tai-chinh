import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hoadon_insight/features/debts/data/debt_notification_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('DebtNotificationStore Phone & Account Validation Tests', () {
    test(
      'Saving user phone registers ownership and adds to registered phones',
      () async {
        const userAId = 'user-a-111';
        const phoneA = '0123456789';

        await DebtNotificationStore.setCurrentUserPhone(
          phoneA,
          userId: userAId,
        );

        // Verify user exists by phone
        final exists = await DebtNotificationStore.checkUserExistsByPhone(
          phoneA,
          null,
        );
        expect(exists, isTrue);

        // Verify phone is NOT taken for User A
        final isTakenForUserA =
            await DebtNotificationStore.isPhoneTakenByAnotherUser(
              phoneA,
              currentUserId: userAId,
            );
        expect(isTakenForUserA, isFalse);

        // Verify phone IS taken for User B
        final isTakenForUserB =
            await DebtNotificationStore.isPhoneTakenByAnotherUser(
              phoneA,
              currentUserId: 'user-b-222',
            );
        expect(isTakenForUserB, isTrue);
      },
    );

    test(
      'Unregistered phone returns false for checkUserExistsByPhone',
      () async {
        final exists = await DebtNotificationStore.checkUserExistsByPhone(
          '0999999999',
          null,
        );
        expect(exists, isFalse);
      },
    );

    test('Seed phones return true for checkUserExistsByPhone', () async {
      final exists = await DebtNotificationStore.checkUserExistsByPhone(
        '0234567890',
        null,
      );
      expect(exists, isTrue);
    });
  });
}
