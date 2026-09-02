import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/ingestion/domain/async_extraction_job.dart';

void main() {
  test(
    'disabled async gateway fails explicitly instead of silently falling back',
    () {
      const gateway = DisabledAsyncExtractionGateway();
      expect(gateway.isConfigured, isFalse);
      expect(
        () => gateway.submit(
          bytes: Uint8List(0),
          ocrText: 'text',
          sourceName: 'invoice.jpg',
        ),
        throwsStateError,
      );
    },
  );

  test('terminal job states are explicit', () {
    final job = AsyncExtractionJob(
      id: 'job-1',
      state: AsyncExtractionJobState.succeeded,
      createdAt: DateTime(2026, 8, 30),
    );
    expect(job.isTerminal, isTrue);
  });
}
