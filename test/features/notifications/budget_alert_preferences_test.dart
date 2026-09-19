import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hoadon_insight/features/notifications/data/budget_alert_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'marks a notification as delivered only after the caller succeeds',
    () async {
      const preferences = BudgetAlertPreferences();

      expect(await preferences.canDeliver('2026-09:approaching'), isTrue);
      await preferences.markDelivered('2026-09:approaching');
      expect(await preferences.canDeliver('2026-09:approaching'), isFalse);
      expect(await preferences.canDeliver('2026-09:exceeded'), isTrue);
    },
  );

  test(
    'keeps preferences and deduplication isolated by account scope',
    () async {
      const firstAccount = BudgetAlertPreferences(scope: 'user-a');
      const secondAccount = BudgetAlertPreferences(scope: 'user-b');

      await firstAccount.setEnabled(false);
      await firstAccount.markDelivered('2026-09:approaching');

      expect(await firstAccount.isEnabled(), isFalse);
      expect(await firstAccount.canDeliver('2026-09:approaching'), isFalse);
      expect(await secondAccount.isEnabled(), isTrue);
      expect(await secondAccount.canDeliver('2026-09:approaching'), isTrue);
    },
  );

  test(
    'clearAll removes scoped and legacy preference state without touching another account',
    () async {
      const legacy = BudgetAlertPreferences();
      const firstAccount = BudgetAlertPreferences(scope: 'user-a');
      const secondAccount = BudgetAlertPreferences(scope: 'user-b');

      await legacy.setEnabled(false);
      await legacy.markDelivered('legacy');
      await firstAccount.setEnabled(false);
      await firstAccount.markDelivered('first');
      await secondAccount.setEnabled(false);
      await secondAccount.markDelivered('second');
      await firstAccount.clearAll();

      expect(await legacy.isEnabled(), isFalse);
      expect(await legacy.canDeliver('legacy'), isFalse);
      expect(await firstAccount.isEnabled(), isTrue);
      expect(await firstAccount.canDeliver('first'), isTrue);
      expect(await secondAccount.isEnabled(), isFalse);
      expect(await secondAccount.canDeliver('second'), isFalse);
    },
  );

  test('clears scoped and legacy notification state when requested', () async {
    const legacy = BudgetAlertPreferences();
    const account = BudgetAlertPreferences(scope: 'user-a');

    await legacy.setEnabled(false);
    await legacy.markDelivered('legacy');
    await account.setEnabled(false);
    await account.markDelivered('account');

    await account.clearAll(includeLegacy: true);

    expect(await legacy.isEnabled(), isTrue);
    expect(await legacy.canDeliver('legacy'), isTrue);
    expect(await account.isEnabled(), isTrue);
    expect(await account.canDeliver('account'), isTrue);
  });
}
