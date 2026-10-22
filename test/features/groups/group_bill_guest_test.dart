import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/groups/data/group_service.dart';
import 'package:hoadon_insight/features/groups/domain/group_models.dart';
import 'package:hoadon_insight/features/groups/presentation/group_screen.dart';

const _group = ExpenseGroup(
  id: 'group-1',
  name: 'Đà Lạt',
  inviteCode: 'DALAT123',
  ownerId: 'user-1',
);

final _details = GroupDetails(
  group: _group,
  members: const [
    GroupMember(userId: 'user-1', displayName: 'Huy', role: 'owner'),
    GroupMember(userId: 'user-2', displayName: 'Lan', role: 'member'),
  ],
  expenses: [
    GroupExpense(
      id: 'expense-1',
      groupId: 'group-1',
      payerId: 'user-1',
      description: 'Ăn tối',
      totalMinor: 90000,
      createdAt: DateTime(2026, 10, 21),
      splitMode: 'equal',
      joinOpen: true,
      joinCode: 'ABCDEF1234',
      splits: const [
        GroupExpenseSplit(userId: 'user-1', amountMinor: 30000),
        GroupExpenseSplit(userId: 'user-2', amountMinor: 30000),
        GroupExpenseSplit(
          userId: 'guest-1',
          amountMinor: 30000,
          participantName: 'Dũng',
        ),
      ],
    ),
  ],
  auditEvents: [
    GroupAuditEvent(
      id: '1',
      eventType: 'bill_joined',
      createdAt: DateTime(2026, 10, 21, 20),
      actorId: 'guest-1',
      targetUserId: 'guest-1',
      expenseId: 'expense-1',
    ),
    GroupAuditEvent(
      id: '2',
      eventType: 'bill_left',
      createdAt: DateTime(2026, 10, 21, 21),
      actorId: 'guest-2',
      targetUserId: 'guest-2',
      expenseId: 'expense-1',
    ),
  ],
);

GroupDetails _withSplits(List<GroupExpenseSplit> splits) => GroupDetails(
  group: _group,
  members: _details.members,
  expenses: [
    GroupExpense(
      id: 'expense-1',
      groupId: 'group-1',
      payerId: 'user-1',
      description: 'Ăn tối',
      totalMinor: 30000,
      createdAt: DateTime(2026, 10, 21),
      splitMode: 'custom',
      splits: splits,
    ),
  ],
  auditEvents: const [],
);

Future<_FakeExpenseGroupService> _pump(
  WidgetTester tester, {
  GroupDetails? details,
  String userId = 'user-1',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 2400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final service = _FakeExpenseGroupService(details ?? _details, userId);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [expenseGroupServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(
        locale: Locale('vi'),
        supportedLocales: [Locale('vi'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: GroupDetailScreen(groupId: 'group-1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

void main() {
  testWidgets(
    'người ngoài trong bill hiện tên kèm nhãn Khách và trong nhật ký',
    (tester) async {
      await _pump(tester);

      expect(find.text('Dũng'), findsOneWidget);
      expect(find.text('Khách'), findsOneWidget);
      await tester.tap(find.textContaining('Lịch sử hoạt động'));
      await tester.pumpAndSettle();
      expect(find.text('Dũng đã vào bill “Ăn tối”'), findsOneWidget);
      expect(find.text('Khách đã rời bill “Ăn tối”'), findsOneWidget);
      expect(find.textContaining('Tài khoản đã xóa'), findsNothing);
    },
  );

  testWidgets('phần 0đ không có nút Tôi đã thanh toán, phần > 0 thì có', (
    tester,
  ) async {
    await _pump(
      tester,
      userId: 'user-2',
      details: _withSplits(const [
        GroupExpenseSplit(userId: 'user-1', amountMinor: 30000),
        GroupExpenseSplit(userId: 'user-2', amountMinor: 0),
      ]),
    );
    expect(find.text('Tôi đã thanh toán'), findsNothing);

    await _pump(
      tester,
      userId: 'user-2',
      details: _withSplits(const [
        GroupExpenseSplit(userId: 'user-1', amountMinor: 20000),
        GroupExpenseSplit(userId: 'user-2', amountMinor: 10000),
      ]),
    );
    expect(find.text('Tôi đã thanh toán'), findsOneWidget);
  });

  testWidgets(
    'khách đã thành viên nhóm hiện tên thành viên, không nhãn Khách',
    (tester) async {
      await _pump(
        tester,
        details: _withSplits(const [
          GroupExpenseSplit(userId: 'user-1', amountMinor: 15000),
          GroupExpenseSplit(
            userId: 'user-2',
            amountMinor: 15000,
            participantName: 'Tên khách cũ',
          ),
        ]),
      );
      expect(find.text('Lan'), findsWidgets);
      expect(find.text('Tên khách cũ'), findsNothing);
      expect(find.text('Khách'), findsNothing);
    },
  );

  testWidgets('người trả mở QR mời vào bill rồi đóng lời mời', (tester) async {
    final service = await _pump(tester);

    await tester.tap(find.byTooltip('Quản lý khoản chi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QR mời vào bill'));
    await tester.pumpAndSettle();
    expect(service.calls, ['open expense-1']);
    expect(find.text('ABCDEF1234'), findsOneWidget);

    await tester.tap(find.text('Đóng lời mời'));
    await tester.pumpAndSettle();
    expect(service.calls, ['open expense-1', 'close expense-1']);
  });

  testWidgets('sửa bill chia đều giữ khách và gửi splitMode equal', (
    tester,
  ) async {
    final service = await _pump(tester);

    await tester.tap(find.byTooltip('Quản lý khoản chi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sửa khoản chi'));
    await tester.pumpAndSettle();
    expect(find.text('Dũng (Khách)'), findsOneWidget);
    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();

    expect(service.calls, ['update expense-1 equal guest-1,user-1,user-2']);
  });
}

class _FakeExpenseGroupService implements ExpenseGroupService {
  _FakeExpenseGroupService(this.details, this.userId);

  final GroupDetails details;
  final String userId;
  final calls = <String>[];

  @override
  String get currentUserId => userId;

  @override
  Future<List<ExpenseGroup>> listGroups() async => const [_group];

  @override
  Future<GroupDetails> loadDetails(ExpenseGroup group) async => details;

  @override
  Future<String> openBillInvite(String expenseId) async {
    calls.add('open $expenseId');
    return 'ABCDEF1234';
  }

  @override
  Future<void> closeBillInvite(String expenseId) async {
    calls.add('close $expenseId');
  }

  @override
  Future<void> updateCustomExpense({
    required String expenseId,
    required String description,
    required int totalMinor,
    required Map<String, int> splitAmounts,
    required String splitMode,
  }) async {
    final ids = splitAmounts.keys.toList()..sort();
    calls.add('update $expenseId $splitMode ${ids.join(',')}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
