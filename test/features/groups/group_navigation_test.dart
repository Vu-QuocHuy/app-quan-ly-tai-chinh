import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/groups/data/group_service.dart';
import 'package:hoadon_insight/features/groups/domain/group_models.dart';
import 'package:hoadon_insight/features/groups/presentation/group_screen.dart';

void main() {
  testWidgets('mở chi tiết nhóm riêng và nút quay lại trở về danh sách', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const group = ExpenseGroup(
      id: 'group-1',
      name: 'Chuyến đi Đà Lạt',
      inviteCode: 'DALAT123',
      ownerId: 'user-1',
    );
    final groupDetails = GroupDetails(
      group: group,
      members: const [
        GroupMember(userId: 'user-1', displayName: 'Huy', role: 'owner'),
      ],
      expenses: const [],
      auditEvents: const [],
    );
    final service = _FakeExpenseGroupService(
      groups: const [group],
      details: groupDetails,
    );
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
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nhóm của tôi'), findsOneWidget);
    expect(find.text('Chuyến đi Đà Lạt'), findsOneWidget);
    expect(find.text('Mã mời: DALAT123'), findsNothing);

    await tester.tap(find.text('Chuyến đi Đà Lạt'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.text('Mã mời: DALAT123'), findsOneWidget);
    expect(find.text('Nhóm của tôi'), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Nhóm của tôi'), findsOneWidget);
    expect(find.text('Chuyến đi Đà Lạt'), findsOneWidget);

    await tester.tap(find.text('Chuyến đi Đà Lạt'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Nhóm của tôi'), findsOneWidget);
    expect(find.text('Chuyến đi Đà Lạt'), findsOneWidget);
  });
}

class _FakeExpenseGroupService implements ExpenseGroupService {
  _FakeExpenseGroupService({required this.groups, required this.details});

  final List<ExpenseGroup> groups;
  final GroupDetails details;

  @override
  String get currentUserId => 'user-1';

  @override
  Future<List<ExpenseGroup>> listGroups() async => groups;

  @override
  Future<GroupDetails> loadDetails(ExpenseGroup group) async => details;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
