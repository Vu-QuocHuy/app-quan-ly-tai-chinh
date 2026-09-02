import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/ingestion/domain/extraction.dart';
import 'package:hoadon_insight/features/ingestion/domain/invoice_extractor_registry.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  test('resolves the first extractor that can handle an input', () async {
    final registry = InvoiceExtractorRegistry([
      _FakeExtractor('first', canHandleResult: false),
      _FakeExtractor('second', canHandleResult: true),
    ]);

    final result = await registry.extract(_input());

    expect(result.adapterName, 'second');
  });

  test('throws when no extractor supports an input', () async {
    final registry = InvoiceExtractorRegistry([
      _FakeExtractor('first', canHandleResult: false),
    ]);

    expect(() => registry.extract(_input()), throwsA(isA<Exception>()));
  });
}

ExtractionInput _input() => ExtractionInput(
  bytes: Uint8List(0),
  fileName: 'unknown.bin',
  sourceType: InvoiceSourceType.xml,
);

class _FakeExtractor implements InvoiceExtractor {
  _FakeExtractor(this.adapterName, {required this.canHandleResult});

  @override
  final String adapterName;

  final bool canHandleResult;

  @override
  String get adapterVersion => '1.0.0';

  @override
  bool canHandle(ExtractionInput input) => canHandleResult;

  @override
  Future<ExtractionResult> extract(ExtractionInput input) async {
    final now = DateTime(2026, 8, 30);
    return ExtractionResult(
      invoice: InvoiceEntity(
        id: adapterName,
        sellerName: adapterName,
        currencyCode: 'VND',
        subtotalMinor: 1,
        taxMinor: 0,
        totalMinor: 1,
        sourceType: input.sourceType,
        status: InvoiceStatus.needsReview,
        createdAt: now,
        updatedAt: now,
      ),
      adapterName: adapterName,
      adapterVersion: adapterVersion,
    );
  }
}
