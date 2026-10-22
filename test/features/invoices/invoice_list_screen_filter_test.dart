import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/app/theme/app_theme.dart';
import 'package:hoadon_insight/core/config/feature_flags.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/income/data/income_repository.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/features/invoices/presentation/invoice_list_screen.dart';

import '../../helpers/fake_sync_coordinator.dart';

void main() {
  testWidgets('groups secondary filters and applies or clears them', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          filteredInvoiceSummariesProvider.overrideWith(
            (ref, query) => Stream.value(const <InvoiceEntity>[]),
          ),
          incomesProvider.overrideWith((ref) => Stream.value(<IncomeEntry>[])),
          categoriesProvider.overrideWith(
            (ref) => Stream.value([
              const CategoryEntity(
                id: 'food',
                name: 'Ăn uống',
                iconName: 'restaurant',
                colorValue: 0xff16806a,
              ),
            ]),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,

          theme: AppTheme.light(),
          home: const InvoiceListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tất cả'), findsOneWidget);
    expect(find.text('Khoản thu'), findsOneWidget);
    expect(find.text('Khoản chi'), findsOneWidget);
    expect(find.text('Mọi trạng thái'), findsNothing);
    expect(find.text('Danh mục'), findsNothing);
    expect(find.text('Tháng'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('transaction-filter-button')));
    await tester.pumpAndSettle();
    expect(find.text('Bộ lọc giao dịch'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Cần kiểm tra').last);
    await tester.tap(find.text('Áp dụng'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('transaction-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Xóa bộ lọc'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filters income transactions by their income category', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          filteredInvoiceSummariesProvider.overrideWith(
            (ref, query) => Stream.value(const <InvoiceEntity>[]),
          ),
          incomesProvider.overrideWith(
            (ref) => Stream.value([
              IncomeEntry(
                id: 'salary',
                amountMinor: 15000000,
                source: IncomeSource.manual,
                categoryId: 'income_salary',
                receivedAt: DateTime(2026, 9, 1),
                updatedAt: DateTime(2026, 9, 1),
              ),
              IncomeEntry(
                id: 'bonus',
                amountMinor: 2000000,
                source: IncomeSource.manual,
                categoryId: 'income_bonus',
                receivedAt: DateTime(2026, 9, 10),
                updatedAt: DateTime(2026, 9, 10),
              ),
            ]),
          ),
          incomeCategoriesProvider.overrideWith(
            (ref) => Stream.value(const [
              CategoryEntity(
                id: 'income_salary',
                name: 'Lương',
                iconName: 'payments',
                colorValue: 0xFF2563EB,
                kind: CategoryKind.income,
              ),
              CategoryEntity(
                id: 'income_bonus',
                name: 'Thưởng',
                iconName: 'redeem',
                colorValue: 0xFF0F766E,
                kind: CategoryKind.income,
              ),
            ]),
          ),
          categoriesProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,

          theme: AppTheme.light(),
          home: const InvoiceListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Khoản thu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transaction-filter-button')));
    await tester.pumpAndSettle();
    expect(find.text('Danh mục thu'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('transaction-category-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lương').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Áp dụng'));
    await tester.pumpAndSettle();

    expect(find.text('Lương'), findsOneWidget);
    expect(find.text('Thưởng'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pulling down syncs with the cloud', (tester) async {
    tester.view.physicalSize = const Size(700, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final coordinator = FakeSyncCoordinator();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          filteredInvoiceSummariesProvider.overrideWith(
            (ref, query) => Stream.value(const <InvoiceEntity>[]),
          ),
          incomesProvider.overrideWith((ref) => Stream.value(<IncomeEntry>[])),
          categoriesProvider.overrideWith((ref) => Stream.value(const [])),
          featureFlagsProvider.overrideWith(
            (ref) async => FeatureFlags.defaults,
          ),
          syncCoordinatorProvider.overrideWithValue(coordinator),
        ],
        child: MaterialApp(
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,

          theme: AppTheme.light(),
          home: const InvoiceListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(coordinator.calls, 1);
  });
}
