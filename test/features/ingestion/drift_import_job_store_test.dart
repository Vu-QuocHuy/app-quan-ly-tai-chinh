import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/database/app_database.dart';
import 'package:hoadon_insight/core/errors/app_exception.dart';
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

  test('keeps extracted source awaiting user review', () async {
    const pending = PendingImport(
      id: 'job-review',
      fileName: 'review.xml',
      diskName: 'review.bin',
      kind: PendingImportKind.document,
    );
    await store.ensureQueued(pending);
    expect(await store.markRunning(pending.id), isTrue);
    await store.markAwaitingReview(pending.id);

    final job = await store.find(pending.id);
    expect(job?.state, ImportJobState.awaitingReview);
    expect(job?.canRetry, isTrue);
    expect(await store.isRunnable(pending.id), isFalse);
    expect(job?.lastError, isNull);
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

  test('stores a redacted, bounded error message', () async {
    const pending = PendingImport(
      id: 'job-redacted',
      fileName: 'invoice.xml',
      diskName: 'invoice.bin',
      kind: PendingImportKind.document,
    );
    await store.ensureQueued(pending);
    await store.markRunning(pending.id);
    await store.markFailed(
      pending.id,
      const NetworkException(
        'Authorization: Bearer very-secret-token https://example.com?a=secret test@example.com',
      ),
    );

    final error = (await store.find(pending.id))?.lastError;
    expect(error, isNotNull);
    expect(error, isNot(contains('very-secret-token')));
    expect(error, isNot(contains('example.com')));
    expect(error, isNot(contains('test@example.com')));
    expect(error!.length, lessThanOrEqualTo(240));
  });

  test('claims a queued job atomically when called concurrently', () async {
    const pending = PendingImport(
      id: 'job-atomic',
      fileName: 'invoice.xml',
      diskName: 'invoice.bin',
      kind: PendingImportKind.document,
    );
    await store.ensureQueued(pending);

    final results = await Future.wait([
      store.markRunning(pending.id),
      store.markRunning(pending.id),
    ]);

    expect(results.where((result) => result), hasLength(1));
    expect((await store.find(pending.id))?.attemptCount, 1);
    expect((await store.find(pending.id))?.state, ImportJobState.running);
  });

  test('does not let retry overwrite a running job', () async {
    const pending = PendingImport(
      id: 'job-running-retry',
      fileName: 'invoice.xml',
      diskName: 'invoice.bin',
      kind: PendingImportKind.document,
    );
    await store.ensureQueued(pending);
    expect(await store.markRunning(pending.id), isTrue);

    await store.retryNow(pending.id);

    final job = await store.find(pending.id);
    expect(job?.state, ImportJobState.running);
    expect(job?.attemptCount, 1);
  });

  test('ignores a stale failure after a job leaves running state', () async {
    const pending = PendingImport(
      id: 'job-stale-failure',
      fileName: 'invoice.xml',
      diskName: 'invoice.bin',
      kind: PendingImportKind.document,
    );
    await store.ensureQueued(pending);
    expect(await store.markRunning(pending.id), isTrue);
    await (database.update(database.importJobs)
          ..where((row) => row.id.equals(pending.id)))
        .write(const ImportJobsCompanion(state: Value('queued')));

    await store.markFailed(pending.id, StateError('stale'));

    expect((await store.find(pending.id))?.state, ImportJobState.queued);
  });

  test('requeues a running job left behind by a process restart', () async {
    const pending = PendingImport(
      id: 'job-process-restart',
      fileName: 'invoice.xml',
      diskName: 'invoice.bin',
      kind: PendingImportKind.document,
    );
    await store.ensureQueued(pending);
    expect(await store.markRunning(pending.id), isTrue);
    await (database.update(
      database.importJobs,
    )..where((row) => row.id.equals(pending.id))).write(
      ImportJobsCompanion(
        updatedAt: Value(DateTime.now().subtract(const Duration(minutes: 11))),
      ),
    );

    await store.ensureQueued(pending);

    final job = await store.find(pending.id);
    expect(job?.state, ImportJobState.retryScheduled);
    expect(job?.nextRetryAt, isNotNull);
  });

  test('creates an import job once when queued concurrently', () async {
    const pending = PendingImport(
      id: 'job-insert-atomic',
      fileName: 'invoice.xml',
      diskName: 'invoice.bin',
      kind: PendingImportKind.document,
    );

    await Future.wait([
      store.ensureQueued(pending),
      store.ensureQueued(pending),
    ]);

    final jobs = await database.select(database.importJobs).get();
    expect(jobs, hasLength(1));
    expect(jobs.single.id, pending.id);
    expect(jobs.single.attemptCount, 0);
  });
}
