import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/errors/app_exception.dart';
import 'package:hoadon_insight/features/ingestion/data/ai_extraction_job_client.dart';
import 'package:hoadon_insight/features/ingestion/domain/extraction.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  test('parses a terminal extraction job without exposing input data', () {
    final job = AiExtractionJob.fromJson({
      'id': '11111111-1111-4111-8111-111111111111',
      'requestId': 'request-1',
      'status': 'succeeded',
      'inputKind': 'image',
      'inputMimeType': 'image/jpeg',
      'attemptCount': 1,
      'maxAttempts': 3,
      'availableAt': '2026-09-17T00:00:00Z',
      'createdAt': '2026-09-17T00:00:00Z',
      'updatedAt': '2026-09-17T00:00:00Z',
      'result': {
        'invoice': {'totalMinor': 120000},
      },
      'errorCode': null,
    });

    expect(job.isTerminal, isTrue);
    expect(job.result?['invoice'], isA<Map>());
    expect(job.inputKind, 'image');
  });

  test('rejects malformed extraction job data', () {
    expect(
      () => AiExtractionJob.fromJson({'id': 'job-1', 'status': 'queued'}),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects an unknown status or invalid optional field type', () {
    expect(
      () => AiExtractionJob.fromJson({
        'id': 'not-a-uuid',
        'requestId': 'request-1',
        'status': 'running',
        'attemptCount': '1',
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => AiExtractionJob.fromJson({
        'id': '11111111-1111-4111-8111-111111111111',
        'requestId': 'request-1',
        'status': 'queued',
        'inputMimeType': 42,
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('requires a configured backend before submitting a job', () async {
    final client = AiExtractionJobClient();
    final input = ExtractionInput(
      bytes: Uint8List.fromList([1, 2, 3]),
      fileName: 'receipt.jpg',
      sourceType: InvoiceSourceType.imageOcr,
    );

    await expectLater(client.submit(input), throwsA(isA<NetworkException>()));
  });

  test('rejects an invalid job id before calling the backend', () async {
    final client = AiExtractionJobClient();

    await expectLater(
      client.status('not-a-uuid'),
      throwsA(isA<ArgumentError>()),
    );
  });
}
