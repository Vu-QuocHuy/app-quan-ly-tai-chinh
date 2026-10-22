import 'dart:convert';

enum DebtType {
  /// Mình nợ người khác (Cần trả / Đi vay)
  iOwe,

  /// Người khác nợ mình (Cần thu / Cho vay)
  theyOwe,
}

enum DebtStatus {
  active,
  settled,
}

class DebtRecord {
  const DebtRecord({
    required this.id,
    required this.personName,
    this.phoneNumber,
    required this.type,
    required this.amountMinor,
    this.paidAmountMinor = 0,
    this.dueDate,
    required this.createdAt,
    this.notes,
    this.status = DebtStatus.active,
    this.settledAt,
  });

  final String id;
  final String personName;
  final String? phoneNumber;
  final DebtType type;
  final int amountMinor;
  final int paidAmountMinor;
  final DateTime? dueDate;
  final DateTime createdAt;
  final String? notes;
  final DebtStatus status;
  final DateTime? settledAt;

  int get remainingMinor => (amountMinor - paidAmountMinor).clamp(0, amountMinor);

  bool get isSettled => status == DebtStatus.settled || remainingMinor <= 0;

  bool get isOverdue =>
      !isSettled && dueDate != null && DateTime.now().isAfter(dueDate!);

  double get progress =>
      amountMinor > 0 ? (paidAmountMinor / amountMinor).clamp(0.0, 1.0) : 1.0;

  DebtRecord copyWith({
    String? id,
    String? personName,
    String? phoneNumber,
    DebtType? type,
    int? amountMinor,
    int? paidAmountMinor,
    DateTime? dueDate,
    DateTime? createdAt,
    String? notes,
    DebtStatus? status,
    DateTime? settledAt,
  }) {
    return DebtRecord(
      id: id ?? this.id,
      personName: personName ?? this.personName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      type: type ?? this.type,
      amountMinor: amountMinor ?? this.amountMinor,
      paidAmountMinor: paidAmountMinor ?? this.paidAmountMinor,
      dueDate: dueDate ?? this.dueDate,
      createdAt: createdAt ?? this.createdAt,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      settledAt: settledAt ?? this.settledAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'personName': personName,
    'phoneNumber': phoneNumber,
    'type': type.name,
    'amountMinor': amountMinor,
    'paidAmountMinor': paidAmountMinor,
    'dueDate': dueDate?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'notes': notes,
    'status': status.name,
    'settledAt': settledAt?.toIso8601String(),
  };

  factory DebtRecord.fromJson(Map<String, dynamic> json) {
    return DebtRecord(
      id: json['id'] as String,
      personName: json['personName'] as String,
      phoneNumber: json['phoneNumber'] as String?,
      type: DebtType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => DebtType.theyOwe,
      ),
      amountMinor: (json['amountMinor'] as num).toInt(),
      paidAmountMinor: ((json['paidAmountMinor'] ?? 0) as num).toInt(),
      dueDate: json['dueDate'] != null
          ? DateTime.tryParse(json['dueDate'] as String)
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      notes: json['notes'] as String?,
      status: DebtStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DebtStatus.active,
      ),
      settledAt: json['settledAt'] != null
          ? DateTime.tryParse(json['settledAt'] as String)
          : null,
    );
  }
}

class DebtSummary {
  const DebtSummary({
    required this.totalReceivableMinor,
    required this.totalPayableMinor,
    required this.activeReceivableCount,
    required this.activePayableCount,
  });

  /// Tổng tiền người khác nợ mình (Cần thu)
  final int totalReceivableMinor;

  /// Tổng tiền mình nợ người khác (Cần trả)
  final int totalPayableMinor;

  /// Số khoản cần thu đang hoạt động
  final int activeReceivableCount;

  /// Số khoản cần trả đang hoạt động
  final int activePayableCount;

  /// Chênh lệch ròng (Cần thu - Cần trả)
  int get netBalanceMinor => totalReceivableMinor - totalPayableMinor;
}
