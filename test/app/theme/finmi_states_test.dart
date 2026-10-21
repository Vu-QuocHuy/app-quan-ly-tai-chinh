@Tags(['visual'])
library;

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hoadon_insight/app/theme/app_theme.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/dashboard/presentation/dashboard_screen.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/shared/widgets/app_error_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final cupertino = FontLoader('packages/cupertino_icons/CupertinoIcons');
    cupertino.addFont(
      rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
    );
    await cupertino.load();
    final vietnamese = FontLoader('Be Vietnam Pro');
    for (final weight in [400, 500, 600, 700]) {
      vietnamese.addFont(
        rootBundle.load('assets/fonts/BeVietnamPro-$weight.ttf'),
      );
    }
    await vietnamese.load();
    if (File('C:/Windows/Fonts/arial.ttf').existsSync()) {
      final loader = FontLoader('Roboto');
      loader.addFont(
        File(
          'C:/Windows/Fonts/arial.ttf',
        ).readAsBytes().then((data) => ByteData.sublistView(data)),
      );
      await loader.load();
    }
  });
  for (final state in ['loading', 'empty', 'error', 'partial']) {
    testWidgets('overview $state has useful feedback', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const snapshot = DashboardSnapshot(
        monthKey: '2026-10',
        totalMinor: 0,
        invoiceCount: 0,
        categoryTotals: {},
        dailyTotals: {},
        budgetLimitMinor: 0,
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardProvider.overrideWith(
              (ref) => switch (state) {
                'loading' => const Stream.empty(),
                'error' => Stream.error(StateError('offline')),
                _ => Stream.value(snapshot),
              },
            ),
            todayDashboardProvider.overrideWith(
              (ref, month) => Stream.value(snapshot),
            ),
            incomesProvider.overrideWith(
              (ref) => state == 'partial'
                  ? Stream.error(StateError('offline'))
                  : Stream.value(const []),
            ),
            filteredInvoiceSummariesProvider.overrideWith(
              (ref, query) => Stream.value(const []),
            ),
            budgetAlertsEnabledProvider.overrideWith((ref) async => false),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: RepaintBoundary(key: key, child: const DashboardScreen()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      if (state == 'error') expect(find.byType(AppErrorState), findsOneWidget);
      if (state == 'partial') {
        expect(find.text('Không tải được khoản thu'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      final render =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage();
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File(
          'artifacts/finmi/state-$state.png',
        ).writeAsBytes(bytes.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
