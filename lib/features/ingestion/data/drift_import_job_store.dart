import 'dart:math';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../domain/import_job.dart';
import 'pending_import_store.dart';

class DriftImportJobStore {
  const DriftImportJobStore(this._db);

  final AppDatabase _db;

  Stream<List<ImportJobEntity>> watchRecent({int limit = 100}) {
    final query = _db.select(_db.importJobs)
      ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
      ..limit(limit.clamp(1, 500));
    return query.watch().map(
      (rows) => rows.map(_fromRow).toList(growable: false),
    );
  }

  Future<ImportJobEntity?> find(String id) async {
    final row = await (_db.select(
      _db.importJobs,
    )..where((item) => item.id.equals(id))).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  Future<void> ensureQueued(PendingImport pending) async {
    final now = DateTime.now();
    await _db.customInsert(
      '''
      INSERT INTO import_jobs (id, file_name, kind, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(id) DO NOTHING
      ''',
      variables: [
        Variable(pending.id),
        Variable(pending.fileName),
        Variable(pending.kind.name),
        Variable(now),
        Variable(now),
      ],
      updates: {_db.importJobs},
    );
    await _db.customUpdate(
      '''
      UPDATE import_jobs
      SET state = ?,
          next_retry_at = ?,
          updated_at = ?,
          last_error = ?
      WHERE id = ?
        AND state = ?
        AND updated_at < ?
      ''',
      variables: [
        Variable(ImportJobState.retryScheduled.name),
        Variable(now),
        Variable(now),
        Variable('Tác vụ bị gián đoạn khi ứng dụng đóng.'),
        Variable(pending.id),
        Variable(ImportJobState.running.name),
        Variable(now.subtract(const Duration(minutes: 10))),
      ],
      updates: {_db.importJobs},
    );
  }

  Future<bool> isRunnable(String id, {DateTime? at}) async {
    final job = await find(id);
    if (job == null) return true;
    final now = at ?? DateTime.now();
    return switch (job.state) {
      ImportJobState.queued => true,
      ImportJobState.retryScheduled =>
        job.nextRetryAt == null || !job.nextRetryAt!.isAfter(now),
      ImportJobState.running ||
      ImportJobState.awaitingReview ||
      ImportJobState.succeeded ||
      ImportJobState.failed => false,
    };
  }

  Future<bool> markRunning(String id) async {
    final now = DateTime.now();
    final changed = await _db.customUpdate(
      '''
      UPDATE import_jobs
      SET state = ?,
          attempt_count = attempt_count + 1,
          last_error = NULL,
          next_retry_at = NULL,
          updated_at = ?,
          completed_at = NULL
      WHERE id = ?
        AND (
          state = ?
          OR (
            state = ?
            AND (next_retry_at IS NULL OR next_retry_at <= ?)
          )
        )
      ''',
      variables: [
        Variable(ImportJobState.running.name),
        Variable(now),
        Variable(id),
        Variable(ImportJobState.queued.name),
        Variable(ImportJobState.retryScheduled.name),
        Variable(now),
      ],
      updates: {_db.importJobs},
    );
    return changed == 1;
  }

  Future<void> markSucceeded(String id) async {
    final now = DateTime.now();
    await (_db.update(_db.importJobs)..where(
          (row) =>
              row.id.equals(id) & row.state.equals(ImportJobState.running.name),
        ))
        .write(
          ImportJobsCompanion(
            state: Value(ImportJobState.succeeded.name),
            lastError: const Value(null),
            nextRetryAt: const Value(null),
            updatedAt: Value(now),
            completedAt: Value(now),
          ),
        );
  }

  Future<void> markAwaitingReview(String id) async {
    final now = DateTime.now();
    await (_db.update(_db.importJobs)..where(
          (row) =>
              row.id.equals(id) & row.state.equals(ImportJobState.running.name),
        ))
        .write(
          ImportJobsCompanion(
            state: Value(ImportJobState.awaitingReview.name),
            lastError: const Value(null),
            nextRetryAt: const Value(null),
            updatedAt: Value(now),
            completedAt: const Value(null),
          ),
        );
  }

  Future<void> markFailed(String id, Object error) async {
    final job = await find(id);
    if (job == null) return;
    final now = DateTime.now();
    final exhausted = job.attemptCount >= job.maxAttempts;
    final delaySeconds = 30 * pow(2, max(0, job.attemptCount - 1)).toInt();
    await (_db.update(_db.importJobs)..where(
          (row) =>
              row.id.equals(id) & row.state.equals(ImportJobState.running.name),
        ))
        .write(
          ImportJobsCompanion(
            state: Value(
              exhausted
                  ? ImportJobState.failed.name
                  : ImportJobState.retryScheduled.name,
            ),
            lastError: Value(safeErrorMessage(error)),
            nextRetryAt: Value(
              exhausted ? null : now.add(Duration(seconds: delaySeconds)),
            ),
            updatedAt: Value(now),
            completedAt: Value(exhausted ? now : null),
          ),
        );
  }

  Future<void> retryNow(String id) async {
    final now = DateTime.now();
    await (_db.update(_db.importJobs)..where(
          (row) =>
              row.id.equals(id) &
              (row.state.equals(ImportJobState.awaitingReview.name) |
                  row.state.equals(ImportJobState.failed.name) |
                  row.state.equals(ImportJobState.retryScheduled.name)),
        ))
        .write(
          ImportJobsCompanion(
            state: Value(ImportJobState.queued.name),
            attemptCount: const Value(0),
            lastError: const Value(null),
            nextRetryAt: const Value(null),
            completedAt: const Value(null),
            updatedAt: Value(now),
          ),
        );
  }

  Future<int> retryAllFailed() async {
    final now = DateTime.now();
    return (_db.update(
      _db.importJobs,
    )..where((row) => row.state.equals(ImportJobState.failed.name))).write(
      ImportJobsCompanion(
        state: Value(ImportJobState.queued.name),
        attemptCount: const Value(0),
        lastError: const Value(null),
        nextRetryAt: const Value(null),
        completedAt: const Value(null),
        updatedAt: Value(now),
      ),
    );
  }

  Future<int> clearSucceeded() {
    return (_db.delete(
      _db.importJobs,
    )..where((row) => row.state.equals(ImportJobState.succeeded.name))).go();
  }

  Future<int> clear() => _db.delete(_db.importJobs).go();

  Future<Duration?> delayUntilNextRetry() async {
    final query = _db.select(_db.importJobs)
      ..where(
        (row) =>
            row.state.equals(ImportJobState.retryScheduled.name) &
            row.nextRetryAt.isNotNull(),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.nextRetryAt)])
      ..limit(1);
    final row = await query.getSingleOrNull();
    final retryAt = row?.nextRetryAt;
    if (retryAt == null) return null;
    final delay = retryAt.difference(DateTime.now());
    return delay.isNegative ? Duration.zero : delay;
  }

  ImportJobEntity _fromRow(ImportJobRow row) {
    return ImportJobEntity(
      id: row.id,
      fileName: row.fileName,
      kind: row.kind,
      state: _state(row.state),
      attemptCount: row.attemptCount,
      maxAttempts: row.maxAttempts,
      lastError: row.lastError,
      nextRetryAt: row.nextRetryAt,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      completedAt: row.completedAt,
    );
  }

  ImportJobState _state(String name) {
    for (final state in ImportJobState.values) {
      if (state.name == name) return state;
    }
    return ImportJobState.failed;
  }
}
