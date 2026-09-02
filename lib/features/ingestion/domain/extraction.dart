import 'dart:typed_data';

import '../../invoices/domain/invoice_models.dart';

class ExtractionInput {
  const ExtractionInput({
    required this.bytes,
    required this.fileName,
    required this.sourceType,
    this.localPath,
    this.ocrText,
  });

  final Uint8List bytes;
  final String fileName;
  final InvoiceSourceType sourceType;
  final String? localPath;
  final String? ocrText;
}

class ExtractionResult {
  const ExtractionResult({
    required this.invoice,
    required this.adapterName,
    required this.adapterVersion,
    this.warnings = const [],
  });

  final InvoiceEntity invoice;
  final String adapterName;
  final String adapterVersion;
  final List<String> warnings;
}

abstract interface class InvoiceExtractor {
  String get adapterName;
  String get adapterVersion;
  bool canHandle(ExtractionInput input);
  Future<ExtractionResult> extract(ExtractionInput input);
}
