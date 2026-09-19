import 'package:flutter/foundation.dart';

import '../../invoices/domain/invoice_models.dart';

@immutable
class SharedBillLine {
  const SharedBillLine({required this.description, required this.totalMinor});

  final String description;
  final int totalMinor;

  factory SharedBillLine.fromMap(Object? value) {
    if (value is! Map) {
      throw const FormatException('Dòng hóa đơn chia sẻ không hợp lệ.');
    }
    final map = Map<String, dynamic>.from(value);
    final description = _requiredString(map['description'], 'description', 240);
    final totalMinor = _requiredInt(map['total_minor'], 'total_minor');
    if (totalMinor < 0) {
      throw const FormatException('Giá trị dòng hóa đơn không hợp lệ.');
    }
    return SharedBillLine(description: description, totalMinor: totalMinor);
  }

  Map<String, dynamic> toMap() => {
    'description': description,
    'total_minor': totalMinor,
  };
}

@immutable
class SharedBillSnapshot {
  const SharedBillSnapshot({
    required this.sellerName,
    required this.currencyCode,
    required this.totalMinor,
    this.sellerTaxCode,
    this.invoiceNumber,
    this.invoiceSymbol,
    this.issuedAt,
    this.subtotalMinor = 0,
    this.taxMinor = 0,
    this.lines = const [],
  });

  final String sellerName;
  final String? sellerTaxCode;
  final String? invoiceNumber;
  final String? invoiceSymbol;
  final DateTime? issuedAt;
  final String currencyCode;
  final int subtotalMinor;
  final int taxMinor;
  final int totalMinor;
  final List<SharedBillLine> lines;

  factory SharedBillSnapshot.fromInvoice(InvoiceEntity invoice) {
    return SharedBillSnapshot(
      sellerName: invoice.sellerName,
      sellerTaxCode: invoice.sellerTaxCode,
      invoiceNumber: invoice.invoiceNumber,
      invoiceSymbol: invoice.invoiceSymbol,
      issuedAt: invoice.issuedAt,
      currencyCode: invoice.currencyCode,
      subtotalMinor: invoice.subtotalMinor,
      taxMinor: invoice.taxMinor,
      totalMinor: invoice.totalMinor,
      lines: [
        for (final line in invoice.lines)
          if (line.totalMinor >= 0)
            SharedBillLine(
              description: line.description,
              totalMinor: line.totalMinor,
            ),
      ],
    );
  }

  factory SharedBillSnapshot.fromMap(Object? value) {
    if (value is! Map) {
      throw const FormatException('Dữ liệu hóa đơn chia sẻ không hợp lệ.');
    }
    final map = Map<String, dynamic>.from(value);
    final linesValue = map['lines'];
    final lines = linesValue == null
        ? const <SharedBillLine>[]
        : (linesValue is List
              ? linesValue.map(SharedBillLine.fromMap).toList(growable: false)
              : throw const FormatException(
                  'Danh sách dòng hóa đơn không hợp lệ.',
                ));
    final totalMinor = _requiredInt(map['total_minor'], 'total_minor');
    if (totalMinor <= 0) {
      throw const FormatException('Tổng hóa đơn chia sẻ không hợp lệ.');
    }
    final issuedAtValue = map['issued_at'];
    final issuedAt = issuedAtValue == null
        ? null
        : DateTime.tryParse(issuedAtValue.toString());
    if (issuedAtValue != null && issuedAt == null) {
      throw const FormatException('Ngày hóa đơn chia sẻ không hợp lệ.');
    }
    return SharedBillSnapshot(
      sellerName: _requiredString(map['seller_name'], 'seller_name', 240),
      sellerTaxCode: _optionalString(
        map['seller_tax_code'],
        'seller_tax_code',
        80,
      ),
      invoiceNumber: _optionalString(
        map['invoice_number'],
        'invoice_number',
        120,
      ),
      invoiceSymbol: _optionalString(
        map['invoice_symbol'],
        'invoice_symbol',
        120,
      ),
      issuedAt: issuedAt,
      currencyCode: _requiredString(map['currency_code'], 'currency_code', 12),
      subtotalMinor: _nonNegativeInt(map['subtotal_minor'], 'subtotal_minor'),
      taxMinor: _nonNegativeInt(map['tax_minor'], 'tax_minor'),
      totalMinor: totalMinor,
      lines: lines,
    );
  }

  Map<String, dynamic> toMap() => {
    'seller_name': sellerName,
    if (sellerTaxCode != null) 'seller_tax_code': sellerTaxCode,
    if (invoiceNumber != null) 'invoice_number': invoiceNumber,
    if (invoiceSymbol != null) 'invoice_symbol': invoiceSymbol,
    if (issuedAt != null) 'issued_at': issuedAt!.toUtc().toIso8601String(),
    'currency_code': currencyCode,
    'subtotal_minor': subtotalMinor,
    'tax_minor': taxMinor,
    'total_minor': totalMinor,
    'lines': [for (final line in lines) line.toMap()],
  };
}

@immutable
class DirectBillShare {
  const DirectBillShare({
    required this.id,
    required this.ownerId,
    required this.recipientEmail,
    required this.sourceInvoiceId,
    required this.snapshot,
    required this.totalMinor,
    required this.ownerAmountMinor,
    required this.recipientAmountMinor,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.recipientId,
    this.acceptedAt,
  });

  final String id;
  final String ownerId;
  final String? recipientId;
  final String recipientEmail;
  final String sourceInvoiceId;
  final SharedBillSnapshot snapshot;
  final int totalMinor;
  final int ownerAmountMinor;
  final int recipientAmountMinor;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? acceptedAt;

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';

  factory DirectBillShare.fromMap(Object? value) {
    if (value is! Map) {
      throw const FormatException('Dữ liệu chia sẻ hóa đơn không hợp lệ.');
    }
    final map = Map<String, dynamic>.from(value);
    final status = _requiredString(map['status'], 'status', 16);
    if (!const {
      'pending',
      'accepted',
      'declined',
      'revoked',
    }.contains(status)) {
      throw const FormatException('Trạng thái chia sẻ hóa đơn không hợp lệ.');
    }
    final totalMinor = _positiveInt(map['total_minor'], 'total_minor');
    final ownerAmountMinor = _nonNegativeInt(
      map['owner_amount_minor'],
      'owner_amount_minor',
    );
    final recipientAmountMinor = _nonNegativeInt(
      map['recipient_amount_minor'],
      'recipient_amount_minor',
    );
    if (ownerAmountMinor + recipientAmountMinor != totalMinor) {
      throw const FormatException('Phần chia hóa đơn không khớp tổng tiền.');
    }
    return DirectBillShare(
      id: _requiredUuid(map['id'], 'id'),
      ownerId: _requiredUuid(map['owner_id'], 'owner_id'),
      recipientId: _optionalUuid(map['recipient_id'], 'recipient_id'),
      recipientEmail: _requiredString(
        map['recipient_email'],
        'recipient_email',
        320,
      ),
      sourceInvoiceId: _requiredString(
        map['source_invoice_id'],
        'source_invoice_id',
        128,
      ),
      snapshot: SharedBillSnapshot.fromMap(map['source_snapshot']),
      totalMinor: totalMinor,
      ownerAmountMinor: ownerAmountMinor,
      recipientAmountMinor: recipientAmountMinor,
      status: status,
      createdAt: _requiredDate(map['created_at'], 'created_at'),
      updatedAt: _requiredDate(map['updated_at'], 'updated_at'),
      acceptedAt: _optionalDate(map['accepted_at'], 'accepted_at'),
    );
  }
}

Map<String, dynamic> invoiceShareSnapshot(InvoiceEntity invoice) {
  return SharedBillSnapshot.fromInvoice(invoice).toMap();
}

String _requiredString(Object? value, String field, int maxLength) {
  if (value is! String || value.trim().isEmpty || value.length > maxLength) {
    throw FormatException('$field không hợp lệ.');
  }
  return value;
}

String? _optionalString(Object? value, String field, int maxLength) {
  if (value == null) return null;
  return _requiredString(value, field, maxLength);
}

int _requiredInt(Object? value, String field) {
  if (value is! num ||
      !value.toDouble().isFinite ||
      value != value.truncate()) {
    throw FormatException('$field không hợp lệ.');
  }
  return value.toInt();
}

int _nonNegativeInt(Object? value, String field) {
  final result = _requiredInt(value, field);
  if (result < 0) throw FormatException('$field không hợp lệ.');
  return result;
}

int _positiveInt(Object? value, String field) {
  final result = _requiredInt(value, field);
  if (result < 1) throw FormatException('$field không hợp lệ.');
  return result;
}

String _requiredUuid(Object? value, String field) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false,
      ).hasMatch(value)) {
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
