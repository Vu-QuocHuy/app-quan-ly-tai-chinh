import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/core/utils/money_formatter.dart';
import 'package:hoadon_insight/features/groups/data/group_service.dart';
import 'package:hoadon_insight/features/groups/domain/external_bill.dart';
import 'package:hoadon_insight/features/groups/presentation/external_bills_section.dart';

ExternalBill _bill({
  int myAmountMinor = 200000,
  DateTime? mySettledAt,
  bool someoneSettled = false,
}) => ExternalBill(
  id: 'bill-1',
  description: 'Ăn tối',
  totalMinor: 600000,
  createdAt: DateTime(2026, 10, 21),
  payerName: 'Huy',
  isOpen: !someoneSettled,
  myAmountMinor: myAmountMinor,
  mySettledAt: mySettledAt,
  participants: [
    ExternalBillParticipant(
      name: 'Huy',
      amountMinor: 600000 - 2 * myAmountMinor,
      settled: false,
      isMe: false,
    ),
    ExternalBillParticipant(
      name: 'Lan',
      amountMinor: myAmountMinor,
      settled: someoneSettled,
      isMe: false,
    ),
    ExternalBillParticipant(
      name: 'Dũng',
      amountMinor: myAmountMinor,
      settled: mySettledAt != null,
      isMe: true,
    ),
  ],
);

Future<_FakeExpenseGroupService> _pump(
  WidgetTester tester,
  List<ExternalBill> bills, {
  bool failSettle = false,
}) async {
  final service = _FakeExpenseGroupService(bills, failSettle: failSettle);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [expenseGroupServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ExternalBillsSection()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

void main() {
  testWidgets('danh sách rỗng thì ẩn mục', (tester) async {
    await _pump(tester, const []);

    expect(find.text('Bill bạn tham gia'), findsNothing);
  });

  testWidgets('có bill thì hiện phần của mình và hai nút', (tester) async {
    await _pump(tester, [_bill()]);

    expect(find.text('Bill bạn tham gia'), findsOneWidget);
    expect(find.text('Người trả: Huy'), findsOneWidget);
    expect(
      find.text('Phần của bạn: ${MoneyFormatter.format(200000)}'),
      findsOneWidget,
    );
    expect(find.text('Tôi đã thanh toán'), findsOneWidget);
    expect(find.text('Rời bill'), findsOneWidget);
  });

  testWidgets('bill mình đã trả thì không còn nút Tôi đã thanh toán', (
    tester,
  ) async {
    await _pump(tester, [_bill(mySettledAt: DateTime(2026, 10, 21))]);

    expect(find.text('Bạn đã thanh toán'), findsOneWidget);
    expect(find.text('Tôi đã thanh toán'), findsNothing);
  });

  testWidgets('bill đã có người trả thì không có nút Rời bill', (tester) async {
    await _pump(tester, [_bill(someoneSettled: true)]);

    expect(find.text('Rời bill'), findsNothing);
    expect(find.text('Tôi đã thanh toán'), findsOneWidget);
  });

  testWidgets('phần của mình 0đ thì chờ người trả, không cho thanh toán', (
    tester,
  ) async {
    await _pump(tester, [_bill(myAmountMinor: 0)]);

    expect(find.text('Chờ người trả chia lại phần tiền'), findsOneWidget);
    expect(find.text('Tôi đã thanh toán'), findsNothing);
    expect(find.text('Rời bill'), findsOneWidget);
  });

  testWidgets('bấm Tôi đã thanh toán gọi settle rồi tải lại', (tester) async {
    final service = await _pump(tester, [_bill()]);

    await tester.tap(find.text('Tôi đã thanh toán'));
    await tester.pumpAndSettle();

    expect(service.calls, ['list', 'settle bill-1', 'list']);
  });

  testWidgets('settle lỗi thì báo lỗi và vẫn tải lại', (tester) async {
    final service = await _pump(tester, [_bill()], failSettle: true);

    await tester.tap(find.text('Tôi đã thanh toán'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(service.calls, ['list', 'settle bill-1', 'list']);
  });

  testWidgets('bấm vào bill hiện danh sách người tham gia', (tester) async {
    await _pump(tester, [_bill()]);

    await tester.tap(find.text('Ăn tối'));
    await tester.pumpAndSettle();

    expect(find.text('Dũng (Bạn)'), findsOneWidget);
    expect(find.text('Lan'), findsOneWidget);
  });
}

class _FakeExpenseGroupService implements ExpenseGroupService {
  _FakeExpenseGroupService(this.bills, {this.failSettle = false});

  final bool failSettle;

  final List<ExternalBill> bills;
  final calls = <String>[];

  @override
  Future<List<ExternalBill>> listExternalBills() async {
    calls.add('list');
    return bills;
  }

  @override
  Future<void> settleMyShare(String expenseId) async {
    calls.add('settle $expenseId');
    if (failSettle) throw Exception('boom');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
