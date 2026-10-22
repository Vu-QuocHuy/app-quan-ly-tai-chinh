class DebtInAppNotification {
  const DebtInAppNotification({
    required this.id,
    required this.targetPhone,
    required this.senderName,
    this.senderPhone,
    this.debtId,
    this.savedDebtId,
    required this.amountMinor,
    this.notes,
    this.dueDate,
    required this.createdAt,
    this.isRead = false,
    this.isSaved = false,
  });

  final String id;
  final String targetPhone;
  final String senderName;
  final String? senderPhone;
  final String? debtId;
  final String? savedDebtId;
  final int amountMinor;
  final String? notes;
  final DateTime? dueDate;
  final DateTime createdAt;
  final bool isRead;
  final bool isSaved;

  Map<String, dynamic> toJson() => {
    'id': id,
    'targetPhone': targetPhone,
    'senderName': senderName,
    'senderPhone': senderPhone,
    'debtId': debtId,
    'savedDebtId': savedDebtId,
    'amountMinor': amountMinor,
    'notes': notes,
    'dueDate': dueDate?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'isRead': isRead,
    'isSaved': isSaved,
  };

  factory DebtInAppNotification.fromJson(Map<String, dynamic> json) =>
      DebtInAppNotification(
        id: json['id'] as String,
        targetPhone: json['targetPhone'] as String,
        senderName: json['senderName'] as String,
        senderPhone: json['senderPhone'] as String?,
        debtId: json['debtId'] as String?,
        savedDebtId: json['savedDebtId'] as String?,
        amountMinor: json['amountMinor'] as int,
        notes: json['notes'] as String?,
        dueDate: json['dueDate'] != null
            ? DateTime.tryParse(json['dueDate'] as String)
            : null,
        createdAt: DateTime.parse(json['createdAt'] as String),
        isRead: json['isRead'] as bool? ?? false,
        isSaved: json['isSaved'] as bool? ?? false,
      );

  DebtInAppNotification copyWith({
    bool? isRead,
    bool? isSaved,
    String? savedDebtId,
  }) => DebtInAppNotification(
    id: id,
    targetPhone: targetPhone,
    senderName: senderName,
    senderPhone: senderPhone,
    debtId: debtId,
    savedDebtId: savedDebtId ?? this.savedDebtId,
    amountMinor: amountMinor,
    notes: notes,
    dueDate: dueDate,
    createdAt: createdAt,
    isRead: isRead ?? this.isRead,
    isSaved: isSaved ?? this.isSaved,
  );
}
