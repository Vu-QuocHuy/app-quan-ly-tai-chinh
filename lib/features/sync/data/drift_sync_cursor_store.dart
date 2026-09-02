import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/sync_models.dart';

class DriftSyncCursorStore {
  const DriftSyncCursorStore(this._db);

  final AppDatabase _db;

  Future<SyncCursor?> read({
    required String userId,
    required String aggregateType,
  }) async {
    final row =
        await (_db.select(_db.syncCursors)..where(
              (item) =>
                  item.userId.equals(userId) &
                  item.aggregateType.equals(aggregateType),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return SyncCursor(updatedAt: row.updatedAt, updatedId: row.updatedId);
  }

  Future<void> write({
    required String userId,
    required String aggregateType,
    required SyncCursor cursor,
  }) {
    return _db
        .into(_db.syncCursors)
        .insertOnConflictUpdate(
          SyncCursorsCompanion(
            userId: Value(userId),
            aggregateType: Value(aggregateType),
            updatedAt: Value(cursor.updatedAt),
            updatedId: Value(cursor.updatedId),
          ),
        );
  }

  Future<void> clearUser(String userId) {
    return (_db.delete(
      _db.syncCursors,
    )..where((row) => row.userId.equals(userId))).go();
  }
}
