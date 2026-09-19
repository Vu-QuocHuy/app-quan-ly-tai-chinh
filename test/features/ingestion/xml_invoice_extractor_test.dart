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

    test('parses generic invoice information schema variant', () async {
      final bytes = await File(
        'test/fixtures/xml/generic_einvoice.xml',
      ).readAsBytes();

      final result = await extractor.extract(
        ExtractionInput(
          bytes: bytes,
          fileName: 'generic.xml',
          sourceType: InvoiceSourceType.xml,
        ),
      );

      expect(result.invoice.sellerName, 'CÔNG TY GENERIC');
      expect(result.invoice.sellerTaxCode, '0101234567');
      expect(result.invoice.invoiceNumber, 'GEN-0001');
      expect(result.invoice.invoiceSymbol, 'G26AA');
      expect(result.invoice.issuedAt, DateTime(2026, 9, 1));
      expect(result.invoice.totalMinor, 54000);
      expect(result.invoice.lines.single.description, 'Hàng tiêu dùng');
      expect(result.invoice.lines.single.quantity, 2);
      expect(result.invoice.lines.single.taxRate, 8);
    });

    test('parses invoice information schema variant', () async {
      final bytes = await File(
        'test/fixtures/xml/invoice_information.xml',
      ).readAsBytes();

      final result = await extractor.extract(
        ExtractionInput(
          bytes: bytes,
          fileName: 'invoice-information.xml',
          sourceType: InvoiceSourceType.xml,
        ),
      );

      expect(result.invoice.sellerName, 'CỬA HÀNG INFORMATION');
      expect(result.invoice.sellerTaxCode, '0207654321');
      expect(result.invoice.invoiceNumber, 'INFO-0002');
      expect(result.invoice.invoiceSymbol, 'I26BB');
      expect(result.invoice.issuedAt, DateTime(2026, 9, 2));
      expect(result.invoice.totalMinor, 33000);
      expect(result.invoice.lines.single.description, 'Đồ uống');
      expect(result.invoice.lines.single.unitPriceMinor, 30000);
    });

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
