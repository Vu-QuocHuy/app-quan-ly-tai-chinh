import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoadon_insight/app/theme/app_theme.dart';
import 'package:hoadon_insight/core/config/feature_flags.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/shared/widgets/app_refresh.dart';

import '../../helpers/fake_sync_coordinator.dart';

void main() {
  Future<void> pumpRefreshable(
    WidgetTester tester, {
    required FakeSyncCoordinator coordinator,
    bool cloudSync = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          featureFlagsProvider.overrideWith(
            (ref) async => FeatureFlags(cloudSync: cloudSync),
          ),
          syncCoordinatorProvider.overrideWithValue(coordinator),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => AppRefreshIndicator(
                onRefresh: () => refreshFromCloud(context, ref),
                // Danh sách ngắn hơn màn hình vẫn phải kéo được.
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [Text('Nội dung')],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pullDown(WidgetTester tester) async {
    await tester.fling(find.text('Nội dung'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
  }

  testWidgets('pulling down runs a cloud sync', (tester) async {
    final coordinator = FakeSyncCoordinator();
    await pumpRefreshable(tester, coordinator: coordinator);

    await pullDown(tester);

    expect(coordinator.calls, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('skips the sync when cloud sync is turned off', (tester) async {
    final coordinator = FakeSyncCoordinator();
    await pumpRefreshable(tester, coordinator: coordinator, cloudSync: false);

    await pullDown(tester);

    expect(coordinator.calls, 0);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('shows a snackbar when the sync fails', (tester) async {
    final coordinator = FakeSyncCoordinator(error: StateError('mất mạng'));
    await pumpRefreshable(tester, coordinator: coordinator);

    await pullDown(tester);

    expect(coordinator.calls, 1);
    expect(find.textContaining('Không thể đồng bộ'), findsOneWidget);
  });
}
