import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/dashboard/presentation/dashboard_screen.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  testWidgets('keeps dashboard charts visible and blank without data', (
    tester,
  ) async {
    const monthKey = '2026-09';
    const snapshot = DashboardSnapshot(
      monthKey: monthKey,
      totalMinor: 0,
      invoiceCount: 0,
      categoryTotals: {},
      dailyTotals: {},
      budgetLimitMinor: 0,
    );
    const insights = SpendingInsights(
      monthKey: monthKey,
      forecastTotalMinor: 0,
      currentTotalMinor: 0,
      recurringExpenses: [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardProvider.overrideWith((ref) => Stream.value(snapshot)),
          spendingInsightsProvider.overrideWith(
            (ref) => Stream.value(insights),
          ),
          categoriesProvider.overrideWith((ref) => Stream.value(const [])),
          budgetAlertsEnabledProvider.overrideWith((ref) async => false),
          dismissedAnomalyIdsProvider.overrideWith((ref) async => const {}),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Chi tiêu theo ngày'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Chi tiêu theo ngày'), findsOneWidget);
    expect(find.text('Chưa có dữ liệu chi tiêu'), findsNothing);

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData, isEmpty);

    await tester.scrollUntilVisible(
      find.text('Theo danh mục'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Theo danh mục'), findsOneWidget);
    expect(find.text('Chưa có danh mục nào'), findsNothing);
  });
}
