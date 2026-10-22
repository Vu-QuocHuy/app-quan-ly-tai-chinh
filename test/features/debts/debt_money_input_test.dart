import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/debts/data/debt_repository.dart';
import 'package:hoadon_insight/features/debts/domain/debt_models.dart';
import 'package:hoadon_insight/features/debts/presentation/debt_entry_sheet.dart';
import 'package:hoadon_insight/features/debts/presentation/debt_settle_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const repository = DebtRepository();
  final debt = DebtRecord(
    id: 'debt-1',
    personName: 'Lan',
    type: DebtType.theyOwe,
    amountMinor: 1000000,
    paidAmountMinor: 250000,
    createdAt: DateTime(2026),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await repository.saveDebts([debt]);
  });

  Future<void> open(WidgetTester tester, {required bool settle}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [debtRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => settle
                    ? showDebtSettleDialog(context, ref, debt)
                    : showDebtEntrySheet(context, existing: debt),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('editing a debt displays grouped money and persists whole VND', (
    tester,
  ) async {
    await open(tester, settle: false);
    final amount = find.byType(TextFormField).at(1);
    expect(tester.widget<TextFormField>(amount).controller!.text, '1.000.000');
    await tester.enterText(amount, '1250000');
    await tester.ensureVisible(find.text('Lưu thay đổi'));
    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();
    expect((await repository.loadDebts()).single.amountMinor, 1250000);
  });

  testWidgets(
    'partial payment parses grouped VND without changing the debt total',
    (tester) async {
      await open(tester, settle: true);
      await tester.tap(find.text('Thanh toán một phần'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '750.000',
      );
      await tester.enterText(find.byType(TextField), '125000');
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      final result = (await repository.loadDebts()).single;
      expect(result.amountMinor, 1000000);
      expect(result.paidAmountMinor, 375000);
    },
  );
}
