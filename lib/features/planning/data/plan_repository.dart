import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/plan_models.dart';

class PlanRepository {
  const PlanRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<PlanItem>> watchAll() =>
      (_db.select(_db.plans)
            ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
          .watch()
          .map((rows) => rows.map(_fromRow).toList(growable: false));

  Future<List<PlanItem>> getAll() async =>
      (await _db.select(_db.plans).get()).map(_fromRow).toList(growable: false);

  Future<PlanItem?> findById(String id) async {
    final row = await (_db.select(
      _db.plans,
    )..where((item) => item.id.equals(id))).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  Future<void> save(PlanItem item) async {
    PlanItem.fromPayload(Map<String, dynamic>.from(item.toPayload()));
    await _db.transaction(() async {
      await _db.into(_db.plans).insertOnConflictUpdate(_companion(item));
      await _enqueue(item.id, 'upsert', item.toPayload());
    });
  }

  Future<void> delete(String id) async {
    await _db.transaction(() async {
      final removed = await (_db.delete(
        _db.plans,
      )..where((item) => item.id.equals(id))).go();
      if (removed > 0) await _enqueue(id, 'delete', {'id': id});
    });
  }

  Future<void> saveRemote(PlanItem item) =>
      _db.into(_db.plans).insertOnConflictUpdate(_companion(item));

  Future<void> deleteRemote(String id) =>
      (_db.delete(_db.plans)..where((item) => item.id.equals(id))).go();

  Future<bool> hasPendingChange(String id) async =>
      (await (_db.select(_db.syncOutboxEvents)
                ..where(
                  (row) =>
                      row.aggregateType.equals('plan') &
                      row.aggregateId.equals(id) &
                      (row.state.equals('pending') |
                          row.state.equals('sending') |
                          row.state.equals('failed')),
                )
                ..limit(1))
              .get())
          .isNotEmpty;

  Future<void> _enqueue(
    String id,
    String operation,
    Map<String, Object?> payload,
  ) async {
    final now = DateTime.now();
    await (_db.delete(_db.syncOutboxEvents)..where(
          (row) =>
              row.aggregateType.equals('plan') &
              row.aggregateId.equals(id) &
              row.state.equals('pending'),
        ))
        .go();
    await _db
        .into(_db.syncOutboxEvents)
        .insert(
          SyncOutboxEventsCompanion.insert(
            id: _uuid.v4(),
            aggregateType: 'plan',
            aggregateId: id,
            operation: operation,
            payloadJson: Value(jsonEncode(payload)),
            revision: 1,
            availableAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  static PlansCompanion _companion(PlanItem item) {
    final payload = item.toPayload();
    return PlansCompanion.insert(
      id: item.id,
      kind: item.kind,
      categoryId: Value(payload['categoryId'] as String?),
      payloadJson: jsonEncode(payload),
      updatedAt: item.updatedAt,
    );
  }

  static PlanItem _fromRow(PlanRow row) {
    final decoded = jsonDecode(row.payloadJson);
    if (decoded is! Map) {
      throw const FormatException('Dữ liệu kế hoạch không hợp lệ.');
    }
    final item = PlanItem.fromPayload(Map<String, dynamic>.from(decoded));
    if (item.id != row.id || item.kind != row.kind) {
      throw const FormatException('Dữ liệu kế hoạch không khớp.');
    }
    return item;
  }
}
