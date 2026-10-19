import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/income/data/income_repository.dart';
import 'package:hoadon_insight/features/income/presentation/income_entry_sheet.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_repository.dart';

void main() {
  testWidgets('saves the selected income category', (tester) async {
    final repository = _FakeIncomeRepository();
    const categories = [
      CategoryEntity(
        id: 'income_salary',
        name: 'Lương',
        iconName: 'category',
        colorValue: 0xFF2563EB,
        kind: CategoryKind.income,
      ),
      CategoryEntity(
        id: 'income_bonus',
        name: 'Thưởng',
        iconName: 'category',
        colorValue: 0xFF0F766E,
        kind: CategoryKind.income,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          incomeRepositoryProvider.overrideWithValue(repository),
          incomeCategoriesProvider.overrideWith(
            (ref) => Stream.value(categories),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const IncomeEntrySheet(),
                ),
                child: const Text('Mở khoản thu'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở khoản thu'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField).first).keyboardType,
      const TextInputType.numberWithOptions(decimal: false),
    );

    await tester.enterText(find.byType(TextField), '250000');
    await tester.tap(
      find.byKey(const ValueKey('income-category-income_salary')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thưởng').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu khoản thu'));
    await tester.pumpAndSettle();

    expect(repository.savedCategoryId, 'income_bonus');
    expect(repository.savedAmount, 250000);
  });

  testWidgets(
    'creates and selects a custom income category while entering income',
    (tester) async {
      final incomes = _FakeIncomeRepository();
      final categories = <CategoryEntity>[];
      late final StreamController<List<CategoryEntity>> categoryStream;
      categoryStream = StreamController<List<CategoryEntity>>.broadcast(
        onListen: () => categoryStream.add(List.of(categories)),
      );
      addTearDown(categoryStream.close);
      final invoices = _FakeInvoiceRepository((category) {
        categories.add(category);
        categoryStream.add(List.of(categories));
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            incomeRepositoryProvider.overrideWithValue(incomes),
            invoiceRepositoryProvider.overrideWithValue(invoices),
            incomeCategoriesProvider.overrideWith(
              (ref) => categoryStream.stream,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => const IncomeEntrySheet(),
                  ),
                  child: const Text('Mở khoản thu'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở khoản thu'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '250000');
      await tester.tap(find.text('Thêm loại khoản thu'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('category-name-field')),
        'Việc tự do',
      );
      await tester.tap(find.text('Lưu danh mục'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu khoản thu'));
      await tester.pumpAndSettle();

      expect(invoices.savedCategory?.name, 'Việc tự do');
      expect(invoices.savedCategory?.kind, CategoryKind.income);
      expect(incomes.savedCategoryId, invoices.savedCategory?.id);
    },
  );
}

class _FakeIncomeRepository extends Fake implements IncomeRepository {
  int? savedAmount;
  String? savedCategoryId;

  @override
  Future<void> save(
    int amountMinor, {
    required IncomeSource source,
    String? categoryId,
    IncomeEntry? existing,
  }) async {
    savedAmount = amountMinor;
    savedCategoryId = categoryId;
  }
}

class _FakeInvoiceRepository extends Fake implements InvoiceRepository {
  _FakeInvoiceRepository(this.onSave);

  final void Function(CategoryEntity) onSave;
  CategoryEntity? savedCategory;

  @override
  Future<void> saveCategory(CategoryEntity category) async {
    savedCategory = category;
    onSave(category);
  }
}
