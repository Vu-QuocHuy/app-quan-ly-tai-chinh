import 'dart:typed_data';

import '../../invoices/domain/invoice_models.dart';

enum AsyncExtractionJobState { queued, running, succeeded, failed, cancelled }

class AsyncExtractionJob {
  const AsyncExtractionJob({
    required this.id,
    required this.state,
    required this.createdAt,
    this.updatedAt,
    this.result,
    this.errorCode,
    this.errorMessage,
  });

  final String id;
  final AsyncExtractionJobState state;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final InvoiceEntity? result;
  final String? errorCode;
  final String? errorMessage;

  bool get isTerminal =>
      state == AsyncExtractionJobState.succeeded ||
      state == AsyncExtractionJobState.failed ||
      state == AsyncExtractionJobState.cancelled;
}

abstract interface class AsyncExtractionGateway {
  bool get isConfigured;

  Future<AsyncExtractionJob> submit({
    required Uint8List bytes,
    required String ocrText,
    required String sourceName,
  });

  Future<AsyncExtractionJob> status(String jobId);

  Future<void> cancel(String jobId);
}

class DisabledAsyncExtractionGateway implements AsyncExtractionGateway {
  const DisabledAsyncExtractionGateway();

  @override
  bool get isConfigured => false;

  @override
  Future<AsyncExtractionJob> submit({
    required Uint8List bytes,
    required String ocrText,
    required String sourceName,
  }) {
    throw StateError('Async extraction chưa được cấu hình.');
  }

  @override
  Future<AsyncExtractionJob> status(String jobId) {
    throw StateError('Async extraction chưa được cấu hình.');
  }

  @override
  Future<void> cancel(String jobId) {
    throw StateError('Async extraction chưa được cấu hình.');
  }
}
