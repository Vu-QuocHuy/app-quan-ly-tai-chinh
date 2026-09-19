import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/features/sync/data/invoice_sync_codec.dart';
import 'package:hoadon_insight/features/sync/data/reference_sync_codec.dart';

void main() {
  group('InvoiceSyncCodec', () {
    test('decodes a valid invoice and nested data', () {
      final invoice = InvoiceSyncCodec.fromPayload(
        _invoicePayload(
          revision: 3,
          lines: [
            {
              'id': 'line-1',
              'description': 'Coffee',
              'quantity': 2,
              'unitPriceMinor': 15000,
              'taxRate': 8,
              'totalMinor': 30000,
              'categoryId': 'food',
            },
          ],
          evidence: [
            {
              'id': 'evidence-1',
              'fieldName': 'totalMinor',
              'rawValue': '30.000',
              'normalizedValue': '30000',
              'sourceType': 'imageOcr',
              'confidence': 0.98,
              'correctedByUser': true,
            },
          ],
        ),
        revision: 3,
      );

      expect(invoice.id, 'invoice-1');
      expect(invoice.status, InvoiceStatus.confirmed);
      expect(invoice.lines.single.categoryId, 'food');
      expect(invoice.evidence.single.correctedByUser, isTrue);
    });

    test('rejects fractional or negative monetary values', () {
      expect(
        () => InvoiceSyncCodec.fromPayload(
          _invoicePayload(totalMinor: 100.5),
          revision: 1,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => InvoiceSyncCodec.fromPayload(
          _invoicePayload(totalMinor: -1),
          revision: 1,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects unknown enum values and malformed nested records', () {
      final unknownStatus = _invoicePayload()..['status'] = 'unknown';
      expect(
        () => InvoiceSyncCodec.fromPayload(unknownStatus, revision: 1),
        throwsA(isA<FormatException>()),
      );

      final malformedLine = _invoicePayload(
        lines: [
          {'id': 'line-1', 'description': 'Coffee', 'totalMinor': 100},
          {'id': 'line-1', 'description': 'Tea', 'totalMinor': 100},
        ],
      );
      expect(
        () => InvoiceSyncCodec.fromPayload(malformedLine, revision: 1),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a payload revision that differs from the delta revision', () {
      expect(
        () => InvoiceSyncCodec.fromPayload(
          _invoicePayload(revision: 2),
          revision: 1,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ReferenceSyncCodec', () {
    test('decodes valid category, budget and merchant rule payloads', () {
      final category = ReferenceSyncCodec.categoryFromPayload({
        'id': 'food',
        'name': 'Ăn uống',
        'iconName': 'restaurant',
        'colorValue': 4293548044,
        'isSystem': true,
      });
      final budget = ReferenceSyncCodec.budgetFromPayload({
        'id': 'budget-1',
        'monthKey': '2026-09',
        'categoryId': 'food',
        'limitMinor': 2000000,
      });
      final rule = ReferenceSyncCodec.merchantRuleFromPayload({
        'id': 'cloud store',
        'normalizedMerchant': 'cloud store',
        'categoryId': 'shopping',
        'updatedAt': '2026-09-01T00:00:00.000Z',
      });

      expect(category.isSystem, isTrue);
      expect(budget.monthKey, '2026-09');
      expect(rule.normalizedMerchant, 'cloud store');
    });

    test('rejects invalid month, amount and timestamp values', () {
      expect(
        () => ReferenceSyncCodec.budgetFromPayload({
          'id': 'budget-1',
          'monthKey': '2026-13',
          'categoryId': 'food',
          'limitMinor': 100,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ReferenceSyncCodec.budgetFromPayload({
          'id': 'budget-1',
          'monthKey': '2026-09',
          'categoryId': 'food',
          'limitMinor': -1,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ReferenceSyncCodec.merchantRuleFromPayload({
          'id': 'cloud store',
          'categoryId': 'shopping',
          'updatedAt': 'not-a-date',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

Map<String, dynamic> _invoicePayload({
  Object totalMinor = 100,
  int? revision,
  List<Map<String, Object?>> lines = const [],
  List<Map<String, Object?>> evidence = const [],
}) {
  return {
    'id': 'invoice-1',
    'sellerName': 'Cloud Store',
    'currencyCode': 'VND',
    'subtotalMinor': 100,
    'taxMinor': 0,
    'totalMinor': totalMinor,
    'sourceType': 'manual',
    'status': 'confirmed',
    'createdAt': '2026-09-01T00:00:00.000Z',
    'updatedAt': '2026-09-01T00:00:00.000Z',
    'revision': revision,
    'lines': lines,
    'evidence': evidence,
    'tags': <String>[],
  };
}
