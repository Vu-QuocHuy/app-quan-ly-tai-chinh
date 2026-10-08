import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoadon_insight/app/theme/app_theme.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/dashboard/presentation/dashboard_screen.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  testWidgets('shows category composition and useful budget details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const monthKey = '2026-09';
    const snapshot = DashboardSnapshot(
      monthKey: monthKey,
      totalMinor: 280000,
      invoiceCount: 7,
      categoryTotals: {
        'category-1': 70000,
        'category-2': 60000,
        'category-3': 50000,
        'category-4': 40000,
        'category-5': 30000,
        'category-6': 20000,
        'category-7': 10000,
      },
      dailyTotals: {},
      budgetLimitMinor: 500000,
    );
    const insights = SpendingInsights(
      monthKey: monthKey,
      forecastTotalMinor: 0,
      currentTotalMinor: 0,
      recurringExpenses: [],
    );
    final categories = List<CategoryEntity>.generate(
      7,
      (index) => CategoryEntity(
        id: 'category-${index + 1}',
        name: 'Danh mục ${index + 1}',
        iconName: '',
        colorValue: 0xff16806a + index * 0x00080808,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectedMonthProvider.overrideWith((ref) => DateTime(2026, 9)),
          incomesProvider.overrideWith((ref) => Stream.value(const [])),
          monthlyExpenseTotalsProvider.overrideWith(
            (ref) => Stream.value(const <String, int>{}),
          ),
          dashboardProvider.overrideWith((ref) => Stream.value(snapshot)),
          spendingInsightsProvider.overrideWith(
            (ref) => Stream.value(insights),
          ),
          categoriesProvider.overrideWith((ref) => Stream.value(categories)),
          budgetAlertsEnabledProvider.overrideWith((ref) async => false),
          dismissedAnomalyIdsProvider.overrideWith((ref) async => const {}),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('56%'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Trong hạn mức'), findsOneWidget);
    expect(find.textContaining('Còn lại'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byType(PieChart),
      400,
      scrollable: find.byType(Scrollable).first,
    );

    final chart = tester.widget<PieChart>(find.byType(PieChart));
    final chartBounds = tester.getRect(find.byType(PieChart));
    final chartCardBounds = tester.getRect(
      find
          .ancestor(of: find.byType(PieChart), matching: find.byType(Card))
          .first,
    );
    final lastLegendLabel = tester.getRect(find.text('Còn lại (2 danh mục)'));
    expect(chart.data.sections, hasLength(6));
    expect(
      chart.data.sections.map((section) => section.value),
      orderedEquals([70000, 60000, 50000, 40000, 30000, 30000]),
    );
    expect(find.text('TỔNG CHI'), findsOneWidget);
    expect(find.text('Còn lại (2 danh mục)'), findsOneWidget);
    expect(chartCardBounds.height, greaterThan(chartBounds.height));
    expect(chartCardBounds.top, lessThan(chartBounds.top));
    expect(chartCardBounds.bottom, greaterThan(chartBounds.bottom));
    expect(lastLegendLabel.top, greaterThan(chartBounds.bottom));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('plots every day and puts missing daily totals at zero', (
    tester,
  ) async {
    const monthKey = '2026-09';
    const snapshot = DashboardSnapshot(
      monthKey: monthKey,
      totalMinor: 175000,
      invoiceCount: 2,
      categoryTotals: {},
      dailyTotals: {3: 125000, 10: 50000},
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
          selectedMonthProvider.overrideWith((ref) => DateTime(2026, 9)),
          incomesProvider.overrideWith((ref) => Stream.value(const [])),
          monthlyExpenseTotalsProvider.overrideWith(
            (ref) => Stream.value(const <String, int>{}),
          ),
          dashboardProvider.overrideWith((ref) => Stream.value(snapshot)),
          spendingInsightsProvider.overrideWith(
            (ref) => Stream.value(insights),
          ),
          categoriesProvider.overrideWith((ref) => Stream.value(const [])),
          budgetAlertsEnabledProvider.overrideWith((ref) async => false),
          dismissedAnomalyIdsProvider.overrideWith((ref) async => const {}),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const DashboardScreen(),
        ),
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
    final spots = chart.data.lineBarsData.single.spots;
    expect(spots, hasLength(30));
    expect(
      spots.map((spot) => spot.x),
      orderedEquals(
        List<double>.generate(30, (index) => (index + 1).toDouble()),
      ),
    );
    expect(spots[0].y, 0);
    expect(spots[2].y, 125000);
    expect(spots[8].y, 0);
    expect(spots[9].y, 50000);
    expect(chart.data.gridData.show, isTrue);
    expect(chart.data.gridData.drawVerticalLine, isFalse);
    expect(chart.data.gridData.horizontalInterval, closeTo(125000 / 3, 0.001));

    await tester.scrollUntilVisible(
      find.text('Chi tiêu theo danh mục'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Chi tiêu theo danh mục'), findsOneWidget);
    expect(find.text('Chưa có khoản chi theo danh mục.'), findsOneWidget);
  });

  testWidgets('keeps dashboard sections stacked on a wide screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const snapshot = DashboardSnapshot(
      monthKey: '2026-09',
      totalMinor: 70000,
      invoiceCount: 1,
      categoryTotals: {'category-1': 70000},
      dailyTotals: {3: 70000},
      budgetLimitMinor: 0,
    );
    const insights = SpendingInsights(
      monthKey: '2026-09',
      forecastTotalMinor: 0,
      currentTotalMinor: 0,
      recurringExpenses: [],
    );
    final categories = [
      CategoryEntity(
        id: 'category-1',
        name: 'Ăn uống',
        iconName: '',
        colorValue: 0xff16806a,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectedMonthProvider.overrideWith((ref) => DateTime(2026, 9)),
          incomesProvider.overrideWith((ref) => Stream.value(const [])),
          monthlyExpenseTotalsProvider.overrideWith(
            (ref) => Stream.value(const <String, int>{}),
          ),
          dashboardProvider.overrideWith((ref) => Stream.value(snapshot)),
          spendingInsightsProvider.overrideWith(
            (ref) => Stream.value(insights),
          ),
          categoriesProvider.overrideWith((ref) => Stream.value(categories)),
          budgetAlertsEnabledProvider.overrideWith((ref) async => false),
          dismissedAnomalyIdsProvider.overrideWith((ref) async => const {}),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Cơ cấu chi tiêu'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    final dailyHeading = tester.getTopLeft(find.text('Chi tiêu theo ngày'));
    final categoryHeading = tester.getTopLeft(find.text('Cơ cấu chi tiêu'));
    expect(dailyHeading.dy, lessThan(categoryHeading.dy));

    await tester.scrollUntilVisible(
      find.byType(PieChart),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    final chartBounds = tester.getRect(find.byType(PieChart));
    final chartCardBounds = tester.getRect(
      find
          .ancestor(of: find.byType(PieChart), matching: find.byType(Card))
          .first,
    );
    final cardMidpoint = chartCardBounds.center.dx;
    final legendRowBounds = tester.getRect(
      find.ancestor(of: find.text('Ăn uống'), matching: find.byType(Row)).first,
    );
    expect(legendRowBounds.center.dx, greaterThan(cardMidpoint));
    expect(
      chartBounds.center.dx,
      closeTo(cardMidpoint - (chartCardBounds.width - 32) / 4, 3),
    );
    expect(chartCardBounds.top + 36, lessThan(chartBounds.top));
    expect(chartCardBounds.bottom - 36, greaterThan(chartBounds.bottom));
    expect(tester.takeException(), isNull);
  });
}
