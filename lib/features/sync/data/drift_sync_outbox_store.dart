import 'dart:math';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../invoices/domain/invoice_models.dart';
import '../domain/sync_models.dart';

class DriftSyncOutboxStore {
  const DriftSyncOutboxStore(this._db);

  final AppDatabase _db;

  Stream<SyncHealth> watchHealth({required bool cloudConfigured}) {
    final trigger = _db.customSelect(
      'SELECT 1 AS tick',
      readsFrom: {_db.syncOutboxEvents},
    );
    return trigger.watch().asyncMap((_) async {
      final row = await _db
          .customSelect(
            '''
          SELECT
            SUM(CASE WHEN state IN ('pending', 'sending') THEN 1 ELSE 0 END)
              AS pending_count,
            SUM(CASE WHEN state = 'failed' THEN 1 ELSE 0 END)
              AS failed_count
          FROM sync_outbox_events
        ''',
            readsFrom: {_db.syncOutboxEvents},
          )
          .getSingle();
      return SyncHealth(
        pendingCount: row.readNullable<int>('pending_count') ?? 0,
        failedCount: row.readNullable<int>('failed_count') ?? 0,
        cloudConfigured: cloudConfigured,
      );
    });
  }

  Future<List<SyncOutboxEntry>> fetchDue({int limit = 50}) async {
    final now = DateTime.now();
    final query = _db.select(_db.syncOutboxEvents)
      ..where(
        (row) =>
            row.state.equals(SyncOutboxState.pending.name) &
            row.availableAt.isSmallerOrEqualValue(now),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.availableAt),
        (row) => OrderingTerm.asc(row.createdAt),
      ])
      ..limit(limit.clamp(1, 200));
    return (await query.get()).map(_fromRow).toList(growable: false);
  }

  Future<void> recoverInterrupted() async {
    final now = DateTime.now();
    await (_db.update(_db.syncOutboxEvents)..where(
          (row) =>
              row.state.equals(SyncOutboxState.sending.name) &
              row.updatedAt.isSmallerThanValue(
                now.subtract(const Duration(minutes: 10)),
              ),
        ))
        .write(
          SyncOutboxEventsCompanion(
            state: Value(SyncOutboxState.pending.name),
            availableAt: Value(now),
            updatedAt: Value(now),
            lastError: const Value(
              'Lần đồng bộ trước bị gián đoạn; đã xếp lại tác vụ.',
            ),
          ),
        );
  }

  Future<bool> markSending(SyncOutboxEntry entry) async {
    final now = DateTime.now();
    final changed = await _db.customUpdate(
      '''
      UPDATE sync_outbox_events
      SET state = ?,
          attempt_count = attempt_count + 1,
          available_at = ?,
          updated_at = ?,
          last_error = NULL
      WHERE id = ?
        AND state = ?
        AND available_at <= ?
      ''',
      variables: [
        Variable(SyncOutboxState.sending.name),
        Variable(now),
        Variable(now),
        Variable(entry.id),
        Variable(SyncOutboxState.pending.name),
        Variable(now),
      ],
      updates: {_db.syncOutboxEvents},
    );
    return changed == 1;
  }

  Future<void> markSent(SyncOutboxEntry entry) async {
    await _db.transaction(() async {
      await _writeState(
        entry.id,
        SyncOutboxState.sent,
        attemptCount: entry.attemptCount + 1,
        clearError: true,
      );
      if (entry.aggregateType != 'invoice') return;
      await (_db.update(_db.invoices)..where(
            (row) =>
                row.id.equals(entry.aggregateId) &
                row.revision.equals(entry.revision),
          ))
          .write(
            InvoicesCompanion(syncState: Value(InvoiceSyncState.synced.name)),
          );
    });
  }

  Future<void> markFailed(SyncOutboxEntry entry, Object error) async {
    final attempts = entry.attemptCount + 1;
    final terminal = attempts >= 5;
    final delayMinutes = min(60, pow(2, attempts - 1).toInt());
    await _writeState(
      entry.id,
      terminal ? SyncOutboxState.failed : SyncOutboxState.pending,
      attemptCount: attempts,
      lastError: safeErrorMessage(error),
      availableAt: DateTime.now().add(Duration(minutes: delayMinutes)),
    );
  }

  Future<void> retryFailed() async {
    final now = DateTime.now();
    await (_db.update(
      _db.syncOutboxEvents,
    )..where((row) => row.state.equals(SyncOutboxState.failed.name))).write(
      SyncOutboxEventsCompanion(
        state: Value(SyncOutboxState.pending.name),
        attemptCount: const Value(0),
        availableAt: Value(now),
        updatedAt: Value(now),
        lastError: const Value(null),
      ),
    );
  }

  Future<int> deleteSentBefore(DateTime threshold) {
    return (_db.delete(_db.syncOutboxEvents)..where(
          (row) =>
              row.state.equals(SyncOutboxState.sent.name) &
              row.updatedAt.isSmallerThanValue(threshold),
        ))
        .go();
  }

  Future<void> _writeState(
    String id,
    SyncOutboxState state, {
    required int attemptCount,
    String? lastError,
    bool clearError = false,
    DateTime? availableAt,
  }) async {
    final now = DateTime.now();
    await (_db.update(
      _db.syncOutboxEvents,
    )..where((row) => row.id.equals(id))).write(
      SyncOutboxEventsCompanion(
        state: Value(state.name),
        attemptCount: Value(attemptCount),
        availableAt: Value(availableAt ?? now),
        updatedAt: Value(now),
        lastError: clearError ? const Value(null) : Value(lastError),
      ),
    );
  }

  SyncOutboxEntry _fromRow(SyncOutboxEventRow row) {
    return SyncOutboxEntry(
      id: row.id,
      aggregateType: row.aggregateType,
      aggregateId: row.aggregateId,
      operation: _operation(row.operation),
      payloadJson: row.payloadJson,
      revision: row.revision,
      state: _state(row.state),
      attemptCount: row.attemptCount,
      availableAt: row.availableAt,
      createdAt: row.createdAt,
      lastError: row.lastError,
    );
  }

  SyncOperation _operation(String name) {
    for (final operation in SyncOperation.values) {
      if (operation.name == name) return operation;
    }
    return SyncOperation.upsert;
  }

  SyncOutboxState _state(String name) {
    for (final state in SyncOutboxState.values) {
      if (state.name == name) return state;
    }
    return SyncOutboxState.failed;
  }
}
