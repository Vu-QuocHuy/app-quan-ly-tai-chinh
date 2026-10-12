import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/income/data/income_repository.dart';
import 'package:hoadon_insight/features/income/presentation/income_entry_sheet.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

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
