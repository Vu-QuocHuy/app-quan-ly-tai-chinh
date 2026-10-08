import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';

class IncomeEntry {
  const IncomeEntry({
    required this.id,
    required this.amountMinor,
    required this.receivedAt,
    required this.updatedAt,
  });

  final String id;
  final int amountMinor;
  final DateTime receivedAt;
  final DateTime updatedAt;

  static IncomeEntry fromPayload(Map<String, dynamic> payload) {
    final id = payload['id'];
    final amount = payload['amountMinor'];
    final receivedAt = DateTime.tryParse('${payload['receivedAt'] ?? ''}');
    final updatedAt = DateTime.tryParse('${payload['updatedAt'] ?? ''}');
    if (id is! String ||
        id.trim().isEmpty ||
        id.length > 128 ||
        amount is! int ||
        amount <= 0 ||
        amount > 9007199254740991 ||
        receivedAt == null ||
        updatedAt == null) {
      throw const FormatException('Khoản thu không hợp lệ.');
    }
    return IncomeEntry(
      id: id,
      amountMinor: amount,
      receivedAt: receivedAt.toLocal(),
      updatedAt: updatedAt.toLocal(),
    );
  }

  Map<String, Object> toPayload() => {
    'id': id,
    'amountMinor': amountMinor,
    'receivedAt': receivedAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

class IncomeRepository {
  const IncomeRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  // ponytail: watchAll loads every income; add month paging if histories exceed 10k rows.
  Stream<List<IncomeEntry>> watchAll() =>
      (_db.select(_db.incomes)
            ..orderBy([(row) => OrderingTerm.desc(row.receivedAt)]))
          .watch()
          .map((rows) => rows.map(_fromRow).toList(growable: false));

  Future<List<IncomeEntry>> getAll() async =>
      (await _db.select(_db.incomes).get())
          .map(_fromRow)
          .toList(growable: false);

  Future<void> save(int amountMinor, {IncomeEntry? existing}) async {
    if (amountMinor <= 0 || amountMinor > 9007199254740991) {
      throw const FormatException('Số tiền thu phải lớn hơn 0.');
    }
    final now = DateTime.now();
    final entry = IncomeEntry(
      id: existing?.id ?? _uuid.v4(),
      amountMinor: amountMinor,
      receivedAt: existing?.receivedAt ?? now,
      updatedAt: now,
    );
    await _db.transaction(() async {
      await _db.into(_db.incomes).insertOnConflictUpdate(_companion(entry));
      await _enqueue(entry.id, 'upsert', entry.toPayload());
    });
  }

  Future<void> delete(String id) async {
    await _db.transaction(() async {
      final removed = await (_db.delete(
        _db.incomes,
      )..where((row) => row.id.equals(id))).go();
      if (removed > 0) await _enqueue(id, 'delete', {'id': id});
    });
  }

  Future<void> saveRemote(IncomeEntry entry) =>
      _db.into(_db.incomes).insertOnConflictUpdate(_companion(entry));

  Future<void> deleteRemote(String id) =>
      (_db.delete(_db.incomes)..where((row) => row.id.equals(id))).go();

  Future<bool> hasPendingChange(String id) async =>
      (await (_db.select(_db.syncOutboxEvents)
                ..where(
                  (row) =>
                      row.aggregateType.equals('income') &
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
    Map<String, Object> payload,
  ) async {
    final now = DateTime.now();
    await (_db.delete(_db.syncOutboxEvents)..where(
          (row) =>
              row.aggregateType.equals('income') &
              row.aggregateId.equals(id) &
              row.state.equals('pending'),
        ))
        .go();
    await _db
        .into(_db.syncOutboxEvents)
        .insert(
          SyncOutboxEventsCompanion.insert(
            id: _uuid.v4(),
            aggregateType: 'income',
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

  static IncomesCompanion _companion(IncomeEntry entry) =>
      IncomesCompanion.insert(
        id: entry.id,
        amountMinor: entry.amountMinor,
        receivedAt: entry.receivedAt,
        updatedAt: entry.updatedAt,
      );

  static IncomeEntry _fromRow(IncomeRow row) => IncomeEntry(
    id: row.id,
    amountMinor: row.amountMinor,
    receivedAt: row.receivedAt,
    updatedAt: row.updatedAt,
  );
}
