import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/chat/domain/chat_models.dart';
import 'package:hoadon_insight/features/chat/domain/local_debt_answer.dart';
import 'package:hoadon_insight/features/debts/domain/debt_models.dart';

void main() {
  final created = DateTime(2026, 11, 1);
  final debts = [
    DebtRecord(
      id: '1',
      personName: 'Nam',
      phoneNumber: '0901234567',
      type: DebtType.iOwe,
      amountMinor: 500000,
      paidAmountMinor: 100000,
      createdAt: created,
    ),
    DebtRecord(
      id: '2',
      personName: 'Lan',
      type: DebtType.theyOwe,
      amountMinor: 300000,
      createdAt: created,
    ),
    DebtRecord(
      id: '3',
      personName: 'Hùng',
      type: DebtType.iOwe,
      amountMinor: 200000,
      paidAmountMinor: 200000,
      createdAt: created,
    ),
  ];

  test('"đang nợ ai" lists only open payables, never phone numbers', () {
    final reply = localDebtAnswer('Tôi đang nợ ai?', debts);
    expect(reply.text, contains('Bạn nợ Nam'));
    expect(reply.text, contains('400.000'));
    expect(reply.text, isNot(contains('Lan')));
    expect(reply.text, isNot(contains('Hùng')));
    expect(reply.text, isNot(contains('0901234567')));
    expect(reply.citations, isNotEmpty);
    expect(
      reply.facts,
      contains(
        isA<ChatFact>()
            .having((f) => f.key, 'key', 'debt_payable_minor_vnd')
            .having((f) => f.value, 'value', '400000'),
      ),
    );
  });

  test('"ai nợ tôi" lists only receivables', () {
    final reply = localDebtAnswer('Ai nợ tôi?', debts);
    expect(reply.text, contains('Lan nợ bạn'));
    expect(reply.text, isNot(contains('Nam')));
  });

  test('general debt question summarises both directions', () {
    final reply = localDebtAnswer('Tổng nợ của tôi là bao nhiêu', debts);
    expect(reply.text, contains('Bạn nợ Nam'));
    expect(reply.text, contains('Lan nợ bạn'));
  });

  test('no open debts gives a friendly empty answer', () {
    final reply = localDebtAnswer('Tôi đang nợ ai?', [debts[2]]);
    expect(reply.text, contains('không còn nợ ai'));
  });
}
