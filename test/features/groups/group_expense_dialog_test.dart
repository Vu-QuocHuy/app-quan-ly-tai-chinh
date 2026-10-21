import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/groups/domain/group_models.dart';
import 'package:hoadon_insight/features/groups/presentation/group_expense_dialog.dart';

const _members = [
  GroupMember(userId: 'u1', displayName: 'Huy', role: 'owner'),
  GroupMember(userId: 'u2', displayName: 'Lan', role: 'member'),
];

Future<void> _open(WidgetTester tester, Widget dialog) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () =>
              showDialog<void>(context: context, builder: (_) => dialog),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester, String label) => tester
    .widget<TextField>(find.widgetWithText(TextField, label))
    .controller!
    .text;

void main() {
  testWidgets('điền sẵn nội dung và tổng tiền từ hóa đơn', (tester) async {
    await _open(
      tester,
      const GroupExpenseDialog(
        members: _members,
        initialDescription: 'Hóa đơn Highlands',
        initialTotalMinor: 120000,
      ),
    );
    expect(_fieldText(tester, 'Nội dung'), 'Hóa đơn Highlands');
    expect(_fieldText(tester, 'Tổng tiền'), '120000');
    expect(find.text('Chia tiền'), findsWidgets);
  });

  testWidgets('tổng tiền 0 từ OCR thì để trống ô tổng tiền', (tester) async {
    await _open(
      tester,
      const GroupExpenseDialog(
        members: _members,
        initialDescription: 'Hóa đơn',
        initialTotalMinor: 0,
      ),
    );
    expect(_fieldText(tester, 'Tổng tiền'), isEmpty);
  });

  testWidgets('khi sửa thì bỏ qua giá trị điền sẵn', (tester) async {
    await _open(
      tester,
      GroupExpenseDialog(
        members: _members,
        initialDescription: 'Khác',
        initialTotalMinor: 1,
        initialExpense: GroupExpense(
          id: 'e1',
          groupId: 'g1',
          payerId: 'u1',
          description: 'Ăn trưa',
          totalMinor: 50000,
          createdAt: DateTime(2026, 10, 20),
          splits: const [
            GroupExpenseSplit(userId: 'u1', amountMinor: 25000),
            GroupExpenseSplit(userId: 'u2', amountMinor: 25000),
          ],
        ),
      ),
    );
    expect(_fieldText(tester, 'Nội dung'), 'Ăn trưa');
    expect(_fieldText(tester, 'Tổng tiền'), '50000');
    expect(find.text('Sửa lần chia tiền'), findsOneWidget);
  });

  testWidgets('submit trả bản nháp chia đều cho mọi thành viên', (
    tester,
  ) async {
    final key = GlobalKey<GroupExpenseFormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GroupExpenseForm(key: key, members: _members),
          ),
        ),
      ),
    );
    expect(key.currentState!.submit(), isNull);
    await tester.pump();
    expect(
      find.text('Hãy nhập nội dung, tổng tiền và chọn thành viên.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Nội dung'),
      'Ăn tối',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Tổng tiền'),
      '90000',
    );
    expect(key.currentState!.hasChanges, isTrue);
    final draft = key.currentState!.submit()!;
    expect(draft.description, 'Ăn tối');
    expect(draft.totalMinor, 90000);
    expect(draft.memberIds.toSet(), {'u1', 'u2'});
    expect(draft.splitAmounts, isNull);
  });

  test('mô tả từ hóa đơn có tên, không tên, và tên quá dài', () {
    expect(receiptExpenseDescription('  Highlands  '), 'Hóa đơn Highlands');
    expect(receiptExpenseDescription('   '), 'Hóa đơn');
    final long = receiptExpenseDescription('A' * 300);
    expect(long.length, 160);
    expect(long, startsWith('Hóa đơn AAA'));
  });
}
