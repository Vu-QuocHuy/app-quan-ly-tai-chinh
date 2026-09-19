import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/insights/data/anomaly_feedback_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists, restores and bounds dismissed anomaly feedback', () async {
    final store = const AnomalyFeedbackStore(maxEntries: 2);

    await store.dismiss('invoice-1');
    await store.dismiss('invoice-2');
    await store.dismiss('invoice-3');

    expect(await store.loadDismissedIds(), {'invoice-2', 'invoice-3'});
    await store.restore('invoice-2');
    expect(await store.loadDismissedIds(), {'invoice-3'});
  });

  test('clear removes all feedback', () async {
    const store = AnomalyFeedbackStore();
    await store.dismiss('invoice-1');
    await store.clear();

    expect(await store.loadDismissedIds(), isEmpty);
  });

  test('keeps feedback isolated by account scope', () async {
    const userOne = AnomalyFeedbackStore(scope: 'user-1');
    const userTwo = AnomalyFeedbackStore(scope: 'user-2');

    await userOne.dismiss('invoice-1');

    expect(await userTwo.loadDismissedIds(), isEmpty);
    expect(await userOne.loadDismissedIds(), {'invoice-1'});
  });

  test(
    'clearAll removes scoped feedback without touching legacy or another account',
    () async {
      const legacy = AnomalyFeedbackStore();
      const userOne = AnomalyFeedbackStore(scope: 'user-1');
      const userTwo = AnomalyFeedbackStore(scope: 'user-2');

      await legacy.dismiss('legacy-invoice');
      await userOne.dismiss('user-one-invoice');
      await userTwo.dismiss('user-two-invoice');
      await userOne.clearAll();

      expect(await legacy.loadDismissedIds(), {'legacy-invoice'});
      expect(await userOne.loadDismissedIds(), isEmpty);
      expect(await userTwo.loadDismissedIds(), {'user-two-invoice'});

      await userOne.clearAll(includeLegacy: true);
      expect(await legacy.loadDismissedIds(), isEmpty);
    },
  );
}
