import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/app/theme/app_theme.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/dashboard/presentation/statistics_screen.dart';
import 'package:hoadon_insight/features/income/data/income_repository.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

InvoiceEntity expense(
  String id,
  DateTime date,
  int amount, {
  InvoiceStatus status = InvoiceStatus.confirmed,
}) => InvoiceEntity(
  id: id,
  sellerName: id,
  currencyCode: 'VND',
  subtotalMinor: amount,
  taxMinor: 0,
  totalMinor: amount,
  sourceType: InvoiceSourceType.manual,
  status: status,
  createdAt: date,
  updatedAt: date,
  issuedAt: date,
  categoryId: 'food',
);

Future<void> pumpStatistics(
  WidgetTester tester, {
  List<InvoiceEntity>? expenses,
}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        selectedMonthProvider.overrideWith((ref) => DateTime(2026, 9)),
        invoiceSummariesProvider.overrideWith(
          (ref) => Stream.value(
            expenses ??
                [
                  expense('Lunch', DateTime(2026, 9, 1), 40000),
                  expense('October', DateTime(2026, 10, 1), 120000),
                  expense(
                    'Draft',
                    DateTime(2026, 9, 1),
                    90000,
                    status: InvoiceStatus.needsReview,
                  ),
                ],
          ),
        ),
        incomesProvider.overrideWith(
          (ref) => Stream.value([
            IncomeEntry(
              id: 'salary',
              amountMinor: 100000,
              source: IncomeSource.manual,
              categoryId: 'salary',
              receivedAt: DateTime(2026, 9, 1),
              updatedAt: DateTime(2026, 9, 1),
            ),
          ]),
        ),
        dashboardProvider.overrideWith((ref) => const Stream.empty()),
        categoriesProvider.overrideWith(
          (ref) => Stream.value(const [
            CategoryEntity(
              id: 'food',
              name: 'Ăn uống',
              iconName: 'restaurant',
              colorValue: 0xFF123D32,
            ),
          ]),
        ),
        incomeCategoriesProvider.overrideWith(
          (ref) => Stream.value(const [
            CategoryEntity(
              id: 'salary',
              name: 'Lương',
              iconName: 'payments',
              colorValue: 0xFF236447,
              kind: CategoryKind.income,
            ),
          ]),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,

        theme: AppTheme.light(),
        home: const StatisticsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> reveal(
  WidgetTester tester,
  Finder finder, {
  double delta = 300,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'calendar day selection scopes both charts and real transactions',
    (tester) async {
      await pumpStatistics(tester);
      expect(find.text('Cơ cấu danh mục'), findsNothing);
      expect(find.text('+60K'), findsOneWidget);
      await tester.tap(find.text('+60K'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('statistics-period')));
      expect(find.text('Biểu đồ · Ngày 01/09/2026'), findsOneWidget);
      await reveal(tester, find.byType(BarChart));
      final flow = tester.widget<BarChart>(find.byType(BarChart));
      expect(flow.data.barGroups, hasLength(1));
      expect(flow.data.barGroups.single.barRods.map((r) => r.toY), [
        100000,
        40000,
      ]);
      await reveal(tester, find.byType(PieChart));
      expect(
        tester
            .widget<PieChart>(find.byType(PieChart))
            .data
            .sections
            .single
            .value,
        40000,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<bool>).last,
          matching: find.text('Khoản thu'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PieChart>(find.byType(PieChart))
            .data
            .sections
            .single
            .value,
        100000,
      );
      await reveal(tester, find.text('Lunch'));
      expect(find.text('Draft'), findsNothing);
      expect(find.text('October'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('year grid and selected month share the chart period', (
    tester,
  ) async {
    await pumpStatistics(tester);
    await tester.tap(find.text('Theo năm'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Tháng 9'));
    await tester.tap(find.text('Tháng 9'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const ValueKey('statistics-period')));
    expect(find.text('Biểu đồ · Tháng 9/2026'), findsOneWidget);
    await reveal(tester, find.byType(BarChart));
    final monthly = tester.widget<BarChart>(find.byType(BarChart));
    expect(monthly.data.barGroups, hasLength(30));
    expect(monthly.data.barGroups.first.barRods.map((r) => r.toY), [
      100000,
      40000,
    ]);
    expect(monthly.data.barGroups[1].barRods.map((r) => r.toY), [0, 0]);
    await reveal(tester, find.text('Xem toàn năm'), delta: -300);
    await tester.tap(find.text('Xem toàn năm'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byType(BarChart));
    final yearly = tester.widget<BarChart>(find.byType(BarChart));
    expect(yearly.data.barGroups, hasLength(12));
    expect(yearly.data.barGroups[9].barRods[1].toY, 120000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty periods have compact explanatory chart states', (
    tester,
  ) async {
    await pumpStatistics(tester, expenses: []);
    await tester.tap(find.text('Theo năm'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Tháng 2'));
    await tester.tap(find.text('Tháng 2'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Chưa có dữ liệu thu chi'));
    expect(find.byType(BarChart), findsNothing);
    await reveal(tester, find.text('Phân bổ thu chi'));
    expect(find.byType(PieChart), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
