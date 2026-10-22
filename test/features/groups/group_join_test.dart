import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/groups/data/group_service.dart';
import 'package:hoadon_insight/features/groups/domain/external_bill.dart';
import 'package:hoadon_insight/features/groups/domain/group_models.dart';
import 'package:hoadon_insight/features/groups/presentation/group_screen.dart';

const _group = ExpenseGroup(
  id: 'group-1',
  name: 'Đà Lạt',
  inviteCode: 'DALAT123',
  ownerId: 'user-1',
);

final _externalBill = ExternalBill(
  id: 'bill-9',
  description: 'Karaoke',
  totalMinor: 300000,
  createdAt: DateTime(2026, 10, 21),
  payerName: 'Minh',
  isOpen: true,
  myAmountMinor: 100000,
  mySettledAt: null,
  participants: const [
    ExternalBillParticipant(
      name: 'Minh',
      amountMinor: 200000,
      settled: false,
      isMe: false,
    ),
    ExternalBillParticipant(
      name: 'Huy',
      amountMinor: 100000,
      settled: false,
      isMe: true,
    ),
  ],
);

Future<_FakeExpenseGroupService> _pump(
  WidgetTester tester, {
  String? billGroupId,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1600);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final service = _FakeExpenseGroupService(billGroupId: billGroupId);
  final rootKey = GlobalKey<NavigatorState>();
  final router = GoRouter(
    navigatorKey: rootKey,
    initialLocation: '/groups',
    routes: [
      GoRoute(
        path: '/groups',
        builder: (context, state) => const GroupScreen(),
        routes: [
          GoRoute(
            path: ':groupId',
            parentNavigatorKey: rootKey,
            builder: (context, state) =>
                GroupDetailScreen(groupId: state.pathParameters['groupId']!),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [expenseGroupServiceProvider.overrideWithValue(service)],
      child: MaterialApp.router(
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

Future<void> _typeCode(WidgetTester tester, String code) async {
  await tester.tap(find.widgetWithText(OutlinedButton, 'Tham gia'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Nhập mã mời'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, 'Mã mời'), code);
  await tester.tap(find.widgetWithText(FilledButton, 'Tham gia'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mã 10 ký tự chữ thường vào bill, người ngoài thấy mục bill', (
    tester,
  ) async {
    final service = await _pump(tester);
    expect(find.text('Bill bạn tham gia'), findsNothing);

    await _typeCode(tester, ' abcdef1234 ');

    expect(service.calls, ['joinBill ABCDEF1234', 'groupOf bill-9']);
    expect(find.text('Đã vào bill'), findsOneWidget);
    expect(find.text('Bill bạn tham gia'), findsOneWidget);
    expect(find.text('Karaoke'), findsOneWidget);
  });

  testWidgets('thành viên nhóm vào bill của nhóm mình thì mở màn nhóm', (
    tester,
  ) async {
    final service = await _pump(tester, billGroupId: 'group-1');

    await _typeCode(tester, 'ABCDEF1234');

    expect(service.calls, ['joinBill ABCDEF1234', 'groupOf bill-9']);
    expect(find.byTooltip('Mời thành viên bằng QR'), findsOneWidget);
  });

  testWidgets('mã 8 ký tự vẫn vào nhóm', (tester) async {
    final service = await _pump(tester);

    await _typeCode(tester, 'abcd1234');

    expect(service.calls, ['joinGroup ABCD1234']);
    expect(find.byTooltip('Mời thành viên bằng QR'), findsOneWidget);
  });

  testWidgets('mã 9 hoặc 11 ký tự báo lỗi tại chỗ, không gọi server', (
    tester,
  ) async {
    final service = await _pump(tester);

    for (final code in ['ABCDEF123', 'ABCDEF12345']) {
      await _typeCode(tester, code);
      expect(
        find.text(
          'Mã mời phải có 8 ký tự (nhóm) hoặc 10 ký tự (bill), gồm 0-9 và A-F.',
        ),
        findsOneWidget,
      );
      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold).first),
      ).removeCurrentSnackBar();
      await tester.pumpAndSettle();
    }
    expect(service.calls, isEmpty);
  });
}

class _FakeExpenseGroupService implements ExpenseGroupService {
  _FakeExpenseGroupService({this.billGroupId});

  final String? billGroupId;
  final calls = <String>[];
  bool _joinedBill = false;

  @override
  String get currentUserId => 'user-1';

  @override
  Future<List<ExpenseGroup>> listGroups() async => const [_group];

  @override
  Future<GroupDetails> loadDetails(ExpenseGroup group) async => GroupDetails(
    group: group,
    members: const [
      GroupMember(userId: 'user-1', displayName: 'Huy', role: 'owner'),
    ],
    expenses: const [],
    auditEvents: const [],
  );

  @override
  Future<ExpenseGroup> joinGroup(String inviteCode) async {
    calls.add('joinGroup $inviteCode');
    return _group;
  }

  @override
  Future<String> joinBill(String code) async {
    calls.add('joinBill $code');
    _joinedBill = true;
    return 'bill-9';
  }

  @override
  Future<String?> expenseGroupIdOf(String expenseId) async {
    calls.add('groupOf $expenseId');
    return billGroupId;
  }

  @override
  Future<List<ExternalBill>> listExternalBills() async =>
      _joinedBill && billGroupId == null ? [_externalBill] : const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
