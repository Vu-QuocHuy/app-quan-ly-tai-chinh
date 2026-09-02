import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/ingestion/application/import_coordinator.dart';
import 'package:hoadon_insight/features/ingestion/application/import_queue.dart';
import 'package:hoadon_insight/features/ingestion/domain/extraction.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  test('processes jobs in order and continues after a failure', () async {
    final events = <String>[];
    final progress = <ImportQueueProgress>[];
    final invoice = _invoice();
    final outcome = ImportOutcome(
      result: ExtractionResult(
        invoice: invoice,
        adapterName: 'test',
        adapterVersion: '1.0.0',
      ),
    );
    final queue = ImportQueueController();

    final summary = await queue.run(
      jobs: [
        ImportQueueJob(
          fileName: 'first.xml',
          operation: () async {
            events.add('first');
            return outcome;
          },
        ),
        ImportQueueJob(
          fileName: 'broken.xml',
          operation: () async {
            events.add('broken');
            throw StateError('bad xml');
          },
        ),
        ImportQueueJob(
          fileName: 'last.xml',
          operation: () async {
            events.add('last');
            return outcome;
          },
        ),
      ],
      onProgress: progress.add,
      onOutcome: (job, _) async => events.add('saved:${job.fileName}'),
    );

    expect(events, [
      'first',
      'saved:first.xml',
      'broken',
      'last',
      'saved:last.xml',
    ]);
    expect(summary.total, 3);
    expect(summary.succeeded, 2);
    expect(summary.failed, 1);
    expect(summary.failures.single.job.fileName, 'broken.xml');
    expect(progress.first.currentFileName, 'first.xml');
    expect(progress.last.isRunning, isFalse);
    expect(progress.last.completed, 2);
    expect(queue.isRunning, isFalse);
  });

  test('can cancel before the next queued job starts', () async {
    final events = <String>[];
    final queue = ImportQueueController();
    final outcome = ImportOutcome(
      result: ExtractionResult(
        invoice: _invoice(),
        adapterName: 'test',
        adapterVersion: '1.0.0',
      ),
    );

    final summary = await queue.run(
      jobs: [
        ImportQueueJob(
          fileName: 'first.xml',
          operation: () async {
            events.add('first');
            queue.cancel();
            return outcome;
          },
        ),
        ImportQueueJob(
          fileName: 'second.xml',
          operation: () async {
            events.add('second');
            return outcome;
          },
        ),
      ],
      onProgress: (_) {},
      onOutcome: (_, _) async {},
    );

    expect(events, ['first']);
    expect(summary.cancelled, isTrue);
    expect(summary.succeeded, 1);
  });
}

InvoiceEntity _invoice() {
  final now = DateTime(2026, 8, 30);
  return InvoiceEntity(
    id: 'queue-invoice',
    sellerName: 'Queue Demo',
    currencyCode: 'VND',
    subtotalMinor: 100,
    taxMinor: 0,
    totalMinor: 100,
    sourceType: InvoiceSourceType.xml,
    status: InvoiceStatus.confirmed,
    createdAt: now,
    updatedAt: now,
  );
}
