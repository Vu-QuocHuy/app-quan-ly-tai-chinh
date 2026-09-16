import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/group_models.dart';

class ExpenseGroupService {
  const ExpenseGroupService(this._client);

  final SupabaseClient _client;

  String get currentUserId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Bạn cần đăng nhập để dùng nhóm.');
    return id;
  }

  Future<List<ExpenseGroup>> listGroups() async {
    final rows = await _client
        .from('expense_groups')
        .select('id, name, invite_code, owner_id')
        .order('created_at', ascending: false);
    return rows.map(_groupFromMap).toList(growable: false);
  }

  Future<ExpenseGroup> createGroup(String name) async {
    final rows = await _client.rpc(
      'create_expense_group',
      params: {'p_name': name},
    );
    final list = _asRows(rows);
    if (list.isEmpty) throw StateError('Không tạo được nhóm.');
    return _groupFromMap(list.first);
  }

  Future<ExpenseGroup> joinGroup(String inviteCode) async {
    final rows = await _client.rpc(
      'join_expense_group',
      params: {'p_invite_code': inviteCode},
    );
    final list = _asRows(rows);
    if (list.isEmpty) throw StateError('Không tham gia được nhóm.');
    return _groupFromMap(list.first);
  }

  Future<GroupDetails> loadDetails(ExpenseGroup group) async {
    final memberRows = await _client
        .from('expense_group_members')
        .select('user_id, display_name, role')
        .eq('group_id', group.id)
        .order('joined_at');
    final expenseRows = await _client
        .from('group_expenses')
        .select('id, group_id, payer_id, description, total_minor, created_at')
        .eq('group_id', group.id)
        .order('created_at', ascending: false);
    final expenseIds = expenseRows.map((row) => '${row['id']}').toList();
    final splitRows = expenseIds.isEmpty
        ? const <dynamic>[]
        : await _client
              .from('group_expense_splits')
              .select('expense_id, user_id, amount_minor, settled_at')
              .inFilter('expense_id', expenseIds);
    final splitsByExpense = <String, List<GroupExpenseSplit>>{};
    for (final row in splitRows) {
      final map = _map(row);
      splitsByExpense
          .putIfAbsent('${map['expense_id']}', () => [])
          .add(
            GroupExpenseSplit(
              userId: '${map['user_id']}',
              amountMinor: _int(map['amount_minor']),
              settledAt: _date(map['settled_at']),
            ),
          );
    }
    return GroupDetails(
      group: group,
      members: memberRows
          .map(
            (row) => GroupMember(
              userId: '${row['user_id']}',
              displayName: '${row['display_name']}',
              role: '${row['role']}',
            ),
          )
          .toList(growable: false),
      expenses: expenseRows
          .map(
            (row) => GroupExpense(
              id: '${row['id']}',
              groupId: '${row['group_id']}',
              payerId: '${row['payer_id']}',
              description: '${row['description']}',
              totalMinor: _int(row['total_minor']),
              createdAt: _date(row['created_at']) ?? DateTime.now(),
              splits: List.unmodifiable(
                splitsByExpense['${row['id']}'] ?? const [],
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Future<void> addEqualExpense({
    required String groupId,
    required String description,
    required int totalMinor,
    required List<String> memberIds,
  }) async {
    await _client.rpc(
      'create_group_expense',
      params: {
        'p_group_id': groupId,
        'p_description': description,
        'p_total_minor': totalMinor,
        'p_split_user_ids': memberIds,
      },
    );
  }

  Future<void> addCustomExpense({
    required String groupId,
    required String description,
    required int totalMinor,
    required Map<String, int> splitAmounts,
  }) async {
    await _client.rpc(
      'create_group_expense_custom',
      params: {
        'p_group_id': groupId,
        'p_description': description,
        'p_total_minor': totalMinor,
        'p_splits': splitAmounts.entries
            .map((entry) => {'user_id': entry.key, 'amount_minor': entry.value})
            .toList(growable: false),
      },
    );
  }

  Future<void> settleMyShare(String expenseId) async {
    await _client.rpc(
      'settle_group_split',
      params: {'p_expense_id': expenseId},
    );
  }

  ExpenseGroup _groupFromMap(dynamic value) {
    final map = _map(value);
    return ExpenseGroup(
      id: '${map['id']}',
      name: '${map['name']}',
      inviteCode: '${map['invite_code'] ?? map['inviteCode']}',
      ownerId: '${map['owner_id'] ?? map['ownerId']}',
    );
  }

  List<Map<String, dynamic>> _asRows(dynamic value) {
    if (value is! List) return const [];
    return value.map(_map).toList(growable: false);
  }

  Map<String, dynamic> _map(dynamic value) =>
      Map<String, dynamic>.from(value as Map);

  int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  DateTime? _date(dynamic value) =>
      value == null ? null : DateTime.tryParse('$value')?.toLocal();
}
