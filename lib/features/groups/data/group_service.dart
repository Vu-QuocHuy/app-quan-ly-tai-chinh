import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/group_models.dart';

class ExpenseGroupService {
  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  static const _maxSafeInteger = 9007199254740991;

  const ExpenseGroupService(this._client);

  final SupabaseClient _client;

  String get currentUserId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Bạn cần đăng nhập để dùng nhóm.');
    return id;
  }

  Future<List<ExpenseGroup>> listGroups() async {
    final rows = _asRows(
      await _client
          .from('expense_groups')
          .select('id, name, invite_code, owner_id')
          .order('created_at', ascending: false),
    );
    return rows.map(_groupFromMap).toList(growable: false);
  }

  Future<ExpenseGroup> createGroup(String name) async {
    final validName = _requiredString(name, 'Tên nhóm', 80, minLength: 2);
    final rows = await _client.rpc(
      'create_expense_group',
      params: {'p_name': validName},
    );
    final list = _asRows(rows);
    if (list.isEmpty) throw StateError('Không tạo được nhóm.');
    return _groupFromMap(list.first);
  }

  Future<ExpenseGroup> joinGroup(String inviteCode) async {
    final validCode = _requiredString(inviteCode, 'Mã mời', 32);
    final rows = await _client.rpc(
      'join_expense_group',
      params: {'p_invite_code': validCode},
    );
    final list = _asRows(rows);
    if (list.isEmpty) throw StateError('Không tham gia được nhóm.');
    return _groupFromMap(list.first);
  }

  Future<GroupDetails> loadDetails(ExpenseGroup group) async {
    _requiredUuid(group.id, 'group.id');
    final memberRows = _asRows(
      await _client
          .from('expense_group_members')
          .select('user_id, display_name, role')
          .eq('group_id', group.id)
          .order('joined_at'),
    );
    final expenseRows = _asRows(
      await _client
          .from('group_expenses')
          .select(
            'id, group_id, payer_id, description, total_minor, created_at',
          )
          .eq('group_id', group.id)
          .order('created_at', ascending: false),
    );
    final expenseIds = expenseRows
        .map((row) => _requiredUuid(row['id'], 'group_expense.id'))
        .toList(growable: false);
    final splitRows = expenseIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : _asRows(
            await _client
                .from('group_expense_splits')
                .select('expense_id, user_id, amount_minor, settled_at')
                .inFilter('expense_id', expenseIds),
          );
    List<Map<String, dynamic>> auditRows;
    try {
      auditRows = _asRows(
        await _client
            .from('group_audit_events')
            .select(
              'id, event_type, actor_id, target_user_id, expense_id, created_at',
            )
            .eq('group_id', group.id)
            .order('created_at', ascending: false)
            .limit(50),
      );
    } on PostgrestException catch (error) {
      if (error.code == '42P01' || error.code == 'PGRST205') {
        auditRows = const [];
      } else {
        rethrow;
      }
    }
    var ownerId = group.ownerId;
    String? foundOwnerId;
    final memberIds = <String>{};
    for (final row in memberRows) {
      final userId = _requiredUuid(row['user_id'], 'group_member.userId');
      if (!memberIds.add(userId)) {
        throw const FormatException('Dữ liệu thành viên nhóm bị trùng.');
      }
      final role = _requiredString(row['role'], 'group_member.role', 16);
      if (role != 'owner' && role != 'member') {
        throw const FormatException('Vai trò thành viên nhóm không hợp lệ.');
      }
      if (role == 'owner') {
        if (foundOwnerId != null) {
          throw const FormatException('Dữ liệu nhóm có nhiều chủ nhóm.');
        }
        foundOwnerId = userId;
        ownerId = userId;
      }
    }
    if (foundOwnerId == null) {
      throw const FormatException('Dữ liệu nhóm thiếu chủ nhóm.');
    }
    final resolvedGroup = ownerId == group.ownerId
        ? group
        : ExpenseGroup(
            id: group.id,
            name: group.name,
            inviteCode: group.inviteCode,
            ownerId: ownerId,
          );
    final splitsByExpense = <String, List<GroupExpenseSplit>>{};
    final splitKeys = <String>{};
    var orphanIndex = 0;
    for (final row in splitRows) {
      final map = _map(row);
      final expenseId = _requiredUuid(
        map['expense_id'],
        'group_expense_split.expenseId',
      );
      if (!expenseIds.contains(expenseId)) {
        throw const FormatException('Dữ liệu phần chia không thuộc nhóm.');
      }
      final userId = _optionalUuid(
        map['user_id'],
        'group_expense_split.userId',
      );
      final key = userId == null
          ? '$expenseId|orphan|${orphanIndex++}'
          : '$expenseId|$userId';
      if (!splitKeys.add(key)) {
        throw const FormatException('Dữ liệu phần chia bị trùng.');
      }
      splitsByExpense
          .putIfAbsent(expenseId, () => [])
          .add(
            GroupExpenseSplit(
              userId: userId,
              amountMinor: _nonNegativeInteger(
                map['amount_minor'],
                'group_expense_split.amountMinor',
              ),
              settledAt: _optionalDate(
                map['settled_at'],
                'group_expense_split.settledAt',
              ),
            ),
          );
    }
    return GroupDetails(
      group: resolvedGroup,
      members: [
        for (final row in memberRows)
          GroupMember(
            userId: _requiredUuid(row['user_id'], 'group_member.userId'),
            displayName: _requiredString(
              row['display_name'],
              'group_member.displayName',
              120,
            ),
            role: _requiredString(row['role'], 'group_member.role', 16),
          ),
      ],
      expenses: [
        for (final row in expenseRows)
          _expenseFromMap(row, group.id, splitsByExpense),
      ],
      auditEvents: auditRows.map(_auditEventFromMap).toList(growable: false),
    );
  }

  Future<void> addEqualExpense({
    required String groupId,
    required String description,
    required int totalMinor,
    required List<String> memberIds,
  }) async {
    _validateExpenseInput(
      groupId: groupId,
      description: description,
      totalMinor: totalMinor,
    );
    _validateMemberIds(memberIds);
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
    _validateExpenseInput(
      groupId: groupId,
      description: description,
      totalMinor: totalMinor,
    );
    if (splitAmounts.isEmpty || splitAmounts.length > 100) {
      throw const FormatException('Danh sách phần chia không hợp lệ.');
    }
    _validateMemberIds(splitAmounts.keys);
    final splitTotal = splitAmounts.values.fold<int>(0, (sum, value) {
      if (value < 0 ||
          value > _maxSafeInteger ||
          sum > _maxSafeInteger - value) {
        throw const FormatException('Số tiền phần chia không hợp lệ.');
      }
      return sum + value;
    });
    if (splitTotal != totalMinor) {
      throw const FormatException('Tổng phần chia phải bằng tổng khoản chi.');
    }
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
    _requiredUuid(expenseId, 'expenseId');
    await _client.rpc(
      'settle_group_split',
      params: {'p_expense_id': expenseId},
    );
  }

  Future<void> setMemberRole({
    required String groupId,
    required String userId,
    required String role,
  }) async {
    _requiredUuid(groupId, 'groupId');
    _requiredUuid(userId, 'userId');
    if (role != 'owner' && role != 'member') {
      throw const FormatException('Vai trò thành viên nhóm không hợp lệ.');
    }
    await _client.rpc(
      'set_expense_group_member_role',
      params: {'p_group_id': groupId, 'p_user_id': userId, 'p_role': role},
    );
  }

  Future<void> removeMember({
    required String groupId,
    required String userId,
  }) async {
    _requiredUuid(groupId, 'groupId');
    _requiredUuid(userId, 'userId');
    await _client.rpc(
      'remove_expense_group_member',
      params: {'p_group_id': groupId, 'p_user_id': userId},
    );
  }

  Future<void> leaveGroup(String groupId) async {
    _requiredUuid(groupId, 'groupId');
    await _client.rpc('leave_expense_group', params: {'p_group_id': groupId});
  }

  ExpenseGroup _groupFromMap(dynamic value) {
    final map = _map(value);
    final name = _requiredString(map['name'], 'group.name', 80, minLength: 2);
    final inviteCode = _requiredString(
      map['invite_code'] ?? map['inviteCode'],
      'group.inviteCode',
      32,
    );
    return ExpenseGroup(
      id: _requiredUuid(map['id'], 'group.id'),
      name: name,
      inviteCode: inviteCode,
      ownerId: _requiredUuid(
        map['owner_id'] ?? map['ownerId'],
        'group.ownerId',
      ),
    );
  }

  List<Map<String, dynamic>> _asRows(dynamic value) {
    if (value is! List) {
      throw const FormatException('Backend trả danh sách nhóm không hợp lệ.');
    }
    return value.map(_map).toList(growable: false);
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const FormatException('Backend trả dữ liệu nhóm không hợp lệ.');
    }
    return Map<String, dynamic>.from(value);
  }

  GroupExpense _expenseFromMap(
    Map<String, dynamic> map,
    String groupId,
    Map<String, List<GroupExpenseSplit>> splitsByExpense,
  ) {
    final expenseId = _requiredUuid(map['id'], 'group_expense.id');
    final rowGroupId = _requiredUuid(map['group_id'], 'group_expense.groupId');
    if (rowGroupId != groupId) {
      throw const FormatException('Khoản chi không thuộc nhóm hiện tại.');
    }
    final totalMinor = _positiveInteger(
      map['total_minor'],
      'group_expense.totalMinor',
    );
    final splits = splitsByExpense[expenseId] ?? const <GroupExpenseSplit>[];
    final splitTotal = splits.fold<int>(
      0,
      (sum, split) => sum <= _maxSafeInteger - split.amountMinor
          ? sum + split.amountMinor
          : _maxSafeInteger + 1,
    );
    if (splitTotal != totalMinor) {
      throw const FormatException('Tổng phần chia không khớp khoản chi.');
    }
    return GroupExpense(
      id: expenseId,
      groupId: rowGroupId,
      payerId: _optionalUuid(map['payer_id'], 'group_expense.payerId'),
      description: _requiredString(
        map['description'],
        'group_expense.description',
        160,
        minLength: 2,
      ),
      totalMinor: totalMinor,
      createdAt: _requiredDate(map['created_at'], 'group_expense.createdAt'),
      splits: List.unmodifiable(splits),
    );
  }

  GroupAuditEvent _auditEventFromMap(Map<String, dynamic> map) {
    return GroupAuditEvent(
      id: _requiredInteger(map['id'], 'group_audit.id').toString(),
      eventType: _requiredString(
        map['event_type'],
        'group_audit.eventType',
        64,
      ),
      actorId: _optionalUuid(map['actor_id'], 'group_audit.actorId'),
      targetUserId: _optionalUuid(
        map['target_user_id'],
        'group_audit.targetUserId',
      ),
      expenseId: _optionalUuid(map['expense_id'], 'group_audit.expenseId'),
      createdAt: _requiredDate(map['created_at'], 'group_audit.createdAt'),
    );
  }

  String _requiredString(
    Object? value,
    String field,
    int maxLength, {
    int minLength = 1,
  }) {
    if (value is! String ||
        value.length < minLength ||
        value.length > maxLength ||
        value.trim().isEmpty) {
      throw FormatException('$field không hợp lệ.');
    }
    return value;
  }

  String _requiredUuid(Object? value, String field) {
    if (value is! String || !_uuidPattern.hasMatch(value)) {
      throw FormatException('$field không hợp lệ.');
    }
    return value;
  }

  String? _optionalUuid(Object? value, String field) {
    if (value == null) return null;
    return _requiredUuid(value, field);
  }

  DateTime _requiredDate(Object? value, String field) {
    if (value is! String) throw FormatException('$field không hợp lệ.');
    final result = DateTime.tryParse(value);
    if (result == null) throw FormatException('$field không hợp lệ.');
    return result.toLocal();
  }

  DateTime? _optionalDate(Object? value, String field) {
    if (value == null) return null;
    return _requiredDate(value, field);
  }

  int _requiredInteger(Object? value, String field) {
    if (value is! num ||
        !value.toDouble().isFinite ||
        value != value.truncate() ||
        value < 0 ||
        value > _maxSafeInteger) {
      throw FormatException('$field không hợp lệ.');
    }
    return value.toInt();
  }

  int _nonNegativeInteger(Object? value, String field) {
    return _requiredInteger(value, field);
  }

  int _positiveInteger(Object? value, String field) {
    final result = _requiredInteger(value, field);
    if (result < 1) throw FormatException('$field không hợp lệ.');
    return result;
  }

  void _validateExpenseInput({
    required String groupId,
    required String description,
    required int totalMinor,
  }) {
    _requiredUuid(groupId, 'groupId');
    _requiredString(description, 'description', 160, minLength: 2);
    if (totalMinor < 1 || totalMinor > _maxSafeInteger) {
      throw const FormatException('Tổng tiền khoản chi không hợp lệ.');
    }
  }

  void _validateMemberIds(Iterable<String> memberIds) {
    final ids = memberIds.toList(growable: false);
    if (ids.isEmpty || ids.length > 100 || ids.toSet().length != ids.length) {
      throw const FormatException('Danh sách thành viên không hợp lệ.');
    }
    for (final id in ids) {
      _requiredUuid(id, 'memberId');
    }
  }
}
