/// Một người trong bill mà người ngoài nhóm đã vào (từ `list_my_external_bills`).
class ExternalBillParticipant {
  const ExternalBillParticipant({
    required this.name,
    required this.amountMinor,
    required this.settled,
    required this.isMe,
  });

  factory ExternalBillParticipant.fromJson(Object? value) {
    final map = _object(value, 'participant');
    return ExternalBillParticipant(
      name: _string(map, 'name'),
      amountMinor: _amount(map, 'amount_minor'),
      settled: _bool(map, 'settled'),
      isMe: _bool(map, 'is_me'),
    );
  }

  final String name;
  final int amountMinor;
  final bool settled;
  final bool isMe;
}

/// Bill mà người dùng tham gia qua QR nhưng không là thành viên nhóm của bill.
/// Không mang `group_id` hay `user_id` của người khác.
class ExternalBill {
  const ExternalBill({
    required this.id,
    required this.description,
    required this.totalMinor,
    required this.createdAt,
    required this.payerName,
    required this.isOpen,
    required this.myAmountMinor,
    required this.mySettledAt,
    required this.participants,
  });

  factory ExternalBill.fromJson(Object? value) {
    final map = _object(value, 'external_bill');
    final participants = map['participants'];
    if (participants is! List) {
      throw const FormatException('external_bill.participants không hợp lệ.');
    }
    final mySettledAt = map['my_settled_at'];
    return ExternalBill(
      id: _string(map, 'id'),
      description: _string(map, 'description'),
      totalMinor: _amount(map, 'total_minor'),
      createdAt: _date(map['created_at'], 'created_at'),
      payerName: _string(map, 'payer_name'),
      isOpen: _bool(map, 'is_open'),
      myAmountMinor: _amount(map, 'my_amount_minor'),
      mySettledAt: mySettledAt == null
          ? null
          : _date(mySettledAt, 'my_settled_at'),
      participants: List.unmodifiable(
        participants.map(ExternalBillParticipant.fromJson),
      ),
    );
  }

  final String id;
  final String description;
  final int totalMinor;
  final DateTime createdAt;
  final String payerName;
  final bool isOpen;
  final int myAmountMinor;
  final DateTime? mySettledAt;
  final List<ExternalBillParticipant> participants;

  bool get isMineSettled => mySettledAt != null;

  /// Đã có người thanh toán thì không ai rời bill được nữa.
  bool get hasSettlement => participants.any((item) => item.settled);
}

Map<String, dynamic> _object(Object? value, String field) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw FormatException('$field không hợp lệ.');
  }
  return Map<String, dynamic>.from(value);
}

String _string(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('external_bill.$key không hợp lệ.');
  }
  return value;
}

int _amount(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! int || value < 0 || value > 9007199254740991) {
    throw FormatException('external_bill.$key không hợp lệ.');
  }
  return value;
}

bool _bool(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! bool) throw FormatException('external_bill.$key không hợp lệ.');
  return value;
}

DateTime _date(Object? value, String key) {
  final result = value is String ? DateTime.tryParse(value) : null;
  if (result == null) throw FormatException('external_bill.$key không hợp lệ.');
  return result.toLocal();
}
