import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../invoices/domain/invoice_repository.dart';
import '../data/ai_extraction_client.dart';
import '../data/heuristic_text_extractor.dart';
import '../data/pdf_text_service.dart';
import '../data/xml_invoice_extractor.dart';
import '../domain/duplicate_detector.dart';
import '../domain/extraction.dart';
import '../domain/invoice_extractor_registry.dart';
import '../domain/line_category_classifier.dart';
import '../domain/ocr_text_normalizer.dart';

class ImportOutcome {
  const ImportOutcome({
    required this.result,
    this.exactDuplicate,
    this.likelyDuplicate,
    this.sourceImageBytes,
    this.sourceImageFileName,
  });

  final ExtractionResult result;
  final InvoiceEntity? exactDuplicate;
  final DuplicateMatch? likelyDuplicate;
  final Uint8List? sourceImageBytes;
  final String? sourceImageFileName;
}

class ImportCoordinator {
  ImportCoordinator({
    required InvoiceRepository repository,
    required XmlInvoiceExtractor xmlExtractor,
    required PdfTextService pdfTextService,
    required AiExtractionClient aiExtractor,
    required HeuristicTextExtractor heuristicExtractor,
    DuplicateDetector duplicateDetector = const DuplicateDetector(),
    LineCategoryClassifier lineCategoryClassifier =
        const LineCategoryClassifier(),
    Uuid uuid = const Uuid(),
    Iterable<InvoiceExtractor> additionalExtractors = const [],
  }) : _repository = repository,
       _pdfTextService = pdfTextService,
       _aiExtractor = aiExtractor,
       _heuristicExtractor = heuristicExtractor,
       _duplicateDetector = duplicateDetector,
       _lineCategoryClassifier = lineCategoryClassifier,
       _uuid = uuid,
       _extractorRegistry = InvoiceExtractorRegistry([
         xmlExtractor,
         ...additionalExtractors,
       ]);

  final InvoiceRepository _repository;
  final PdfTextService _pdfTextService;
  final AiExtractionClient _aiExtractor;
  final HeuristicTextExtractor _heuristicExtractor;
  final DuplicateDetector _duplicateDetector;
  final LineCategoryClassifier _lineCategoryClassifier;
  final Uuid _uuid;
  final InvoiceExtractorRegistry _extractorRegistry;

  Future<ImportOutcome> importFile({
    required Uint8List bytes,
    required String fileName,
    String? localPath,
  }) async {
    _validateSize(bytes);
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.pdf')) {
      PdfTextService.validateSignature(bytes);
      final text = await _pdfTextService.extractText(bytes, fileName: fileName);
      final input = ExtractionInput(
        bytes: bytes,
        fileName: fileName,
        sourceType: InvoiceSourceType.pdfText,
        localPath: localPath,
        ocrText: OcrTextNormalizer.normalize(text),
      );
      return _complete(await _extractText(input));
    }
    final input = ExtractionInput(
      bytes: bytes,
      fileName: fileName,
      sourceType: InvoiceSourceType.xml,
      localPath: localPath,
    );
    return _complete(await _extractorRegistry.extract(input));
  }

  Future<ImportOutcome> importImage({
    required Uint8List bytes,
    required String fileName,
    required String imagePath,
  }) async {
    _validateSize(bytes);
    final input = ExtractionInput(
      bytes: bytes,
      fileName: fileName,
      sourceType: InvoiceSourceType.imageOcr,
      localPath: imagePath,
    );
    if (!_aiExtractor.isConfigured) {
      throw const NetworkException(
        'Cần kết nối dịch vụ AI để phân tích ảnh hóa đơn. Bạn có thể nhập thủ công.',
      );
    }
    final outcome = await _complete(await _aiExtractor.extractImage(input));
    return ImportOutcome(
      result: outcome.result,
      exactDuplicate: outcome.exactDuplicate,
      likelyDuplicate: outcome.likelyDuplicate,
      sourceImageBytes: bytes,
      sourceImageFileName: fileName,
    );
  }

  InvoiceEntity createManualDraft() {
    final now = DateTime.now();
    return InvoiceEntity(
      id: _uuid.v4(),
      sellerName: '',
      issuedAt: now,
      currencyCode: AppConstants.defaultCurrency,
      subtotalMinor: 0,
      taxMinor: 0,
      totalMinor: 0,
      sourceType: InvoiceSourceType.manual,
      status: InvoiceStatus.needsReview,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<ImportOutcome> _complete(ExtractionResult result) async {
    final categories = await _repository.watchCategories().first;
    final classifiedLines = _lineCategoryClassifier.classify(
      result.invoice.lines,
      categories,
    );
    final merchantRuleCategoryId = await _repository.categoryForMerchant(
      result.invoice.sellerName,
    );
    var categoryId = merchantRuleCategoryId ?? result.invoice.categoryId;
    if (merchantRuleCategoryId == null &&
        (categoryId == null || categoryId == 'other') &&
        classifiedLines.isNotEmpty) {
      final lineCategoryIds = classifiedLines
          .map((line) => line.categoryId)
          .toSet();
      if (lineCategoryIds.length == 1 &&
          !lineCategoryIds.contains(null) &&
          !lineCategoryIds.contains('other')) {
        categoryId = lineCategoryIds.single;
      }
    }
    if (merchantRuleCategoryId == null &&
        (categoryId == null || categoryId == 'other') &&
        _aiExtractor.isConfigured) {
      try {
        final merchantCategoryId = await _aiExtractor.classifyMerchant(
          result.invoice.sellerName,
        );
        if (merchantCategoryId != null && merchantCategoryId != 'other') {
          categoryId = merchantCategoryId;
        }
      } on NetworkException {
        // Classification is an enrichment step; import must remain offline-first.
      }
    }
    final availableCategoryIds = categories
        .map((category) => category.id)
        .toSet();
    if (categoryId != null && !availableCategoryIds.contains(categoryId)) {
      categoryId = availableCategoryIds.contains('other') ? 'other' : null;
    }
    final resolvedResult = ExtractionResult(
      invoice: result.invoice.copyWith(
        categoryId: categoryId,
        lines: classifiedLines,
      ),
      adapterName: result.adapterName,
      adapterVersion: result.adapterVersion,
      warnings: result.warnings,
    );
    final hash = resolvedResult.invoice.sourceHash;
    final exact = hash == null
        ? null
        : await _repository.findBySourceHash(hash);
    final existing = await _repository.findDuplicateCandidates(
      resolvedResult.invoice,
    );
    final fuzzy = exact == null
        ? _duplicateDetector.findLikelyDuplicate(
            resolvedResult.invoice,
            existing,
          )
        : null;
    return ImportOutcome(
      result: resolvedResult,
      exactDuplicate: exact,
      likelyDuplicate: fuzzy,
    );
  }

  Future<ExtractionResult> _extractText(ExtractionInput input) async {
    if (!_aiExtractor.canHandle(input)) {
      return _heuristicExtractor.extract(input);
    }
    try {
      return await _aiExtractor.extract(input);
    } on NetworkException catch (error) {
      final fallback = await _heuristicExtractor.extract(input);
      return ExtractionResult(
        invoice: fallback.invoice,
        adapterName: fallback.adapterName,
        adapterVersion: fallback.adapterVersion,
        warnings: [
          'Dịch vụ AI tạm thời không khả dụng: ${error.message}',
          ...fallback.warnings,
        ],
      );
    }
  }

  void _validateSize(Uint8List bytes) {
    if (bytes.length > AppConstants.maxImportBytes) {
      throw const ValidationException('File vượt quá giới hạn 15 MB.');
    }
    if (bytes.isEmpty) {
      throw const ValidationException('File rỗng hoặc không thể đọc.');
    }
  }
}
