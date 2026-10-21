import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/groups/data/group_service.dart';
import 'package:hoadon_insight/features/groups/domain/group_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _expenseId = '6f1c2b8e-4a1d-4c3e-9b2a-1d2e3f4a5b6c';
const _groupId = '1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b';

/// Service gọi Supabase giả: [respond] nhận tên RPC/bảng và body đã gửi.
({ExpenseGroupService service, List<String> calls}) _service(
  Object? Function(String path, Map<String, dynamic>? body) respond,
) {
  final calls = <String>[];
  final client = SupabaseClient(
    'https://example.supabase.co',
    'sb_publishable_test',
    httpClient: MockClient((request) async {
      final path = request.url.path.replaceFirst('/rest/v1/', '');
      final body = request.body.isEmpty
          ? null
          : jsonDecode(request.body) as Map<String, dynamic>?;
      calls.add(body == null ? path : '$path ${jsonEncode(body)}');
      return http.Response(
        jsonEncode(respond(path, body)),
        200,
        request: request,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  return (service: ExpenseGroupService(client), calls: calls);
}

void main() {
  test('joinBill chuẩn hóa mã và trả expense_id', () async {
    final fake = _service((path, body) => _expenseId);

    expect(await fake.service.joinBill('  abcdef1234 '), _expenseId);
    expect(fake.calls, ['rpc/join_group_bill {"p_code":"ABCDEF1234"}']);
  });

  test('joinBill: RPC trả null thì báo mã mời không hợp lệ', () async {
    final fake = _service((path, body) => null);

    await expectLater(
      fake.service.joinBill('ABCDEF1234'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Mã mời không hợp lệ.',
        ),
      ),
    );
  });

  test('joinBill từ chối mã sai độ dài mà không gọi server', () async {
    final fake = _service((path, body) => _expenseId);

    await expectLater(fake.service.joinBill('ABCD1234'), throwsFormatException);
    expect(fake.calls, isEmpty);
  });

  test(
    'openBillInvite trả mã 10 ký tự, closeBillInvite gọi đúng RPC',
    () async {
      final fake = _service(
        (path, body) =>
            path == 'rpc/open_group_bill_invite' ? 'ABCDEF1234' : null,
      );

      expect(await fake.service.openBillInvite(_expenseId), 'ABCDEF1234');
      await fake.service.closeBillInvite(_expenseId);
      await fake.service.leaveBill(_expenseId);
      expect(fake.calls, [
        'rpc/open_group_bill_invite {"p_expense_id":"$_expenseId"}',
        'rpc/close_group_bill_invite {"p_expense_id":"$_expenseId"}',
        'rpc/leave_group_bill {"p_expense_id":"$_expenseId"}',
      ]);
    },
  );

  test('listExternalBills đọc mảng JSON của RPC', () async {
    final fake = _service(
      (path, body) => [
        {
          'id': _expenseId,
          'description': 'Ăn tối',
          'total_minor': 600000,
          'created_at': '2026-10-21T12:00:00+00:00',
          'payer_name': 'Huy',
          'is_open': true,
          'my_amount_minor': 200000,
          'my_settled_at': null,
          'participants': [
            {
              'name': 'Dũng',
              'amount_minor': 200000,
              'settled': false,
              'is_me': true,
            },
          ],
        },
      ],
    );

    final bills = await fake.service.listExternalBills();
    expect(bills.single.description, 'Ăn tối');
    expect(bills.single.participants.single.isMe, isTrue);
  });

  test('updateCustomExpense gửi p_split_mode', () async {
    final fake = _service((path, body) => null);

    await fake.service.updateCustomExpense(
      expenseId: _expenseId,
      description: 'Ăn tối',
      totalMinor: 100,
      splitAmounts: const {_groupId: 100},
      splitMode: 'equal',
    );
    expect(fake.calls.single, contains('"p_split_mode":"equal"'));
    await expectLater(
      fake.service.updateCustomExpense(
        expenseId: _expenseId,
        description: 'Ăn tối',
        totalMinor: 100,
        splitAmounts: const {_groupId: 100},
        splitMode: 'weird',
      ),
      throwsFormatException,
    );
  });

  test(
    'expenseGroupIdOf: thành viên thấy nhóm, người ngoài nhận null',
    () async {
      final member = _service(
        (path, body) => [
          {'group_id': _groupId},
        ],
      );
      final guest = _service((path, body) => <Object>[]);

      expect(await member.service.expenseGroupIdOf(_expenseId), _groupId);
      expect(await guest.service.expenseGroupIdOf(_expenseId), isNull);
    },
  );

  test('loadDetails đọc split_mode, lời mời và tên người ngoài', () async {
    const owner = 'a1a1a1a1-0000-4000-8000-000000000001';
    const guest = 'd4d4d4d4-0000-4000-8000-000000000004';
    final fake = _service(
      (path, body) => switch (path) {
        'expense_group_members' => [
          {
            'user_id': owner,
            'display_name': 'Huy',
            'phone': null,
            'role': 'owner',
          },
        ],
        'group_expenses' => [
          {
            'id': _expenseId,
            'group_id': _groupId,
            'payer_id': owner,
            'description': 'Ăn tối',
            'total_minor': 300,
            'created_at': '2026-10-21T12:00:00+00:00',
            'source_invoice_id': null,
            'source_snapshot': null,
            'split_mode': 'equal',
            'join_open': true,
            'join_code': 'ABCDEF1234',
          },
        ],
        'group_expense_splits' => [
          {
            'expense_id': _expenseId,
            'user_id': owner,
            'amount_minor': 150,
            'settled_at': null,
            'participant_name': null,
          },
          {
            'expense_id': _expenseId,
            'user_id': guest,
            'amount_minor': 150,
            'settled_at': null,
            'participant_name': 'Dũng',
          },
        ],
        _ => <Object>[],
      },
    );

    final details = await fake.service.loadDetails(
      const ExpenseGroup(
        id: _groupId,
        name: 'Đà Lạt',
        inviteCode: 'ABCD1234',
        ownerId: owner,
      ),
    );
    final expense = details.expenses.single;
    expect(expense.splitMode, 'equal');
    expect(expense.joinOpen, isTrue);
    expect(expense.joinCode, 'ABCDEF1234');
    expect(expense.splits.map((split) => split.participantName), [
      null,
      'Dũng',
    ]);
  });
}
