import '../../invoices/domain/invoice_models.dart';

abstract final class InvoiceSyncCodec {
  static InvoiceEntity fromPayload(
    Map<String, dynamic> payload, {
    required int revision,
  }) {
    final now = DateTime.now();
    return InvoiceEntity(
      id: _string(payload['id']) ?? '',
      cloudId: _string(payload['cloudId']),
      sellerName: _string(payload['sellerName']) ?? '',
      sellerTaxCode: _string(payload['sellerTaxCode']),
      invoiceNumber: _string(payload['invoiceNumber']),
      invoiceSymbol: _string(payload['invoiceSymbol']),
      issuedAt: _date(payload['issuedAt']),
      currencyCode: _string(payload['currencyCode']) ?? 'VND',
      subtotalMinor: _int(payload['subtotalMinor']),
      taxMinor: _int(payload['taxMinor']),
      totalMinor: _int(payload['totalMinor']),
      sourceType: _enum(
        InvoiceSourceType.values,
        _string(payload['sourceType']),
        InvoiceSourceType.manual,
      ),
      sourceHash: _string(payload['sourceHash']),
      status: _enum(
        InvoiceStatus.values,
        _string(payload['status']),
        InvoiceStatus.needsReview,
      ),
      categoryId: _string(payload['categoryId']),
      notes: _string(payload['notes']),
      tags: _strings(payload['tags']),
      createdAt: _date(payload['createdAt']) ?? now,
      updatedAt: _date(payload['updatedAt']) ?? now,
      confirmedAt: _date(payload['confirmedAt']),
      syncState: InvoiceSyncState.synced,
      revision: revision,
      deletedAt: _date(payload['deletedAt']),
      lines: _lines(payload['lines']),
      evidence: _evidence(payload['evidence']),
    );
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final result = '$value';
    return result.isEmpty ? null : result;
  }

  static DateTime? _date(Object? value) {
    final string = _string(value);
    return string == null ? null : DateTime.tryParse(string)?.toLocal();
  }

  static int _int(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static double? _double(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  static List<String> _strings(Object? value) {
    if (value is! List) return const [];
    return value.map(_string).whereType<String>().toList(growable: false);
  }

  static List<InvoiceLineEntity> _lines(Object? value) {
    if (value is! List) return const [];
    return [
      for (final raw in value)
        if (raw is Map)
          InvoiceLineEntity(
            id: _string(raw['id']) ?? '',
            description: _string(raw['description']) ?? '',
            quantity: _double(raw['quantity']),
            unitPriceMinor: raw['unitPriceMinor'] == null
                ? null
                : _int(raw['unitPriceMinor']),
            taxRate: _double(raw['taxRate']),
            totalMinor: _int(raw['totalMinor']),
          ),
    ];
  }

  static List<FieldEvidenceEntity> _evidence(Object? value) {
    if (value is! List) return const [];
    return [
      for (final raw in value)
        if (raw is Map)
          FieldEvidenceEntity(
            id: _string(raw['id']) ?? '',
            fieldName: _string(raw['fieldName']) ?? '',
            rawValue: _string(raw['rawValue']),
            normalizedValue: _string(raw['normalizedValue']) ?? '',
            source: _enum(
              InvoiceSourceType.values,
              _string(raw['sourceType']),
              InvoiceSourceType.manual,
            ),
            confidence: _double(raw['confidence']) ?? 0,
            correctedByUser: raw['correctedByUser'] == true,
          ),
    ];
  }

  static T _enum<T extends Enum>(List<T> values, String? name, T fallback) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }
}
