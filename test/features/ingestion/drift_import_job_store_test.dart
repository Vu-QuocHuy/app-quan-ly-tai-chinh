import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/database/app_database.dart';
import 'package:hoadon_insight/features/ingestion/data/drift_import_job_store.dart';
import 'package:hoadon_insight/features/ingestion/data/pending_import_store.dart';
import 'package:hoadon_insight/features/ingestion/domain/import_job.dart';

void main() {
  late AppDatabase database;
  late DriftImportJobStore store;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    store = DriftImportJobStore(database);
  });

  tearDown(() => database.close());

  test('tracks attempts, schedules retry and supports manual retry', () async {
    const pending = PendingImport(
      id: 'job-1',
      fileName: 'invoice.xml',
      diskName: 'invoice.bin',
      kind: PendingImportKind.document,
    );
    await store.ensureQueued(pending);
    expect(await store.markRunning(pending.id), isTrue);
    await store.markFailed(pending.id, StateError('network'));

    final scheduled = await store.find(pending.id);
    expect(scheduled?.state, ImportJobState.retryScheduled);
    expect(scheduled?.attemptCount, 1);
    expect(scheduled?.nextRetryAt, isNotNull);
    expect(await store.isRunnable(pending.id), isFalse);

    await store.retryNow(pending.id);
    expect((await store.find(pending.id))?.state, ImportJobState.queued);
    expect(await store.markRunning(pending.id), isTrue);
    await store.markSucceeded(pending.id);
    expect((await store.find(pending.id))?.state, ImportJobState.succeeded);
  });

  test('replays terminal jobs and clears only successful history', () async {
    const failed = PendingImport(
      id: 'job-failed',
      fileName: 'failed.xml',
      diskName: 'failed.bin',
      kind: PendingImportKind.document,
    );
    const succeeded = PendingImport(
      id: 'job-succeeded',
      fileName: 'done.xml',
      diskName: 'done.bin',
      kind: PendingImportKind.document,
    );
    await store.ensureQueued(failed);
    await store.ensureQueued(succeeded);

    await (database.update(database.importJobs)
          ..where((row) => row.id.equals(failed.id)))
        .write(const ImportJobsCompanion(attemptCount: Value(2)));
    expect(await store.markRunning(failed.id), isTrue);
    await store.markFailed(failed.id, StateError('terminal'));
    expect((await store.find(failed.id))?.state, ImportJobState.failed);

    expect(await store.markRunning(succeeded.id), isTrue);
    await store.markSucceeded(succeeded.id);
    expect(await store.clearSucceeded(), 1);
    expect(await store.find(succeeded.id), isNull);

    expect(await store.retryAllFailed(), 1);
    final replayed = await store.find(failed.id);
    expect(replayed?.state, ImportJobState.queued);
    expect(replayed?.attemptCount, 0);
    expect(replayed?.lastError, isNull);
  });
}
