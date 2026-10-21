import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/app/theme/app_theme.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/income/data/income_repository.dart';
import 'package:hoadon_insight/features/income/presentation/transaction_entry_sheet.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_repository.dart';

class _Income extends Fake implements IncomeRepository {
  int? amount;
  String? category, content;
  DateTime? date;
  @override
  Future<void> save(
    int amountMinor, {
    required IncomeSource source,
    String? categoryId,
    IncomeEntry? existing,
    String? note,
    DateTime? receivedAt,
  }) async {
    amount = amountMinor;
    category = categoryId;
    content = note;
    date = receivedAt;
  }
}

class _Expenses extends Fake implements InvoiceRepository {
  InvoiceEntity? saved;
  @override
  Future<void> saveInvoice(InvoiceEntity invoice) async => saved = invoice;
}

Future<void> _openForm(
  WidgetTester tester,
  _Income incomes,
  _Expenses expenses,
) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        incomeRepositoryProvider.overrideWithValue(incomes),
        invoiceRepositoryProvider.overrideWithValue(expenses),
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
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showTransactionEntry(context),
              child: const Text('Mở giao dịch'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Mở giao dịch'));
  await tester.pumpAndSettle();
}

Future<void> selectCategory(WidgetTester tester, String name) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'two tabs retain drafts and income saves content/category/selected date',
    (tester) async {
      final income = _Income(), expense = _Expenses();
      await _openForm(tester, income, expense);
      expect(find.text('Thêm khoản thu'), findsOneWidget);
      expect(find.text('Thêm khoản chi'), findsOneWidget);
      final today = DateUtils.dateOnly(DateTime.now());
      expect(
        find.text(
          'Ngày giao dịch: ${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}',
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).first, '125.000');
      await tester.enterText(find.byType(TextField).last, 'Lương thử việc');
      await selectCategory(tester, 'Lương');
      await tester.tap(find.text('Thêm khoản chi'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '75000');
      await tester.tap(find.text('Thêm khoản thu'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '125.000',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'Lương thử việc',
      );
      await tester.ensureVisible(find.textContaining('Ngày giao dịch:'));
      await tester.tap(find.textContaining('Ngày giao dịch:'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Lưu giao dịch'));
      await tester.tap(find.text('Lưu giao dịch'));
      await tester.pumpAndSettle();
      expect(income.amount, 125000);
      expect(income.category, 'salary');
      expect(income.content, 'Lương thử việc');
      expect(income.date, DateTime(today.year, today.month, 15));
      expect(expense.saved, isNull);
      expect(find.byType(TransactionEntrySheet), findsNothing);
    },
  );
  testWidgets(
    'expense validates input and saves confirmed manual transaction for today',
    (tester) async {
      final income = _Income(), expense = _Expenses();
      await _openForm(tester, income, expense);
      await tester.tap(find.text('Thêm khoản chi'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Lưu giao dịch'));
      await tester.tap(find.text('Lưu giao dịch'));
      await tester.pumpAndSettle();
      expect(find.text('Chọn danh mục giao dịch.'), findsOneWidget);
      expect(expense.saved, isNull);
      await tester.ensureVisible(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, '75000');
      await selectCategory(tester, 'Ăn uống');
      await tester.enterText(find.byType(TextField).last, 'Ăn trưa');
      await tester.ensureVisible(find.text('Lưu giao dịch'));
      await tester.tap(find.text('Lưu giao dịch'));
      await tester.pumpAndSettle();
      expect(expense.saved!.totalMinor, 75000);
      expect(expense.saved!.notes, 'Ăn trưa');
      expect(expense.saved!.categoryId, 'food');
      expect(expense.saved!.status, InvoiceStatus.confirmed);
      expect(expense.saved!.sourceType, InvoiceSourceType.manual);
      expect(expense.saved!.issuedAt, DateUtils.dateOnly(DateTime.now()));
      expect(income.amount, isNull);
    },
  );
}
