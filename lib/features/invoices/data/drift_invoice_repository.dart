import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/string_normalizer.dart';
import '../../insights/domain/spending_insight_engine.dart';
import '../../sync/data/invoice_sync_codec.dart';
import '../domain/invoice_filters.dart';
import '../domain/invoice_models.dart';
import '../domain/invoice_repository.dart';

class DriftInvoiceRepository implements InvoiceRepository {
  DriftInvoiceRepository(
    this._db, {
    Uuid? uuid,
    SpendingInsightEngine insightEngine = const SpendingInsightEngine(),
  }) : _uuid = uuid ?? const Uuid(),
       _insightEngine = insightEngine;

  final AppDatabase _db;
  final Uuid _uuid;
  final SpendingInsightEngine _insightEngine;

  @override
  Stream<List<InvoiceEntity>> watchInvoices() {
    final query = _db.select(_db.invoices)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([
        (row) => OrderingTerm.desc(row.updatedAt),
        (row) => OrderingTerm.desc(row.id),
      ]);
    return query.watch().asyncMap((rows) => Future.wait(rows.map(_hydrate)));
  }

  @override
  Stream<List<InvoiceEntity>> watchInvoiceSummaries({
    InvoiceFilter filter = const InvoiceFilter(),
    int? limit,
  }) {
    final query = _summaryQuery(filter);
    if (limit != null) query.limit(limit);
    return query.watch().map(
      (rows) => rows.map(_fromRow).toList(growable: false),
    );
  }

  @override
  Future<InvoicePage> fetchInvoicePage({
    InvoiceFilter filter = const InvoiceFilter(),
    int limit = 50,
    InvoicePageCursor? cursor,
  }) async {
    final safeLimit = limit.clamp(1, 200);
    final query = _summaryQuery(filter);
    if (cursor != null) {
      query.where(
        (row) =>
            row.updatedAt.isSmallerThanValue(cursor.updatedAt) |
            (row.updatedAt.equals(cursor.updatedAt) &
                row.id.isSmallerThanValue(cursor.id)),
      );
    }
    query.limit(safeLimit + 1);
    final rows = await query.get();
    final hasMore = rows.length > safeLimit;
    final visible = hasMore ? rows.take(safeLimit).toList() : rows;
    final items = visible.map(_fromRow).toList(growable: false);
    final last = items.lastOrNull;
    return InvoicePage(
      items: items,
      hasMore: hasMore,
      nextCursor: last == null
          ? null
          : InvoicePageCursor(updatedAt: last.updatedAt, id: last.id),
    );
  }

  @override
  Stream<List<CategoryEntity>> watchCategories() {
    final query = _db.select(_db.categories)
      ..orderBy([(row) => OrderingTerm.asc(row.name)]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => CategoryEntity(
              id: row.id,
              name: row.name,
              iconName: row.iconName,
              colorValue: row.colorValue,
              isSystem: row.isSystem,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Stream<List<MerchantRuleEntity>> watchMerchantRules() {
    final query = _db.select(_db.merchantRules)
      ..orderBy([(row) => OrderingTerm.asc(row.normalizedMerchant)]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => MerchantRuleEntity(
              normalizedMerchant: row.normalizedMerchant,
              categoryId: row.categoryId,
              updatedAt: row.updatedAt,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Stream<List<BudgetEntity>> watchBudgets(String monthKey) {
    final query = _db.select(_db.budgets)
      ..where((row) => row.monthKey.equals(monthKey));
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => BudgetEntity(
              id: row.id,
              monthKey: row.monthKey,
              categoryId: row.categoryId,
              limitMinor: row.limitMinor,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Stream<DashboardSnapshot> watchDashboard(String monthKey) {
    final trigger = _db.customSelect(
      'SELECT 1 AS tick',
      readsFrom: {_db.invoices, _db.budgets},
    );
    return trigger.watch().asyncMap((_) => _loadDashboard(monthKey));
  }

  @override
  Stream<SpendingInsights> watchSpendingInsights(String monthKey) {
    final month = _parseMonthKey(monthKey);
    final start = DateTime(month.year, month.month - 5);
    final end = DateTime(month.year, month.month + 1);
    final query = _db.select(_db.invoices)
      ..where(
        (row) =>
            row.deletedAt.isNull() &
            row.status.equals(InvoiceStatus.confirmed.name) &
            _dateInRange(row, start, end),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.issuedAt)]);
    return query.watch().map(
      (rows) =>
          _insightEngine.analyze(invoices: rows.map(_fromRow), month: month),
    );
  }

  @override
  Future<InvoiceEntity?> findById(String id) async {
    final query = _db.select(_db.invoices)
      ..where((row) => row.id.equals(id) & row.deletedAt.isNull());
    final row = await query.getSingleOrNull();
    return row == null ? null : _hydrate(row);
  }

  @override
  Future<InvoiceEntity?> findBySourceHash(String hash) async {
    final query = _db.select(_db.invoices)
      ..where((row) => row.sourceHash.equals(hash) & row.deletedAt.isNull());
    final row = await query.getSingleOrNull();
    return row == null ? null : _hydrate(row);
  }

  @override
  Future<List<InvoiceEntity>> findDuplicateCandidates(
    InvoiceEntity candidate,
  ) async {
    final predicates = <Expression<bool>>[];
    if (candidate.sellerTaxCode?.trim().isNotEmpty == true) {
      predicates.add(
        _db.invoices.sellerTaxCode.equals(candidate.sellerTaxCode!),
      );
    }
    if (candidate.invoiceNumber?.trim().isNotEmpty == true) {
      predicates.add(
        _db.invoices.invoiceNumber.equals(candidate.invoiceNumber!),
      );
    }
    if (candidate.totalMinor > 0) {
      predicates.add(_db.invoices.totalMinor.equals(candidate.totalMinor));
    }
    final candidateDate = candidate.issuedAt ?? candidate.createdAt;
    final start = DateTime(
      candidateDate.year,
      candidateDate.month,
      candidateDate.day,
    );
    predicates.add(
      _dateInRange(_db.invoices, start, start.add(const Duration(days: 1))),
    );
    if (predicates.isEmpty) return const [];

    final matching = predicates.reduce((left, right) => left | right);
    final query = _db.select(_db.invoices)
      ..where((row) => row.deletedAt.isNull() & matching)
      ..orderBy([
        (row) => OrderingTerm.desc(row.updatedAt),
        (row) => OrderingTerm.desc(row.id),
      ])
      ..limit(200);
    return (await query.get()).map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> saveInvoice(InvoiceEntity invoice) async {
    await _db.transaction(() => _saveInvoice(invoice));
  }

  @override
  Future<void> saveRemoteInvoice(InvoiceEntity invoice) async {
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.invoices,
      )..where((row) => row.id.equals(invoice.id))).getSingleOrNull();
      if (existing != null && invoice.revision < existing.revision) return;
      await _saveInvoice(
        invoice,
        enqueueSync: false,
        syncState: InvoiceSyncState.synced,
        revisionOverride: invoice.revision,
      );
      await _discardRemoteOutbox(invoice.id, invoice.revision);
    });
  }

  @override
  Future<void> deleteRemoteInvoice(
    String id, {
    required int revision,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) async {
    if (id.trim().isEmpty || revision < 1) {
      throw const FormatException('Invoice tombstone không hợp lệ.');
    }
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.invoices,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (existing != null && revision < existing.revision) return;
      final tombstoneAt = deletedAt ?? updatedAt;
      if (existing == null) {
        await _db
            .into(_db.invoices)
            .insert(
              InvoicesCompanion(
                id: Value(id),
                sellerName: const Value('Đã xóa'),
                currencyCode: const Value('VND'),
                subtotalMinor: const Value(0),
                taxMinor: const Value(0),
                totalMinor: const Value(0),
                sourceType: const Value('manual'),
                status: const Value('failed'),
                searchText: const Value(''),
                tagsJson: const Value('[]'),
                createdAt: Value(updatedAt),
                updatedAt: Value(updatedAt),
                syncState: const Value('synced'),
                revision: Value(revision),
                deletedAt: Value(tombstoneAt),
              ),
            );
      } else {
        await (_db.update(
          _db.invoices,
        )..where((row) => row.id.equals(id))).write(
          InvoicesCompanion(
            updatedAt: Value(updatedAt),
            sourceHash: const Value(null),
            syncState: const Value('synced'),
            revision: Value(revision),
            deletedAt: Value(tombstoneAt),
          ),
        );
      }
      await (_db.delete(
        _db.invoiceLines,
      )..where((row) => row.invoiceId.equals(id))).go();
      await (_db.delete(
        _db.fieldEvidences,
      )..where((row) => row.invoiceId.equals(id))).go();
      await (_db.delete(
        _db.invoiceConflicts,
      )..where((row) => row.invoiceId.equals(id))).go();
      await _discardRemoteOutbox(id, revision);
    });
  }

  @override
  Future<void> saveRemoteCategory(CategoryEntity category) async {
    await _db
        .into(_db.categories)
        .insertOnConflictUpdate(
          CategoriesCompanion(
            id: Value(category.id),
            name: Value(category.name),
            iconName: Value(category.iconName),
            colorValue: Value(category.colorValue),
            isSystem: Value(category.isSystem),
          ),
        );
  }

  @override
  Future<void> deleteRemoteCategory(String id) async {
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.categories,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (existing == null || existing.isSystem) return;
      await (_db.delete(
        _db.budgets,
      )..where((row) => row.categoryId.equals(id))).go();
      await (_db.delete(
        _db.merchantRules,
      )..where((row) => row.categoryId.equals(id))).go();
      await (_db.delete(
        _db.categories,
      )..where((row) => row.id.equals(id))).go();
    });
  }

  @override
  Future<void> saveRemoteBudget(BudgetEntity budget) async {
    await _db
        .into(_db.budgets)
        .insertOnConflictUpdate(
          BudgetsCompanion.insert(
            id: budget.id,
            monthKey: budget.monthKey,
            categoryId: budget.categoryId,
            limitMinor: budget.limitMinor,
          ),
        );
  }

  @override
  Future<void> deleteRemoteBudget(String id) async {
    await (_db.delete(_db.budgets)..where((row) => row.id.equals(id))).go();
  }

  @override
  Future<void> saveRemoteMerchantRule(MerchantRuleEntity rule) async {
    await _db
        .into(_db.merchantRules)
        .insertOnConflictUpdate(
          MerchantRulesCompanion.insert(
            id: rule.normalizedMerchant,
            normalizedMerchant: rule.normalizedMerchant,
            categoryId: rule.categoryId,
            updatedAt: rule.updatedAt,
          ),
        );
  }

  @override
  Future<void> deleteRemoteMerchantRule(String normalizedMerchant) async {
    await (_db.delete(
      _db.merchantRules,
    )..where((row) => row.normalizedMerchant.equals(normalizedMerchant))).go();
  }

  @override
  Future<void> markInvoiceConflict(String id, {InvoiceEntity? remote}) async {
    await _db.transaction(() async {
      await (_db.update(_db.invoices)..where((row) => row.id.equals(id))).write(
        InvoicesCompanion(syncState: Value(InvoiceSyncState.conflict.name)),
      );
      if (remote == null) return;
      await _db
          .into(_db.invoiceConflicts)
          .insertOnConflictUpdate(
            InvoiceConflictsCompanion.insert(
              invoiceId: id,
              remotePayloadJson: jsonEncode(_syncPayload(remote)),
              remoteRevision: remote.revision,
              detectedAt: DateTime.now(),
            ),
          );
    });
  }

  @override
  Stream<List<InvoiceConflictEntity>> watchInvoiceConflicts() {
    final query = _db.select(_db.invoiceConflicts)
      ..orderBy([(row) => OrderingTerm.desc(row.detectedAt)]);
    return query.watch().asyncMap((rows) async {
      final conflicts = <InvoiceConflictEntity>[];
      for (final row in rows) {
        final local = await findById(row.invoiceId);
        if (local == null) continue;
        final decoded = jsonDecode(row.remotePayloadJson);
        if (decoded is! Map) continue;
        final remote = InvoiceSyncCodec.fromPayload(
          Map<String, dynamic>.from(decoded),
          revision: row.remoteRevision,
        );
        conflicts.add(
          InvoiceConflictEntity(
            local: local,
            remote: remote,
            detectedAt: row.detectedAt,
          ),
        );
      }
      return conflicts;
    });
  }

  @override
  Future<void> resolveInvoiceConflictKeepLocal(String id) async {
    final local = await findById(id);
    if (local == null) return;
    await saveInvoice(
      local.copyWith(
        updatedAt: DateTime.now(),
        syncState: InvoiceSyncState.pending,
        revision: local.revision + 1,
      ),
    );
    await (_db.delete(
      _db.invoiceConflicts,
    )..where((row) => row.invoiceId.equals(id))).go();
  }

  @override
  Future<void> resolveInvoiceConflictUseRemote(String id) async {
    final row = await (_db.select(
      _db.invoiceConflicts,
    )..where((item) => item.invoiceId.equals(id))).getSingleOrNull();
    if (row == null) return;
    final decoded = jsonDecode(row.remotePayloadJson);
    if (decoded is! Map) {
      throw const FormatException('Conflict payload không hợp lệ.');
    }
    final remote = InvoiceSyncCodec.fromPayload(
      Map<String, dynamic>.from(decoded),
      revision: row.remoteRevision,
    );
    await saveRemoteInvoice(remote);
    await (_db.delete(
      _db.invoiceConflicts,
    )..where((item) => item.invoiceId.equals(id))).go();
  }

  @override
  Future<void> saveInvoices(Iterable<InvoiceEntity> invoices) async {
    await _db.transaction(() async {
      for (final invoice in invoices) {
        await _saveInvoice(invoice);
      }
    });
  }

  @override
  Future<void> deleteInvoice(String id) async {
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.invoices,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (existing == null || existing.deletedAt != null) return;
      final now = DateTime.now();
      final revision = existing.revision + 1;
      await (_db.update(_db.invoices)..where((row) => row.id.equals(id))).write(
        InvoicesCompanion(
          updatedAt: Value(now),
          deletedAt: Value(now),
          sourceHash: const Value(null),
          syncState: Value(InvoiceSyncState.pending.name),
          revision: Value(revision),
        ),
      );
      await _enqueueSync(
        aggregateId: id,
        operation: 'delete',
        revision: revision,
        payload: jsonEncode({'id': id, 'deletedAt': now.toIso8601String()}),
        now: now,
      );
      await (_db.delete(
        _db.invoiceConflicts,
      )..where((row) => row.invoiceId.equals(id))).go();
    });
  }

  @override
  Future<void> deleteAllUserData() async {
    await _db.transaction(() async {
      await _db.delete(_db.extractionAttempts).go();
      await _db.delete(_db.invoiceConflicts).go();
      await _db.delete(_db.invoices).go();
      await _db.delete(_db.budgets).go();
      await _db.delete(_db.merchantRules).go();
      await (_db.delete(
        _db.categories,
      )..where((category) => category.isSystem.equals(false))).go();
      await _db.delete(_db.syncOutboxEvents).go();
      await _db.delete(_db.syncCursors).go();
      await _db.delete(_db.importJobs).go();
    });
  }

  @override
  Future<void> saveCategory(CategoryEntity category) async {
    if (category.id.trim().isEmpty || category.name.trim().isEmpty) {
      throw ArgumentError('Danh mục phải có mã và tên.');
    }
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db
          .into(_db.categories)
          .insertOnConflictUpdate(
            CategoriesCompanion(
              id: Value(category.id),
              name: Value(category.name.trim()),
              iconName: Value(category.iconName),
              colorValue: Value(category.colorValue),
              isSystem: Value(category.isSystem),
            ),
          );
      await _enqueueSync(
        aggregateType: 'category',
        aggregateId: category.id,
        operation: 'upsert',
        revision: 1,
        payload: jsonEncode({
          'id': category.id,
          'name': category.name.trim(),
          'iconName': category.iconName,
          'colorValue': category.colorValue,
          'isSystem': category.isSystem,
        }),
        now: now,
      );
    });
  }

  @override
  Future<void> deleteCategory(String id) async {
    await _db.transaction(() async {
      final category = await (_db.select(
        _db.categories,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (category == null) return;
      if (category.isSystem) {
        throw StateError('Không thể xóa danh mục mặc định.');
      }

      await (_db.update(_db.invoices)
            ..where((row) => row.categoryId.equals(id)))
          .write(const InvoicesCompanion(categoryId: Value('other')));
      await (_db.update(_db.invoiceLines)
            ..where((row) => row.categoryId.equals(id)))
          .write(const InvoiceLinesCompanion(categoryId: Value('other')));
      await (_db.delete(
        _db.budgets,
      )..where((row) => row.categoryId.equals(id))).go();
      await (_db.delete(
        _db.merchantRules,
      )..where((row) => row.categoryId.equals(id))).go();
      await (_db.delete(
        _db.categories,
      )..where((row) => row.id.equals(id))).go();
      await _enqueueSync(
        aggregateType: 'category',
        aggregateId: id,
        operation: 'delete',
        revision: 1,
        payload: jsonEncode({'id': id}),
        now: DateTime.now(),
      );
    });
  }

  @override
  Future<void> saveBudget(BudgetEntity budget) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db
          .into(_db.budgets)
          .insertOnConflictUpdate(
            BudgetsCompanion.insert(
              id: budget.id,
              monthKey: budget.monthKey,
              categoryId: budget.categoryId,
              limitMinor: budget.limitMinor,
            ),
          );
      await _enqueueSync(
        aggregateType: 'budget',
        aggregateId: budget.id,
        operation: 'upsert',
        revision: 1,
        payload: jsonEncode({
          'id': budget.id,
          'monthKey': budget.monthKey,
          'categoryId': budget.categoryId,
          'limitMinor': budget.limitMinor,
        }),
        now: now,
      );
    });
  }

  @override
  Future<void> deleteBudget(String id) async {
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.budgets,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (existing == null) return;
      await (_db.delete(_db.budgets)..where((row) => row.id.equals(id))).go();
      await _enqueueSync(
        aggregateType: 'budget',
        aggregateId: id,
        operation: 'delete',
        revision: 1,
        payload: jsonEncode({'id': id}),
        now: DateTime.now(),
      );
    });
  }

  @override
  Future<void> saveMerchantRule(String merchant, String categoryId) async {
    final normalized = StringNormalizer.merchant(merchant);
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db
          .into(_db.merchantRules)
          .insertOnConflictUpdate(
            MerchantRulesCompanion.insert(
              id: normalized,
              normalizedMerchant: normalized,
              categoryId: categoryId,
              updatedAt: now,
            ),
          );
      await _enqueueSync(
        aggregateType: 'merchant_rule',
        aggregateId: normalized,
        operation: 'upsert',
        revision: 1,
        payload: jsonEncode({
          'id': normalized,
          'normalizedMerchant': normalized,
          'categoryId': categoryId,
          'updatedAt': now.toIso8601String(),
        }),
        now: now,
      );
    });
  }

  @override
  Future<void> deleteMerchantRule(String normalizedMerchant) async {
    final normalized = StringNormalizer.merchant(normalizedMerchant);
    await _db.transaction(() async {
      final existing =
          await (_db.select(_db.merchantRules)
                ..where((row) => row.normalizedMerchant.equals(normalized)))
              .getSingleOrNull();
      if (existing == null) return;
      await (_db.delete(
        _db.merchantRules,
      )..where((row) => row.normalizedMerchant.equals(normalized))).go();
      await _enqueueSync(
        aggregateType: 'merchant_rule',
        aggregateId: normalized,
        operation: 'delete',
        revision: 1,
        payload: jsonEncode({'id': normalized}),
        now: DateTime.now(),
      );
    });
  }

  @override
  Future<String?> categoryForMerchant(String merchant) async {
    final normalized = StringNormalizer.merchant(merchant);
    final query = _db.select(_db.merchantRules)
      ..where((row) => row.normalizedMerchant.equals(normalized));
    return (await query.getSingleOrNull())?.categoryId;
  }

  Future<InvoiceEntity> _hydrate(InvoiceRow row) async {
    final lines = await (_db.select(
      _db.invoiceLines,
    )..where((item) => item.invoiceId.equals(row.id))).get();
    final evidence = await (_db.select(
      _db.fieldEvidences,
    )..where((item) => item.invoiceId.equals(row.id))).get();
    return _fromRow(
      row,
      lines: lines
          .map(
            (item) => InvoiceLineEntity(
              id: item.id,
              description: item.description,
              quantity: item.quantity,
              unitPriceMinor: item.unitPriceMinor,
              taxRate: item.taxRate,
              totalMinor: item.totalMinor,
              categoryId: item.categoryId,
            ),
          )
          .toList(growable: false),
      evidence: evidence
          .map(
            (item) => FieldEvidenceEntity(
              id: item.id,
              fieldName: item.fieldName,
              rawValue: item.rawValue,
              normalizedValue: item.normalizedValue,
              source: _sourceTypeFromName(item.sourceType),
              confidence: item.confidence,
              correctedByUser: item.correctedByUser,
            ),
          )
          .toList(growable: false),
    );
  }

  InvoiceEntity _fromRow(
    InvoiceRow row, {
    List<InvoiceLineEntity> lines = const [],
    List<FieldEvidenceEntity> evidence = const [],
  }) {
    return InvoiceEntity(
      id: row.id,
      sellerName: row.sellerName,
      sellerTaxCode: row.sellerTaxCode,
      invoiceNumber: row.invoiceNumber,
      invoiceSymbol: row.invoiceSymbol,
      issuedAt: row.issuedAt,
      currencyCode: row.currencyCode,
      subtotalMinor: row.subtotalMinor,
      taxMinor: row.taxMinor,
      totalMinor: row.totalMinor,
      sourceType: _sourceTypeFromName(row.sourceType),
      sourceHash: row.sourceHash,
      status: InvoiceStatus.values.byName(row.status),
      categoryId: row.categoryId,
      cloudId: row.cloudId,
      notes: row.notes,
      tags: _decodeTags(row.tagsJson),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      confirmedAt: row.confirmedAt,
      syncState: _enumByName(
        InvoiceSyncState.values,
        row.syncState,
        InvoiceSyncState.localOnly,
      ),
      revision: row.revision,
      deletedAt: row.deletedAt,
      lines: lines,
      evidence: evidence,
    );
  }

  SimpleSelectStatement<$InvoicesTable, InvoiceRow> _summaryQuery(
    InvoiceFilter filter,
  ) {
    final query = _db.select(_db.invoices)
      ..where((row) => row.deletedAt.isNull());
    final normalizedQuery = StringNormalizer.merchant(filter.query);
    if (normalizedQuery.isNotEmpty) {
      query.where((row) => row.searchText.like('%$normalizedQuery%'));
    }
    if (filter.monthKey != null) {
      final month = _parseMonthKey(filter.monthKey!);
      query.where(
        (row) =>
            _dateInRange(row, month, DateTime(month.year, month.month + 1)),
      );
    }
    if (filter.categoryId != null) {
      query.where((row) => row.categoryId.equals(filter.categoryId!));
    }
    if (filter.status != null) {
      query.where((row) => row.status.equals(filter.status!.name));
    }
    if (filter.sourceType != null) {
      final sourceName = filter.sourceType!.name;
      query.where(
        (row) => sourceName == InvoiceSourceType.imageOcr.name
            ? row.sourceType.equals(sourceName) | row.sourceType.equals('qr')
            : row.sourceType.equals(sourceName),
      );
    }
    if (filter.minTotalMinor != null) {
      query.where(
        (row) => row.totalMinor.isBiggerThanValue(filter.minTotalMinor! - 1),
      );
    }
    if (filter.maxTotalMinor != null) {
      query.where(
        (row) => row.totalMinor.isSmallerThanValue(filter.maxTotalMinor! + 1),
      );
    }
    query.orderBy([
      (row) => OrderingTerm.desc(row.updatedAt),
      (row) => OrderingTerm.desc(row.id),
    ]);
    return query;
  }

  InvoiceSourceType _sourceTypeFromName(String name) {
    if (name == 'qr') return InvoiceSourceType.imageOcr;
    return InvoiceSourceType.values.byName(name);
  }

  Expression<bool> _dateInRange(
    $InvoicesTable row,
    DateTime start,
    DateTime end,
  ) {
    return (row.issuedAt.isNotNull() &
            row.issuedAt.isBiggerOrEqualValue(start) &
            row.issuedAt.isSmallerThanValue(end)) |
        (row.issuedAt.isNull() &
            row.createdAt.isBiggerOrEqualValue(start) &
            row.createdAt.isSmallerThanValue(end));
  }

  Future<DashboardSnapshot> _loadDashboard(String monthKey) async {
    final month = _parseMonthKey(monthKey);
    final end = DateTime(month.year, month.month + 1);
    final previous = DateTime(month.year, month.month - 1);

    final summary = await _db
        .customSelect(
          '''
        SELECT COALESCE(SUM(total_minor), 0) AS total,
               COUNT(*) AS invoice_count
        FROM invoices
        WHERE deleted_at IS NULL
          AND status = ?
          AND COALESCE(issued_at, created_at) >= ?
          AND COALESCE(issued_at, created_at) < ?
      ''',
          variables: [
            Variable<String>(InvoiceStatus.confirmed.name),
            Variable<DateTime>(month),
            Variable<DateTime>(end),
          ],
          readsFrom: {_db.invoices},
        )
        .getSingle();

    final previousSummary = await _db
        .customSelect(
          '''
        SELECT COALESCE(SUM(total_minor), 0) AS total
        FROM invoices
        WHERE deleted_at IS NULL
          AND status = ?
          AND COALESCE(issued_at, created_at) >= ?
          AND COALESCE(issued_at, created_at) < ?
      ''',
          variables: [
            Variable<String>(InvoiceStatus.confirmed.name),
            Variable<DateTime>(previous),
            Variable<DateTime>(month),
          ],
          readsFrom: {_db.invoices},
        )
        .getSingle();

    final categoryRows = await _db
        .customSelect(
          '''
        SELECT COALESCE(category_id, 'other') AS category_id,
               SUM(total_minor) AS total
        FROM invoices
        WHERE deleted_at IS NULL
          AND status = ?
          AND COALESCE(issued_at, created_at) >= ?
          AND COALESCE(issued_at, created_at) < ?
        GROUP BY COALESCE(category_id, 'other')
      ''',
          variables: [
            Variable<String>(InvoiceStatus.confirmed.name),
            Variable<DateTime>(month),
            Variable<DateTime>(end),
          ],
          readsFrom: {_db.invoices},
        )
        .get();

    final dailyRows = await _db
        .customSelect(
          '''
        SELECT CAST(strftime('%d', COALESCE(issued_at, created_at),
                             'unixepoch', 'localtime') AS INTEGER) AS day,
               SUM(total_minor) AS total
        FROM invoices
        WHERE deleted_at IS NULL
          AND status = ?
          AND COALESCE(issued_at, created_at) >= ?
          AND COALESCE(issued_at, created_at) < ?
        GROUP BY day
        ORDER BY day
      ''',
          variables: [
            Variable<String>(InvoiceStatus.confirmed.name),
            Variable<DateTime>(month),
            Variable<DateTime>(end),
          ],
          readsFrom: {_db.invoices},
        )
        .get();

    final budget = await _db
        .customSelect(
          'SELECT COALESCE(SUM(limit_minor), 0) AS total '
          'FROM budgets WHERE month_key = ?',
          variables: [Variable<String>(monthKey)],
          readsFrom: {_db.budgets},
        )
        .getSingle();

    return DashboardSnapshot(
      monthKey: monthKey,
      totalMinor: summary.read<int>('total'),
      invoiceCount: summary.read<int>('invoice_count'),
      previousMonthTotalMinor: previousSummary.read<int>('total'),
      categoryTotals: {
        for (final row in categoryRows)
          row.read<String>('category_id'): row.read<int>('total'),
      },
      dailyTotals: {
        for (final row in dailyRows)
          row.read<int>('day'): row.read<int>('total'),
      },
      budgetLimitMinor: budget.read<int>('total'),
    );
  }

  Future<void> _saveInvoice(
    InvoiceEntity invoice, {
    bool enqueueSync = true,
    InvoiceSyncState syncState = InvoiceSyncState.pending,
    int? revisionOverride,
  }) async {
    final existing = await (_db.select(
      _db.invoices,
    )..where((row) => row.id.equals(invoice.id))).getSingleOrNull();
    final revision =
        revisionOverride ??
        (existing == null
            ? (invoice.revision < 1 ? 1 : invoice.revision)
            : existing.revision + 1);
    final normalizedTags = invoice.tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final stored = invoice.copyWith(
      cloudId: invoice.cloudId ?? existing?.cloudId,
      tags: normalizedTags,
      syncState: syncState,
      revision: revision,
    );

    await _db
        .into(_db.invoices)
        .insertOnConflictUpdate(
          InvoicesCompanion(
            id: Value(stored.id),
            cloudId: Value(stored.cloudId),
            sellerName: Value(stored.sellerName),
            sellerTaxCode: Value(stored.sellerTaxCode),
            invoiceNumber: Value(stored.invoiceNumber),
            invoiceSymbol: Value(stored.invoiceSymbol),
            issuedAt: Value(stored.issuedAt),
            currencyCode: Value(stored.currencyCode),
            subtotalMinor: Value(stored.subtotalMinor),
            taxMinor: Value(stored.taxMinor),
            totalMinor: Value(stored.totalMinor),
            sourceType: Value(stored.sourceType.name),
            sourceHash: Value(stored.sourceHash),
            status: Value(stored.status.name),
            searchText: Value(_searchText(stored)),
            notes: Value(stored.notes),
            tagsJson: Value(jsonEncode(normalizedTags)),
            categoryId: Value(stored.categoryId),
            createdAt: Value(existing?.createdAt ?? stored.createdAt),
            updatedAt: Value(stored.updatedAt),
            confirmedAt: Value(stored.confirmedAt),
            syncState: Value(stored.syncState.name),
            revision: Value(revision),
            deletedAt: Value(stored.deletedAt),
          ),
        );
    await (_db.delete(
      _db.invoiceLines,
    )..where((row) => row.invoiceId.equals(stored.id))).go();
    await (_db.delete(
      _db.fieldEvidences,
    )..where((row) => row.invoiceId.equals(stored.id))).go();
    if (stored.lines.isNotEmpty) {
      await _db.batch((batch) {
        batch.insertAll(
          _db.invoiceLines,
          stored.lines
              .map(
                (line) => InvoiceLinesCompanion.insert(
                  id: line.id,
                  invoiceId: stored.id,
                  description: line.description,
                  quantity: Value(line.quantity),
                  unitPriceMinor: Value(line.unitPriceMinor),
                  taxRate: Value(line.taxRate),
                  totalMinor: line.totalMinor,
                  categoryId: Value(line.categoryId),
                ),
              )
              .toList(growable: false),
        );
      });
    }
    if (stored.evidence.isNotEmpty) {
      await _db.batch((batch) {
        batch.insertAll(
          _db.fieldEvidences,
          stored.evidence
              .map(
                (item) => FieldEvidencesCompanion.insert(
                  id: item.id,
                  invoiceId: stored.id,
                  fieldName: item.fieldName,
                  rawValue: Value(item.rawValue),
                  normalizedValue: item.normalizedValue,
                  sourceType: item.source.name,
                  confidence: item.confidence,
                  correctedByUser: Value(item.correctedByUser),
                ),
              )
              .toList(growable: false),
        );
      });
    }
    if (enqueueSync) {
      await _enqueueSync(
        aggregateId: stored.id,
        operation: 'upsert',
        revision: revision,
        payload: jsonEncode(_syncPayload(stored)),
        now: stored.updatedAt,
      );
    }
  }

  Future<void> _discardRemoteOutbox(String aggregateId, int revision) async {
    await _db.customUpdate(
      '''
      DELETE FROM sync_outbox_events
      WHERE aggregate_type = ?
        AND aggregate_id = ?
        AND revision <= ?
      ''',
      variables: [
        Variable<String>('invoice'),
        Variable<String>(aggregateId),
        Variable<int>(revision),
      ],
      updates: {_db.syncOutboxEvents},
    );
  }

  Future<void> _enqueueSync({
    String aggregateType = 'invoice',
    required String aggregateId,
    required String operation,
    required int revision,
    required String payload,
    required DateTime now,
  }) async {
    await (_db.delete(_db.syncOutboxEvents)..where(
          (row) =>
              row.aggregateType.equals(aggregateType) &
              row.aggregateId.equals(aggregateId) &
              row.state.equals('pending'),
        ))
        .go();
    await _db
        .into(_db.syncOutboxEvents)
        .insert(
          SyncOutboxEventsCompanion.insert(
            id: _uuid.v4(),
            aggregateType: aggregateType,
            aggregateId: aggregateId,
            operation: operation,
            payloadJson: Value(payload),
            revision: revision,
            availableAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  String _searchText(InvoiceEntity invoice) {
    return StringNormalizer.merchant(
      [
        invoice.sellerName,
        invoice.sellerTaxCode,
        invoice.invoiceNumber,
        invoice.invoiceSymbol,
        invoice.notes,
        ...invoice.tags,
      ].whereType<String>().join(' '),
    );
  }

  Map<String, Object?> _syncPayload(InvoiceEntity invoice) => {
    'id': invoice.id,
    'cloudId': invoice.cloudId,
    'sellerName': invoice.sellerName,
    'sellerTaxCode': invoice.sellerTaxCode,
    'invoiceNumber': invoice.invoiceNumber,
    'invoiceSymbol': invoice.invoiceSymbol,
    'issuedAt': invoice.issuedAt?.toIso8601String(),
    'currencyCode': invoice.currencyCode,
    'subtotalMinor': invoice.subtotalMinor,
    'taxMinor': invoice.taxMinor,
    'totalMinor': invoice.totalMinor,
    'sourceType': invoice.sourceType.name,
    'sourceHash': invoice.sourceHash,
    'status': invoice.status.name,
    'categoryId': invoice.categoryId,
    'notes': invoice.notes,
    'tags': invoice.tags,
    'createdAt': invoice.createdAt.toIso8601String(),
    'updatedAt': invoice.updatedAt.toIso8601String(),
    'confirmedAt': invoice.confirmedAt?.toIso8601String(),
    'revision': invoice.revision,
    'deletedAt': invoice.deletedAt?.toIso8601String(),
    'lines': [
      for (final line in invoice.lines)
        {
          'id': line.id,
          'description': line.description,
          'quantity': line.quantity,
          'unitPriceMinor': line.unitPriceMinor,
          'taxRate': line.taxRate,
          'totalMinor': line.totalMinor,
          'categoryId': line.categoryId,
        },
    ],
    'evidence': [
      for (final item in invoice.evidence)
        {
          'id': item.id,
          'fieldName': item.fieldName,
          'rawValue': item.rawValue,
          'normalizedValue': item.normalizedValue,
          'sourceType': item.source.name,
          'confidence': item.confidence,
          'correctedByUser': item.correctedByUser,
        },
    ],
  };

  List<String> _decodeTags(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return const [];
      return decoded.whereType<String>().toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  T _enumByName<T extends Enum>(List<T> values, String name, T fallback) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  static DateTime _parseMonthKey(String monthKey) {
    final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(monthKey);
    if (match == null) throw FormatException('Tháng không hợp lệ: $monthKey');
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    if (month < 1 || month > 12) {
      throw FormatException('Tháng không hợp lệ: $monthKey');
    }
    return DateTime(year, month);
  }
}
