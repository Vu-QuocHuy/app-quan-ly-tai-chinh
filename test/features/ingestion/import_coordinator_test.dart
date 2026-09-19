import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/database/app_database.dart';
import 'package:hoadon_insight/features/ingestion/application/import_coordinator.dart';
import 'package:hoadon_insight/features/ingestion/data/ai_extraction_client.dart';
import 'package:hoadon_insight/features/ingestion/data/heuristic_text_extractor.dart';
import 'package:hoadon_insight/features/ingestion/data/ocr_service.dart';
import 'package:hoadon_insight/features/ingestion/data/pdf_text_service.dart';
import 'package:hoadon_insight/features/ingestion/data/xml_invoice_extractor.dart';
import 'package:hoadon_insight/features/ingestion/domain/extraction.dart';
import 'package:hoadon_insight/features/invoices/data/drift_invoice_repository.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  late AppDatabase database;
  late DriftInvoiceRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftInvoiceRepository(database);
  });

  tearDown(() => database.close());

  test('runs XML extraction through repository completion', () async {
    final coordinator = _buildCoordinator(repository);
    final bytes = await File('test/fixtures/xml/vn_einvoice.xml').readAsBytes();
    await repository.saveMerchantRule('CÔNG TY TNHH DEMO', 'education');

    final outcome = await coordinator.importFile(
      bytes: bytes,
      fileName: 'invoice.xml',
    );

    expect(outcome.result.invoice.sellerName, 'CÔNG TY TNHH DEMO');
    expect(outcome.result.invoice.totalMinor, 110000);
    expect(outcome.result.invoice.lines, hasLength(1));
    expect(outcome.result.invoice.categoryId, 'education');
    expect(outcome.exactDuplicate, isNull);
    expect(outcome.likelyDuplicate, isNull);
  });

  test('runs offline OCR extraction when AI is unavailable', () async {
    final coordinator = _buildCoordinator(
      repository,
      ocrService: _FakeOcrService(
        'Siêu thị Demo\nNgày 17/09/2026\nTổng thanh toán: 125.000',
      ),
    );

    final outcome = await coordinator.importImage(
      bytes: Uint8List.fromList([1, 2, 3]),
      fileName: 'receipt.jpg',
      imagePath: '/tmp/receipt.jpg',
    );

    expect(outcome.result.invoice.sourceType, InvoiceSourceType.imageOcr);
    expect(outcome.result.invoice.sellerName, 'Siêu thị Demo');
    expect(outcome.result.invoice.issuedAt, DateTime(2026, 9, 17));
    expect(outcome.result.invoice.totalMinor, 125000);
    expect(outcome.result.adapterName, 'offline-text-fallback');
    expect(outcome.result.warnings, isNotEmpty);
  });

  test(
    'keeps the category returned by extraction when no merchant rule exists',
    () async {
      final coordinator = _buildCoordinator(
        repository,
        aiExtractor: _FakeAiExtractor(),
        ocrService: _FakeOcrService(
          'Siêu thị Demo\nNgày 17/09/2026\nTổng thanh toán: 125.000',
        ),
      );

      final outcome = await coordinator.importImage(
        bytes: Uint8List.fromList([7, 8, 9]),
        fileName: 'receipt.jpg',
        imagePath: '/tmp/receipt.jpg',
      );

      expect(outcome.result.invoice.categoryId, 'food');
    },
  );
}

ImportCoordinator _buildCoordinator(
  DriftInvoiceRepository repository, {
  OcrService? ocrService,
  AiExtractionClient? aiExtractor,
}) {
  return ImportCoordinator(
    repository: repository,
    xmlExtractor: XmlInvoiceExtractor(),
    ocrService: ocrService ?? _FakeOcrService(''),
    pdfTextService: const PdfTextService(),
    aiExtractor: aiExtractor ?? AiExtractionClient(enabled: false),
    heuristicExtractor: HeuristicTextExtractor(),
  );
}

class _FakeOcrService extends OcrService {
  _FakeOcrService(this.text);

  final String text;

  @override
  Future<String> recognizeText(String imagePath) async => text;
}

class _FakeAiExtractor extends AiExtractionClient {
  _FakeAiExtractor() : super(enabled: false);

  @override
  bool get isConfigured => true;

  @override
  bool canHandle(ExtractionInput input) => true;

  @override
  Future<ExtractionResult> extract(ExtractionInput input) async {
    final now = DateTime(2026, 9, 17);
    return ExtractionResult(
      adapterName: 'fake-ai',
      adapterVersion: 'test',
      invoice: InvoiceEntity(
        id: 'ai-invoice',
        sellerName: 'Siêu thị Demo',
        currencyCode: 'VND',
        subtotalMinor: 125000,
        taxMinor: 0,
        totalMinor: 125000,
        sourceType: input.sourceType,
        categoryId: 'food',
        status: InvoiceStatus.needsReview,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  @override
  Future<String?> classifyMerchant(String merchant) async => null;
}
