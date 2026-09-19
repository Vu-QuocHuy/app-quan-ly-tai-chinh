import '../../invoices/domain/invoice_models.dart';

abstract final class InvoiceSyncCodec {
  static const _maxSafeInteger = 9007199254740991;
  static const _maxLines = 1000;
  static const _maxEvidence = 1000;

  static InvoiceEntity fromPayload(
    Map<String, dynamic> payload, {
    required int revision,
  }) {
    if (revision < 1) {
      throw const FormatException('Invoice revision không hợp lệ.');
    }
    _validatePayloadRevision(payload['revision'], revision);
    final createdAt = _requiredDate(payload['createdAt'], 'invoice.createdAt');
    final updatedAt = _requiredDate(payload['updatedAt'], 'invoice.updatedAt');
    return InvoiceEntity(
      id: _requiredString(payload['id'], 'invoice.id', maxLength: 128),
      cloudId: _optionalString(payload['cloudId'], 'invoice.cloudId', 64),
      sellerName: _requiredString(
        payload['sellerName'],
        'invoice.sellerName',
        maxLength: 500,
      ),
      sellerTaxCode: _optionalString(
        payload['sellerTaxCode'],
        'invoice.sellerTaxCode',
        64,
      ),
      invoiceNumber: _optionalString(
        payload['invoiceNumber'],
        'invoice.invoiceNumber',
        128,
      ),
      invoiceSymbol: _optionalString(
        payload['invoiceSymbol'],
        'invoice.invoiceSymbol',
        128,
      ),
      issuedAt: _optionalDate(payload['issuedAt'], 'invoice.issuedAt'),
      currencyCode: _requiredCurrency(payload['currencyCode']),
      subtotalMinor: _nonNegativeInteger(
        payload['subtotalMinor'],
        'invoice.subtotalMinor',
      ),
      taxMinor: _nonNegativeInteger(payload['taxMinor'], 'invoice.taxMinor'),
      totalMinor: _nonNegativeInteger(
        payload['totalMinor'],
        'invoice.totalMinor',
      ),
      sourceType: _invoiceSourceType(
        payload['sourceType'],
        'invoice.sourceType',
      ),
      sourceHash: _optionalString(
        payload['sourceHash'],
        'invoice.sourceHash',
        512,
      ),
      status: _enum(InvoiceStatus.values, payload['status'], 'invoice.status'),
      categoryId: _optionalString(
        payload['categoryId'],
        'invoice.categoryId',
        128,
      ),
      notes: _optionalString(payload['notes'], 'invoice.notes', 5000),
      tags: _strings(payload['tags'], 'invoice.tags'),
      createdAt: createdAt,
      updatedAt: updatedAt,
      confirmedAt: _optionalDate(payload['confirmedAt'], 'invoice.confirmedAt'),
      syncState: InvoiceSyncState.synced,
      revision: revision,
      deletedAt: _optionalDate(payload['deletedAt'], 'invoice.deletedAt'),
      lines: _lines(payload['lines']),
      evidence: _evidence(payload['evidence']),
    );
  }

  static String _requiredString(
    Object? value,
    String field, {
    required int maxLength,
  }) {
    final result = _optionalString(value, field, maxLength);
    if (result == null || result.trim().isEmpty) {
      throw FormatException('$field thiếu giá trị.');
    }
    return result;
  }

  static String? _optionalString(Object? value, String field, int maxLength) {
    if (value == null) return null;
    if (value is! String || value.length > maxLength) {
      throw FormatException('$field không hợp lệ.');
    }
    return value;
  }

  static String _requiredCurrency(Object? value) {
    final result = _requiredString(
      value,
      'invoice.currencyCode',
      maxLength: 12,
    );
    if (result.length < 3) {
      throw const FormatException('invoice.currencyCode không hợp lệ.');
    }
    return result;
  }

  static DateTime _requiredDate(Object? value, String field) {
    final result = _optionalDate(value, field);
    if (result == null) {
      throw FormatException('$field thiếu giá trị.');
    }
    return result;
  }

  static DateTime? _optionalDate(Object? value, String field) {
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('$field không hợp lệ.');
    }
    final result = DateTime.tryParse(value);
    if (result == null) {
      throw FormatException('$field không hợp lệ.');
    }
    return result.toLocal();
  }

  static int _nonNegativeInteger(Object? value, String field) {
    final result = _integer(value, field);
    if (result < 0) {
      throw FormatException('$field không được âm.');
    }
    return result;
  }

  static int? _optionalNonNegativeInteger(Object? value, String field) {
    if (value == null) return null;
    return _nonNegativeInteger(value, field);
  }

  static int _integer(Object? value, String field) {
    if (value is! num || !value.toDouble().isFinite) {
      throw FormatException('$field không phải số nguyên.');
    }
    if (value < -_maxSafeInteger ||
        value > _maxSafeInteger ||
        value != value.truncate()) {
      throw FormatException('$field không phải số nguyên hợp lệ.');
    }
    return value.toInt();
  }

  static double? _optionalNonNegativeDouble(Object? value, String field) {
    if (value == null) return null;
    if (value is! num) {
      throw FormatException('$field không hợp lệ.');
    }
    final result = value.toDouble();
    if (!result.isFinite || result < 0) {
      throw FormatException('$field không hợp lệ.');
    }
    return result;
  }

  static double? _optionalTaxRate(Object? value, String field) {
    final result = _optionalNonNegativeDouble(value, field);
    if (result != null && result > 100) {
      throw FormatException('$field không hợp lệ.');
    }
    return result;
  }

  static List<String> _strings(Object? value, String field) {
    if (value == null) return const [];
    if (value is! List || value.length > 100) {
      throw FormatException('$field không hợp lệ.');
    }
    return [
      for (var index = 0; index < value.length; index++)
        _requiredString(value[index], '$field[$index]', maxLength: 128),
    ];
  }

  static List<InvoiceLineEntity> _lines(Object? value) {
    if (value == null) return const [];
    if (value is! List || value.length > _maxLines) {
      throw const FormatException('invoice.lines không hợp lệ.');
    }
    final ids = <String>{};
    final lines = <InvoiceLineEntity>[];
    for (var index = 0; index < value.length; index++) {
      final raw = value[index];
      if (raw is! Map) {
        throw FormatException('invoice.lines[$index] không hợp lệ.');
      }
      final id = _requiredString(
        raw['id'],
        'invoice.lines[$index].id',
        maxLength: 128,
      );
      if (!ids.add(id)) {
        throw FormatException('invoice.lines[$index].id bị trùng.');
      }
      lines.add(
        InvoiceLineEntity(
          id: id,
          description: _requiredString(
            raw['description'],
            'invoice.lines[$index].description',
            maxLength: 500,
          ),
          quantity: _optionalNonNegativeDouble(
            raw['quantity'],
            'invoice.lines[$index].quantity',
          ),
          unitPriceMinor: _optionalNonNegativeInteger(
            raw['unitPriceMinor'],
            'invoice.lines[$index].unitPriceMinor',
          ),
          taxRate: _optionalTaxRate(
            raw['taxRate'],
            'invoice.lines[$index].taxRate',
          ),
          totalMinor: _nonNegativeInteger(
            raw['totalMinor'],
            'invoice.lines[$index].totalMinor',
          ),
          categoryId: _optionalString(
            raw['categoryId'],
            'invoice.lines[$index].categoryId',
            128,
          ),
        ),
      );
    }
    return lines;
  }

  static List<FieldEvidenceEntity> _evidence(Object? value) {
    if (value == null) return const [];
    if (value is! List || value.length > _maxEvidence) {
      throw const FormatException('invoice.evidence không hợp lệ.');
    }
    final ids = <String>{};
    final evidence = <FieldEvidenceEntity>[];
    for (var index = 0; index < value.length; index++) {
      final raw = value[index];
      if (raw is! Map) {
        throw FormatException('invoice.evidence[$index] không hợp lệ.');
      }
      final id = _requiredString(
        raw['id'],
        'invoice.evidence[$index].id',
        maxLength: 128,
      );
      if (!ids.add(id)) {
        throw FormatException('invoice.evidence[$index].id bị trùng.');
      }
      evidence.add(
        FieldEvidenceEntity(
          id: id,
          fieldName: _requiredString(
            raw['fieldName'],
            'invoice.evidence[$index].fieldName',
            maxLength: 64,
          ),
          rawValue: _optionalString(
            raw['rawValue'],
            'invoice.evidence[$index].rawValue',
            5000,
          ),
          normalizedValue:
              _optionalString(
                raw['normalizedValue'],
                'invoice.evidence[$index].normalizedValue',
                5000,
              ) ??
              '',
          source: _invoiceSourceType(
            raw['sourceType'],
            'invoice.evidence[$index].sourceType',
          ),
          confidence: _confidence(
            raw['confidence'],
            'invoice.evidence[$index].confidence',
          ),
          correctedByUser: _optionalBool(
            raw['correctedByUser'],
            'invoice.evidence[$index].correctedByUser',
          ),
        ),
      );
    }
    return evidence;
  }

  static double _confidence(Object? value, String field) {
    if (value is! num) {
      throw FormatException('$field không hợp lệ.');
    }
    final result = value.toDouble();
    if (!result.isFinite || result < 0 || result > 1) {
      throw FormatException('$field không hợp lệ.');
    }
    return result;
  }

  static bool _optionalBool(Object? value, String field) {
    if (value == null) return false;
    if (value is! bool) {
      throw FormatException('$field không hợp lệ.');
    }
    return value;
  }

  static T _enum<T extends Enum>(List<T> values, Object? value, String field) {
    if (value is! String) {
      throw FormatException('$field không hợp lệ.');
    }
    for (final item in values) {
      if (item.name == value) return item;
    }
    throw FormatException('$field không được hỗ trợ.');
  }

  static InvoiceSourceType _invoiceSourceType(Object? value, String field) {
    if (value == 'qr') return InvoiceSourceType.imageOcr;
    return _enum(InvoiceSourceType.values, value, field);
  }

  static void _validatePayloadRevision(Object? value, int revision) {
    if (value == null) return;
    if (_integer(value, 'invoice.revision') != revision) {
      throw const FormatException('Invoice revision không đồng nhất.');
    }
  }
}
