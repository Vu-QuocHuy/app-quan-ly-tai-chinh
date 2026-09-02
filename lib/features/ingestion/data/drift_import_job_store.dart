import 'dart:math';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
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
    final existing = await find(pending.id);
    if (existing == null) {
      final now = DateTime.now();
      await _db
          .into(_db.importJobs)
          .insert(
            ImportJobsCompanion.insert(
              id: pending.id,
              fileName: pending.fileName,
              kind: pending.kind.name,
              createdAt: now,
              updatedAt: now,
            ),
          );
      return;
    }
    if (existing.state == ImportJobState.running) {
      final now = DateTime.now();
      await (_db.update(
        _db.importJobs,
      )..where((row) => row.id.equals(pending.id))).write(
        ImportJobsCompanion(
          state: Value(ImportJobState.retryScheduled.name),
          nextRetryAt: Value(now),
          updatedAt: Value(now),
          lastError: const Value('Tác vụ bị gián đoạn khi ứng dụng đóng.'),
        ),
      );
    }
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
      ImportJobState.succeeded ||
      ImportJobState.failed => false,
    };
  }

  Future<bool> markRunning(String id) async {
    final job = await find(id);
    if (job == null || !await isRunnable(id)) return false;
    final now = DateTime.now();
    await (_db.update(_db.importJobs)..where((row) => row.id.equals(id))).write(
      ImportJobsCompanion(
        state: Value(ImportJobState.running.name),
        attemptCount: Value(job.attemptCount + 1),
        lastError: const Value(null),
        nextRetryAt: const Value(null),
        updatedAt: Value(now),
      ),
    );
    return true;
  }

  Future<void> markSucceeded(String id) async {
    final now = DateTime.now();
    await (_db.update(_db.importJobs)..where((row) => row.id.equals(id))).write(
      ImportJobsCompanion(
        state: Value(ImportJobState.succeeded.name),
        lastError: const Value(null),
        nextRetryAt: const Value(null),
        updatedAt: Value(now),
        completedAt: Value(now),
      ),
    );
  }

  Future<void> markFailed(String id, Object error) async {
    final job = await find(id);
    if (job == null) return;
    final now = DateTime.now();
    final exhausted = job.attemptCount >= job.maxAttempts;
    final delaySeconds = 30 * pow(2, max(0, job.attemptCount - 1)).toInt();
    await (_db.update(_db.importJobs)..where((row) => row.id.equals(id))).write(
      ImportJobsCompanion(
        state: Value(
          exhausted
              ? ImportJobState.failed.name
              : ImportJobState.retryScheduled.name,
        ),
        lastError: Value(error.toString()),
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
    await (_db.update(_db.importJobs)..where((row) => row.id.equals(id))).write(
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
