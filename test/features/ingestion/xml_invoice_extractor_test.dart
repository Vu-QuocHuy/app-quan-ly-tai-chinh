import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/errors/app_exception.dart';
import 'package:hoadon_insight/features/ingestion/data/xml_invoice_extractor.dart';
import 'package:hoadon_insight/features/ingestion/domain/extraction.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  group('XmlInvoiceExtractor', () {
    final extractor = XmlInvoiceExtractor();

    test(
      'parses namespaced Vietnamese e-invoice into canonical model',
      () async {
        final bytes = await File(
          'test/fixtures/xml/vn_einvoice.xml',
        ).readAsBytes();

        final result = await extractor.extract(
          ExtractionInput(
            bytes: bytes,
            fileName: 'invoice.xml',
            sourceType: InvoiceSourceType.xml,
          ),
        );

        expect(result.adapterName, 'vietnam-einvoice-xml');
        expect(result.invoice.sellerName, 'CÔNG TY TNHH DEMO');
        expect(result.invoice.sellerTaxCode, '0312345678');
        expect(result.invoice.invoiceNumber, '00001234');
        expect(result.invoice.invoiceSymbol, 'C24TAA');
        expect(result.invoice.issuedAt, DateTime(2026, 8, 20));
        expect(result.invoice.subtotalMinor, 100000);
        expect(result.invoice.taxMinor, 10000);
        expect(result.invoice.totalMinor, 110000);
        expect(result.invoice.lines, hasLength(1));
        expect(result.invoice.lines.single.description, 'Dịch vụ phần mềm');
        expect(result.invoice.status, InvoiceStatus.confirmed);
        expect(result.invoice.sourceHash, hasLength(64));
        expect(result.warnings, isEmpty);
      },
    );

    test('rejects malformed XML with a user-facing exception', () async {
      final input = ExtractionInput(
        bytes: File(
          'test/fixtures/xml/vn_einvoice.xml',
        ).readAsBytesSync().sublist(0, 40),
        fileName: 'broken.xml',
        sourceType: InvoiceSourceType.xml,
      );

      expect(
        () => extractor.extract(input),
        throwsA(isA<ExtractionException>()),
      );
    });

    test('rejects DTD and entity declarations', () async {
      final input = ExtractionInput(
        bytes: Uint8List.fromList(
          '<!DOCTYPE invoice [<!ENTITY x "unsafe">]><invoice>&x;</invoice>'
              .codeUnits,
        ),
        fileName: 'unsafe.xml',
        sourceType: InvoiceSourceType.xml,
      );

      expect(
        () => extractor.extract(input),
        throwsA(isA<ExtractionException>()),
      );
    });
  });
}
