import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoadon_insight/app/theme/app_theme.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/dashboard/presentation/dashboard_screen.dart';
import 'package:hoadon_insight/features/income/data/income_repository.dart';
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
      categoryBudgets: [
        CategoryBudgetStatus(
          categoryId: 'category-1',
          categoryName: 'Danh mục 1',
          limitMinor: 500000,
          spentMinor: 70000,
        ),
      ],
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
          incomesProvider.overrideWith(
            (ref) => Stream.value([
              IncomeEntry(
                id: 'fixed-income',
                amountMinor: 300000,
                source: IncomeSource.fixed,
                categoryId: 'income_salary',
                receivedAt: DateTime(2026, 9, 3),
                updatedAt: DateTime(2026, 9, 3),
              ),
              IncomeEntry(
                id: 'manual-income',
                amountMinor: 100000,
                source: IncomeSource.manual,
                categoryId: 'income_other',
                receivedAt: DateTime(2026, 9, 10),
                updatedAt: DateTime(2026, 9, 10),
              ),
            ]),
          ),
          monthlyExpenseTotalsProvider.overrideWith(
            (ref) => Stream.value(const <String, int>{}),
          ),
          dashboardProvider.overrideWith((ref) => Stream.value(snapshot)),
          spendingInsightsProvider.overrideWith(
            (ref) => Stream.value(insights),
          ),
          categoriesProvider.overrideWith((ref) => Stream.value(categories)),
          incomeCategoriesProvider.overrideWith(
            (ref) => Stream.value([
              const CategoryEntity(
                id: 'income_salary',
                name: 'Lương',
                iconName: 'payments',
                colorValue: 0xFF2563EB,
                kind: CategoryKind.income,
              ),
              const CategoryEntity(
                id: 'income_other',
                name: 'Khoản khác',
                iconName: 'category',
                colorValue: 0xFF64748B,
                kind: CategoryKind.income,
              ),
            ]),
          ),
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
      find.text('Trong hạn mức'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Trong hạn mức'), findsOneWidget);
    expect(find.textContaining('Vượt'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Chi tiêu theo ngày'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Chưa có dữ liệu chi tiêu'), findsOneWidget);
    final emptyChartCard = find
        .ancestor(
          of: find.text('Chưa có dữ liệu chi tiêu'),
          matching: find.byType(Card),
        )
        .first;
    expect(tester.getSize(emptyChartCard).height, lessThan(320));

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
    expect(chart.data.sections, hasLength(6));
    expect(
      chart.data.sections.map((section) => section.value),
      orderedEquals([70000, 60000, 50000, 40000, 30000, 30000]),
    );
    expect(
      chart.data.sections.map((section) => section.title),
      orderedEquals(['25%', '21%', '18%', '14%', '11%', '11%']),
    );
    expect(find.text('TỔNG CHI'), findsOneWidget);
    expect(find.text('Còn lại (2 danh mục)'), findsOneWidget);
    expect(chartCardBounds.height, greaterThan(chartBounds.height));
    expect(chartCardBounds.top, lessThan(chartBounds.top));
    expect(chartCardBounds.bottom, greaterThan(chartBounds.bottom));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('income-composition-chart')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    final incomeChart = tester.widget<PieChart>(
      find.byKey(const ValueKey('income-composition-chart')),
    );
    expect(
      incomeChart.data.sections.map((section) => section.value),
      orderedEquals([300000, 100000]),
    );
    expect(
      incomeChart.data.sections.map((section) => section.title),
      orderedEquals(['75%', '25%']),
    );
    expect(find.text('Lương'), findsOneWidget);
    expect(find.text('Khoản khác'), findsOneWidget);
    final fixedLabel = tester.getRect(
      find.byKey(const ValueKey('income-composition-label-income_salary')),
    );
    final fixedAmount = tester.getRect(
      find.byKey(const ValueKey('income-composition-amount-income_salary')),
    );
    expect((fixedLabel.center.dy - fixedAmount.center.dy).abs(), lessThan(1));
    await tester.scrollUntilVisible(
      find.text('Chi tiêu theo danh mục'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Chi tiêu theo danh mục'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Danh mục 7'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Danh mục 7'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('budget card warns about the top 3 most over-limit categories', (
    tester,
  ) async {
    CategoryBudgetStatus budget(String id, int spent) => CategoryBudgetStatus(
      categoryId: id,
      categoryName: 'Mục $id',
      limitMinor: 100000,
      spentMinor: spent,
    );
    final snapshot = DashboardSnapshot(
      monthKey: '2026-09',
      totalMinor: 900000,
      invoiceCount: 5,
      categoryTotals: const {},
      dailyTotals: const {},
      budgetLimitMinor: 500000,
      categoryBudgets: [
        budget('a', 110000),
        budget('b', 250000),
        budget('c', 50000),
        budget('d', 180000),
        budget('e', 140000),
      ],
    );
    const insights = SpendingInsights(
      monthKey: '2026-09',
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
          incomeCategoriesProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
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
      find.text('và 1 mục khác vượt hạn mức'),
      400,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('4 mục vượt'), findsOneWidget);
    expect(find.text('Mục b'), findsOneWidget);
    expect(find.text('Mục d'), findsOneWidget);
    expect(find.text('Mục e'), findsOneWidget);
    expect(find.text('Mục a'), findsNothing);
    expect(find.text('Mục c'), findsNothing);
    final topY = [
      'Mục b',
      'Mục d',
      'Mục e',
    ].map((name) => tester.getTopLeft(find.text(name)).dy).toList();
    expect(topY[0], lessThan(topY[1]));
    expect(topY[1], lessThan(topY[2]));
    expect(tester.takeException(), isNull);
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
          incomeCategoriesProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
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
    await tester.scrollUntilVisible(
      find.byType(LineChart),
      400,
      scrollable: find.byType(Scrollable).first,
    );

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
      find.text('Cơ cấu chi tiêu'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Cơ cấu chi tiêu'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Chi tiêu theo danh mục'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Chi tiêu theo danh mục'));
    await tester.pumpAndSettle();
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
          incomeCategoriesProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
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
      find.byType(LineChart),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    final dailyChartBounds = tester.getRect(find.byType(LineChart));
    expect(dailyChartBounds.width / dailyChartBounds.height, greaterThan(1.7));

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
    final cardMidpoint = chartCardBounds.center.dx;
    final legendRowBounds = tester.getRect(
      find.ancestor(of: find.text('Ăn uống'), matching: find.byType(Row)).first,
    );
    expect(chartBounds.center.dx, lessThan(cardMidpoint));
    expect(legendRowBounds.center.dx, greaterThan(cardMidpoint));
    expect(
      (legendRowBounds.left - chartCardBounds.left) / chartCardBounds.width,
      closeTo(2 / 3, 0.04),
    );
    expect(legendRowBounds.left - chartBounds.right, greaterThan(150));
    final legendLabel = tester.getRect(
      find.byKey(const ValueKey('composition-legend-label-category-1')),
    );
    final legendAmount = tester.getRect(
      find.byKey(const ValueKey('composition-legend-amount-category-1')),
    );
    expect(legendAmount.left, greaterThan(legendLabel.right));
    expect(legendAmount.right, lessThan(chartCardBounds.right));
    expect(chart.data.sections.single.title, '100%');
    expect(
      chart.data.sections.single.titleStyle?.color,
      chart.data.sections.single.color.computeLuminance() > 0.18
          ? Colors.black
          : Colors.white,
    );
    expect(
      find.byKey(const ValueKey('composition-legend-share-category-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('composition-center-share')),
      findsNothing,
    );
    expect(chartCardBounds.top + 36, lessThan(chartBounds.top));
    expect(chartCardBounds.bottom - 36, greaterThan(chartBounds.bottom));

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('composition-legend-category-1')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 140));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('composition-legend-category-1')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('composition-center-label')))
          .data,
      'Ăn uống',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('composition-center-share')))
          .data,
      '100% tổng chi',
    );

    tester.view.physicalSize = const Size(700, 1000);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('composition-legend-label-category-1')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    final narrowLegendLabel = tester.getRect(
      find.byKey(const ValueKey('composition-legend-label-category-1')),
    );
    final narrowLegendAmount = tester.getRect(
      find.byKey(const ValueKey('composition-legend-amount-category-1')),
    );
    expect(
      narrowLegendAmount.center.dy,
      closeTo(narrowLegendLabel.center.dy, 1),
    );
    expect(tester.takeException(), isNull);
  });
}
