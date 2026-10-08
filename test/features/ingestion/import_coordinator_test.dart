import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/database/app_database.dart';
import 'package:hoadon_insight/core/errors/app_exception.dart';
import 'package:hoadon_insight/features/ingestion/application/import_coordinator.dart';
import 'package:hoadon_insight/features/ingestion/data/ai_extraction_client.dart';
import 'package:hoadon_insight/features/ingestion/data/heuristic_text_extractor.dart';
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

  test('sends the original image to the configured VLM extractor', () async {
    final aiExtractor = _FakeAiExtractor();
    final coordinator = _buildCoordinator(repository, aiExtractor: aiExtractor);
    final bytes = Uint8List.fromList([1, 2, 3]);

    final outcome = await coordinator.importImage(
      bytes: bytes,
      fileName: 'receipt.jpg',
      imagePath: '/tmp/receipt.jpg',
    );

    expect(aiExtractor.imageExtractionCalls, 1);
    expect(aiExtractor.lastImageBytes, bytes);
    expect(outcome.result.invoice.sourceType, InvoiceSourceType.imageOcr);
    expect(outcome.result.adapterName, 'fake-vlm-image');
  });

  test('requires the VLM service for image extraction', () async {
    final coordinator = _buildCoordinator(repository);

    await expectLater(
      coordinator.importImage(
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'receipt.jpg',
        imagePath: '/tmp/receipt.jpg',
      ),
      throwsA(isA<NetworkException>()),
    );
  });

  test(
    'keeps the category returned by extraction when no merchant rule exists',
    () async {
      final coordinator = _buildCoordinator(
        repository,
        aiExtractor: _FakeAiExtractor(),
      );

      final outcome = await coordinator.importImage(
        bytes: Uint8List.fromList([7, 8, 9]),
        fileName: 'receipt.jpg',
        imagePath: '/tmp/receipt.jpg',
      );

      expect(outcome.result.invoice.categoryId, 'food');
    },
  );

  test('uses a shared item category when invoice category is other', () async {
    final aiExtractor = _FakeAiExtractor(
      extractedCategoryId: 'other',
      lineCategoryIds: const ['food'],
      merchantCategoryId: 'other',
    );
    final coordinator = _buildCoordinator(repository, aiExtractor: aiExtractor);

    final outcome = await coordinator.importImage(
      bytes: Uint8List.fromList([7, 8, 9]),
      fileName: 'receipt.jpg',
      imagePath: '/tmp/receipt.jpg',
    );

    expect(outcome.result.invoice.categoryId, 'food');
    expect(outcome.result.invoice.lines.single.categoryId, 'food');
  });
}

ImportCoordinator _buildCoordinator(
  DriftInvoiceRepository repository, {
  AiExtractionClient? aiExtractor,
}) {
  return ImportCoordinator(
    repository: repository,
    xmlExtractor: XmlInvoiceExtractor(),
    pdfTextService: const PdfTextService(),
    aiExtractor: aiExtractor ?? AiExtractionClient(enabled: false),
    heuristicExtractor: HeuristicTextExtractor(),
  );
}

class _FakeAiExtractor extends AiExtractionClient {
  _FakeAiExtractor({
    this.extractedCategoryId = 'food',
    this.lineCategoryIds = const [],
    this.merchantCategoryId,
  }) : super(enabled: false);

  final String extractedCategoryId;
  final List<String> lineCategoryIds;
  final String? merchantCategoryId;

  int imageExtractionCalls = 0;
  Uint8List? lastImageBytes;

  @override
  bool get isConfigured => true;

  @override
  bool canHandle(ExtractionInput input) => true;

  @override
  Future<ExtractionResult> extract(ExtractionInput input) async {
    return _result(input, adapterName: 'fake-ai-text');
  }

  @override
  Future<ExtractionResult> extractImage(ExtractionInput input) async {
    imageExtractionCalls++;
    lastImageBytes = Uint8List.fromList(input.bytes);
    return _result(input, adapterName: 'fake-vlm-image');
  }

  ExtractionResult _result(
    ExtractionInput input, {
    required String adapterName,
  }) {
    final now = DateTime(2026, 9, 17);
    return ExtractionResult(
      adapterName: adapterName,
      adapterVersion: 'test',
      invoice: InvoiceEntity(
        id: 'ai-invoice',
        sellerName: 'Siêu thị Demo',
        currencyCode: 'VND',
        subtotalMinor: 125000,
        taxMinor: 0,
        totalMinor: 125000,
        sourceType: input.sourceType,
        categoryId: extractedCategoryId,
        status: InvoiceStatus.needsReview,
        createdAt: now,
        updatedAt: now,
        lines: [
          for (var index = 0; index < lineCategoryIds.length; index++)
            InvoiceLineEntity(
              id: 'line-$index',
              description: 'Mặt hàng $index',
              totalMinor: 1000,
              categoryId: lineCategoryIds[index],
            ),
        ],
      ),
    );
  }

  @override
  Future<String?> classifyMerchant(String merchant) async => merchantCategoryId;
}
