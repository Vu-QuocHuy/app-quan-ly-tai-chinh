import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/ingestion/data/heuristic_text_extractor.dart';
import 'package:hoadon_insight/features/ingestion/domain/extraction.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  test('keeps an impossible OCR date unresolved for review', () async {
    final result = await HeuristicTextExtractor().extract(
      ExtractionInput(
        bytes: Uint8List.fromList('receipt'.codeUnits),
        fileName: 'receipt.jpg',
        sourceType: InvoiceSourceType.imageOcr,
        ocrText: 'CỬA HÀNG DEMO\nNgày 31/02/2026\nTổng tiền: 100000',
      ),
    );

    expect(result.invoice.issuedAt, isNull);
    expect(result.invoice.status, InvoiceStatus.needsReview);
  });
}
