import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/errors/app_exception.dart';
import 'package:hoadon_insight/features/ingestion/data/ai_extraction_client.dart';
import 'package:hoadon_insight/features/ingestion/domain/extraction.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  final input = ExtractionInput(
    bytes: Uint8List.fromList([1, 2, 3]),
    fileName: 'receipt.jpg',
    sourceType: InvoiceSourceType.imageOcr,
  );

  test('parses a validated AI invoice and its item categories', () {
    final result = AiExtractionClient(enabled: false).parseResponse({
      'invoice': {
        'sellerName': 'Siêu thị Demo',
        'sellerTaxCode': null,
        'invoiceNumber': 'HD-001',
        'invoiceSymbol': null,
        'invoiceDate': '2026-09-17',
        'currencyCode': 'VND',
        'subtotalMinor': 100000,
        'taxMinor': 10000,
        'totalMinor': 110000,
        'categoryId': 'shopping',
        'items': [
          {
            'description': 'Gạo',
            'quantity': 1,
            'unitPriceMinor': 100000,
            'taxRate': 0,
            'totalMinor': 100000,
            'categoryId': 'food',
          },
        ],
      },
      'evidence': [
        {
          'field': 'totalMinor',
          'rawValue': '110.000',
          'value': '110000',
          'confidence': 0.9,
        },
      ],
    }, input);

    expect(result.invoice.sellerName, 'Siêu thị Demo');
    expect(result.invoice.categoryId, 'shopping');
    expect(result.invoice.lines.single.categoryId, 'food');
    expect(result.invoice.evidence.single.confidence, 0.9);
    expect(result.invoice.status, InvoiceStatus.needsReview);
  });

  test('rejects malformed AI amounts and nested collections', () {
    final client = AiExtractionClient(enabled: false);
    final invalidAmount = _validResponse();
    (invalidAmount['invoice'] as Map<String, dynamic>)['totalMinor'] = 10.5;
    expect(
      () => client.parseResponse(invalidAmount, input),
      throwsA(isA<ExtractionException>()),
    );

    final excessiveItems = _validResponse();
    (excessiveItems['invoice']
        as Map<String, dynamic>)['items'] = List.generate(
      201,
      (index) => {
        'description': 'Mặt hàng $index',
        'quantity': 1,
        'unitPriceMinor': 1,
        'taxRate': 0,
        'totalMinor': 1,
        'categoryId': 'other',
      },
    );
    expect(
      () => client.parseResponse(excessiveItems, input),
      throwsA(isA<ExtractionException>()),
    );
  });
}

Map<String, dynamic> _validResponse() => {
  'invoice': {
    'sellerName': 'Cửa hàng',
    'sellerTaxCode': null,
    'invoiceNumber': null,
    'invoiceSymbol': null,
    'invoiceDate': null,
    'currencyCode': 'VND',
    'subtotalMinor': 1,
    'taxMinor': 0,
    'totalMinor': 1,
    'categoryId': 'other',
    'items': <Object?>[],
  },
  'evidence': <Object?>[],
};
