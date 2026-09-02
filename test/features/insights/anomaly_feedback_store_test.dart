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
}
