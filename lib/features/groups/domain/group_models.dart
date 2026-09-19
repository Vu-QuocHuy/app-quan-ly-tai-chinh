class ExpenseGroup {
  const ExpenseGroup({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.ownerId,
  });

  final String id;
  final String name;
  final String inviteCode;
  final String ownerId;
}

class GroupMember {
  const GroupMember({
    required this.userId,
    required this.displayName,
    required this.role,
  });

  final String userId;
  final String displayName;
  final String role;
}

class GroupExpenseSplit {
  const GroupExpenseSplit({
    required this.userId,
    required this.amountMinor,
    this.settledAt,
  });

  final String? userId;
  final int amountMinor;
  final DateTime? settledAt;

  bool get isSettled => settledAt != null;
}

class GroupExpense {
  const GroupExpense({
    required this.id,
    required this.groupId,
    this.payerId,
    required this.description,
    required this.totalMinor,
    required this.createdAt,
    required this.splits,
  });

  final String id;
  final String groupId;
  final String? payerId;
  final String description;
  final int totalMinor;
  final DateTime createdAt;
  final List<GroupExpenseSplit> splits;
}

class GroupAuditEvent {
  const GroupAuditEvent({
    required this.id,
    required this.eventType,
    required this.createdAt,
    this.actorId,
    this.targetUserId,
    this.expenseId,
  });

  final String id;
  final String eventType;
  final DateTime createdAt;
  final String? actorId;
  final String? targetUserId;
  final String? expenseId;
}

class GroupDetails {
  const GroupDetails({
    required this.group,
    required this.members,
    required this.expenses,
    required this.auditEvents,
  });

  final ExpenseGroup group;
  final List<GroupMember> members;
  final List<GroupExpense> expenses;
  final List<GroupAuditEvent> auditEvents;
}
