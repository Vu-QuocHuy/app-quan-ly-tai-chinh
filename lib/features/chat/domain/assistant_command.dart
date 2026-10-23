/// Wire contract: supabase/functions/_shared/assistant_command.schema.json.
/// No arbitrary tool names, record IDs, account IDs or executable payloads.
class AssistantCommand {
  const AssistantCommand({
    required this.kind,
    this.operation = 'create',
    this.amountMinor,
    this.date,
    this.description = '',
    this.categoryId,
    this.personName,
    this.debtDirection,
    this.groupName,
    this.frequency,
  });

  static const kinds = {
    'query',
    'identity',
    'reject',
    'cancel',
    'income',
    'expense',
    'debt',
    'recurring_income',
    'recurring_expense',
    'group',
    'fund_deposit',
    'fund_expense',
    'open_split',
  };
  static const keys = {
    'kind',
    'operation',
    'amountMinor',
    'date',
    'description',
    'categoryId',
    'personName',
    'debtDirection',
    'groupName',
    'frequency',
  };

  final String kind;
  final String operation;
  final int? amountMinor;
  final DateTime? date;
  final String description;
  final String? categoryId;
  final String? personName;
  final String? debtDirection;
  final String? groupName;
  final String? frequency;

  bool get isWrite =>
      !{'query', 'identity', 'reject', 'cancel', 'open_split'}.contains(kind);
  bool get isGroup =>
      {'group', 'fund_deposit', 'fund_expense', 'open_split'}.contains(kind);

  factory AssistantCommand.fromJson(Map<String, dynamic> json) {
    if (json.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(json.keys.toSet()).isNotEmpty) {
      throw const FormatException('Invalid command fields');
    }
    String? text(String key, int max) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String || value.length > max) {
        throw const FormatException('Invalid command string');
      }
      return value.trim().isEmpty ? null : value.trim();
    }

    final kind = text('kind', 32);
    final operation = text('operation', 16);
    final amount = json['amountMinor'];
    final direction = text('debtDirection', 16);
    final frequency = text('frequency', 16);
    final rawDate = text('date', 10);
    final date = rawDate == null ? null : DateTime.tryParse(rawDate);
    if (!kinds.contains(kind) ||
        !{'create', 'update_last'}.contains(operation) ||
        (amount != null &&
            (amount is! int || amount < 1 || amount > 9007199254740991)) ||
        (direction != null && !{'i_owe', 'they_owe'}.contains(direction)) ||
        (frequency != null &&
            !{'weekly', 'monthly', 'yearly'}.contains(frequency)) ||
        (rawDate != null && (date == null || dateKey(date) != rawDate)) ||
        json['description'] is! String) {
      throw const FormatException('Invalid command value');
    }
    return AssistantCommand(
      kind: kind!,
      operation: operation!,
      amountMinor: amount as int?,
      date: date,
      description: text('description', 160) ?? '',
      categoryId: text('categoryId', 128),
      personName: text('personName', 100),
      debtDirection: direction,
      groupName: text('groupName', 80),
      frequency: frequency,
    );
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    'operation': operation,
    'amountMinor': amountMinor,
    'date': date == null ? null : dateKey(date!),
    'description': description,
    'categoryId': categoryId,
    'personName': personName,
    'debtDirection': debtDirection,
    'groupName': groupName,
    'frequency': frequency,
  };

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String? clarification(bool en) {
    if (kind == 'debt') {
      if (debtDirection == null) {
        return en
            ? 'Do you owe them, or do they owe you?'
            : 'Bạn nợ người đó hay người đó nợ bạn?';
      }
      if (personName == null) {
        return en ? 'Who is the debt with?' : 'Khoản nợ này với ai?';
      }
    }
    if (isGroup && (groupName == null || groupName!.length < 2)) {
      return en ? 'What is the group name?' : 'Tên nhóm là gì?';
    }
    if (isWrite && kind != 'group' && amountMinor == null) {
      return en ? 'What is the amount in VND?' : 'Số tiền là bao nhiêu đồng?';
    }
    if (kind.startsWith('recurring_')) {
      if (frequency == null) {
        return en
            ? 'Should this repeat weekly, monthly or yearly?'
            : 'Khoản này lặp lại hàng tuần, hàng tháng hay hàng năm?';
      }
      if (kind == 'recurring_income' && frequency != 'monthly') {
        return en
            ? 'Recurring income currently supports monthly schedules. Would you like a monthly schedule?'
            : 'Thu định kỳ hiện hỗ trợ hàng tháng. Bạn có muốn đặt lịch hàng tháng không?';
      }
      if (date == null) {
        return en
            ? 'When is the first occurrence? Please include day, month and year.'
            : 'Kỳ đầu tiên vào ngày nào? Hãy cho biết ngày, tháng và năm.';
      }
    }
    if (isWrite && kind != 'group' && kind != 'debt' && description.isEmpty) {
      return en
          ? 'What is this transaction for?'
          : 'Khoản này dùng cho việc gì?';
    }
    return null;
  }
}
