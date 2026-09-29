import 'package:flutter/foundation.dart';

@immutable
class QrPaymentDraft {
  const QrPaymentDraft({
    required this.id,
    required this.createdAt,
    required this.bankBin,
    required this.accountNumber,
    required this.recipientName,
    required this.memo,
    this.amountVnd,
    this.categoryId,
    this.bankAppId,
  });

  final String id;
  final DateTime createdAt;
  final String bankBin;
  final String accountNumber;
  final String recipientName;
  final String memo;
  final int? amountVnd;
  final String? categoryId;
  final String? bankAppId;

  QrPaymentDraft copyWith({
    String? accountNumber,
    String? recipientName,
    String? memo,
    int? amountVnd,
    bool clearAmount = false,
    String? categoryId,
    String? bankAppId,
    bool clearBankAppId = false,
  }) {
    return QrPaymentDraft(
      id: id,
      createdAt: createdAt,
      bankBin: bankBin,
      accountNumber: accountNumber ?? this.accountNumber,
      recipientName: recipientName ?? this.recipientName,
      memo: memo ?? this.memo,
      amountVnd: clearAmount ? null : amountVnd ?? this.amountVnd,
      categoryId: categoryId ?? this.categoryId,
      bankAppId: clearBankAppId ? null : bankAppId ?? this.bankAppId,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'bankBin': bankBin,
    'accountNumber': accountNumber,
    'recipientName': recipientName,
    'memo': memo,
    'amountVnd': amountVnd,
    'categoryId': categoryId,
    'bankAppId': bankAppId,
  };

  factory QrPaymentDraft.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final bankBin = json['bankBin'];
    final accountNumber = json['accountNumber'];
    final recipientName = json['recipientName'];
    final memo = json['memo'];
    final amount = json['amountVnd'];
    if (id is! String ||
        id.isEmpty ||
        createdAt == null ||
        bankBin is! String ||
        accountNumber is! String ||
        recipientName is! String ||
        memo is! String ||
        (amount != null && amount is! int)) {
      throw const FormatException('Bản nháp thanh toán QR không hợp lệ.');
    }
    return QrPaymentDraft(
      id: id,
      createdAt: createdAt.toLocal(),
      bankBin: bankBin,
      accountNumber: accountNumber,
      recipientName: recipientName,
      memo: memo,
      amountVnd: amount as int?,
      categoryId: json['categoryId'] as String?,
      bankAppId: json['bankAppId'] as String?,
    );
  }
}
