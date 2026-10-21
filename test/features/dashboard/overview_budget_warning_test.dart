import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hoadon_insight/app/theme/app_theme.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/dashboard/presentation/dashboard_screen.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  CategoryBudgetStatus budget(String id, int spent) => CategoryBudgetStatus(
    categoryId: id,
    categoryName: 'Mục $id',
    limitMinor: 100000,
    spentMinor: spent,
  );

  Future<void> pumpOverview(
    WidgetTester tester,
    List<CategoryBudgetStatus> budgets,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 2000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final snapshot = DashboardSnapshot(
      monthKey: '2026-10',
      totalMinor: 900000,
      invoiceCount: 5,
      categoryTotals: const {},
      dailyTotals: const {},
      // Tổng hạn mức nhỏ hơn tổng chi: không được cảnh báo theo tổng.
      budgetLimitMinor: 500000,
      categoryBudgets: budgets,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardProvider.overrideWith((ref) => Stream.value(snapshot)),
          todayDashboardProvider.overrideWith(
            (ref, month) => Stream.value(snapshot),
          ),
          incomesProvider.overrideWith((ref) => Stream.value(const [])),
          filteredInvoiceSummariesProvider.overrideWith(
            (ref, query) => Stream.value(const []),
          ),
          budgetAlertsEnabledProvider.overrideWith((ref) async => false),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const DashboardScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('shows the top 3 most over-limit categories', (tester) async {
    await pumpOverview(tester, [
      budget('a', 110000),
      budget('b', 250000),
      budget('c', 50000),
      budget('d', 180000),
      budget('e', 140000),
    ]);

    expect(find.text('4 danh mục vượt hạn mức'), findsOneWidget);
    expect(find.text('và 1 mục khác vượt hạn mức'), findsOneWidget);
    for (final name in ['Mục b', 'Mục d', 'Mục e']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Mục a'), findsNothing);
    expect(find.text('Mục c'), findsNothing);
    final y = [
      'Mục b',
      'Mục d',
      'Mục e',
    ].map((name) => tester.getTopLeft(find.text(name)).dy).toList();
    expect(y[0], lessThan(y[1]));
    expect(y[1], lessThan(y[2]));
    expect(tester.takeException(), isNull);
  });

  testWidgets('hides the warning when no category is over its limit', (
    tester,
  ) async {
    await pumpOverview(tester, [budget('a', 90000)]);

    expect(find.byKey(const ValueKey('budget-warning-card')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
