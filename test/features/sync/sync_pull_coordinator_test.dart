import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/database/app_database.dart';
import 'package:hoadon_insight/features/invoices/data/drift_invoice_repository.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/features/sync/application/sync_pull_coordinator.dart';
import 'package:hoadon_insight/features/sync/data/drift_sync_cursor_store.dart';
import 'package:hoadon_insight/features/sync/domain/sync_gateway.dart';
import 'package:hoadon_insight/features/sync/domain/sync_models.dart';

void main() {
  late AppDatabase database;
  late DriftInvoiceRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftInvoiceRepository(database);
  });

  tearDown(() => database.close());

  test('applies a remote invoice and stores its cursor', () async {
    final gateway = _RecordingPullGateway([
      _change(
        id: 'remote-1',
        revision: 4,
        sellerName: 'Cloud Store',
        updatedAt: DateTime.utc(2026, 8, 31, 1),
      ),
    ]);
    final coordinator = SyncPullCoordinator(
      repository: repository,
      cursors: DriftSyncCursorStore(database),
      gateway: gateway,
    );

    final result = await coordinator.runOnce(userId: 'user-1');

    expect(result.applied, 1);
    expect(result.conflicts, 0);
    expect((await repository.findById('remote-1'))?.sellerName, 'Cloud Store');
    expect(
      (await repository.findById('remote-1'))?.syncState,
      InvoiceSyncState.synced,
    );

    await coordinator.runOnce(userId: 'user-1');
    expect(gateway.cursors.last?.updatedId, 'remote-1');
  });

  test('marks equal-revision divergent content as a conflict', () async {
    final localTime = DateTime.utc(2026, 8, 31, 2);
    await repository.saveInvoice(
      InvoiceEntity(
        id: 'same-revision',
        sellerName: 'Local Store',
        currencyCode: 'VND',
        subtotalMinor: 100,
        taxMinor: 0,
        totalMinor: 100,
        sourceType: InvoiceSourceType.manual,
        status: InvoiceStatus.confirmed,
        createdAt: localTime,
        updatedAt: localTime,
      ),
    );
    final gateway = _RecordingPullGateway([
      _change(
        id: 'same-revision',
        revision: 1,
        sellerName: 'Remote Store',
        updatedAt: localTime,
      ),
    ]);
    final coordinator = SyncPullCoordinator(
      repository: repository,
      cursors: DriftSyncCursorStore(database),
      gateway: gateway,
    );

    final result = await coordinator.runOnce(userId: 'user-1');

    expect(result.conflicts, 1);
    expect(
      (await repository.findById('same-revision'))?.syncState,
      InvoiceSyncState.conflict,
    );
    expect(
      (await repository.findById('same-revision'))?.sellerName,
      'Local Store',
    );
    final conflicts = await repository.watchInvoiceConflicts().first;
    expect(conflicts.single.remote.sellerName, 'Remote Store');
  });

  test('marks equal-revision line category changes as a conflict', () async {
    final localTime = DateTime.utc(2026, 8, 31, 2, 30);
    await repository.saveInvoice(
      InvoiceEntity(
        id: 'line-category-conflict',
        sellerName: 'Local Store',
        currencyCode: 'VND',
        subtotalMinor: 100,
        taxMinor: 0,
        totalMinor: 100,
        sourceType: InvoiceSourceType.manual,
        status: InvoiceStatus.confirmed,
        createdAt: localTime,
        updatedAt: localTime,
        lines: const [
          InvoiceLineEntity(
            id: 'line-1',
            description: 'Coffee',
            totalMinor: 100,
            categoryId: 'food',
          ),
        ],
      ),
    );
    final gateway = _RecordingPullGateway([
      SyncPullChange(
        id: 'line-category-conflict',
        updatedAt: localTime,
        revision: 1,
        payload: {
          'id': 'line-category-conflict',
          'sellerName': 'Local Store',
          'currencyCode': 'VND',
          'subtotalMinor': 100,
          'taxMinor': 0,
          'totalMinor': 100,
          'sourceType': 'manual',
          'status': 'confirmed',
          'createdAt': localTime.toIso8601String(),
          'updatedAt': localTime.toIso8601String(),
          'lines': [
            {
              'id': 'line-1',
              'description': 'Coffee',
              'totalMinor': 100,
              'categoryId': 'shopping',
            },
          ],
          'evidence': <Object?>[],
          'tags': <Object?>[],
        },
      ),
    ]);
    final coordinator = SyncPullCoordinator(
      repository: repository,
      cursors: DriftSyncCursorStore(database),
      gateway: gateway,
    );

    final result = await coordinator.runOnce(userId: 'user-1');

    expect(result.conflicts, 1);
    expect(
      (await repository.findById('line-category-conflict'))?.syncState,
      InvoiceSyncState.conflict,
    );
  });

  test(
    'applies a minimal remote invoice tombstone without creating an outbox event',
    () async {
      final localTime = DateTime.utc(2026, 8, 31, 2);
      final deletedAt = localTime.add(const Duration(minutes: 1));
      await repository.saveInvoice(
        InvoiceEntity(
          id: 'deleted-remotely',
          sellerName: 'Local Store',
          currencyCode: 'VND',
          subtotalMinor: 100,
          taxMinor: 0,
          totalMinor: 100,
          sourceType: InvoiceSourceType.manual,
          status: InvoiceStatus.confirmed,
          createdAt: localTime,
          updatedAt: localTime,
        ),
      );
      final gateway = _RecordingPullGateway([
        SyncPullChange(
          id: 'deleted-remotely',
          updatedAt: deletedAt,
          revision: 2,
          operation: 'delete',
          payload: {
            'id': 'deleted-remotely',
            'deletedAt': deletedAt.toIso8601String(),
          },
        ),
      ]);
      final coordinator = SyncPullCoordinator(
        repository: repository,
        cursors: DriftSyncCursorStore(database),
        gateway: gateway,
      );

      final result = await coordinator.runOnce(userId: 'user-1');

      expect(result.applied, 1);
      expect(await repository.findById('deleted-remotely'), isNull);
      final raw = await database
          .customSelect(
            'SELECT sync_state, revision, deleted_at FROM invoices WHERE id = ?',
            variables: [Variable<String>('deleted-remotely')],
          )
          .getSingle();
      expect(raw.read<String>('sync_state'), 'synced');
      expect(raw.read<int>('revision'), 2);
      expect(raw.read<DateTime>('deleted_at'), isNotNull);
      expect(
        await database
            .customSelect('SELECT COUNT(*) AS count FROM sync_outbox_events')
            .getSingle()
            .then((row) => row.read<int>('count')),
        0,
      );

      await repository.saveRemoteInvoice(
        InvoiceEntity(
          id: 'deleted-remotely',
          sellerName: 'Stale Store',
          currencyCode: 'VND',
          subtotalMinor: 100,
          taxMinor: 0,
          totalMinor: 100,
          sourceType: InvoiceSourceType.manual,
          status: InvoiceStatus.confirmed,
          createdAt: localTime,
          updatedAt: localTime,
          revision: 1,
        ),
      );
      expect(await repository.findById('deleted-remotely'), isNull);
    },
  );

  test(
    'does not create a conflict when only server timestamps differ',
    () async {
      final localTime = DateTime.utc(2026, 8, 31, 2);
      final serverTime = localTime.add(const Duration(minutes: 5));
      await repository.saveInvoice(
        InvoiceEntity(
          id: 'same-content',
          sellerName: 'Same Store',
          currencyCode: 'VND',
          subtotalMinor: 100,
          taxMinor: 0,
          totalMinor: 100,
          sourceType: InvoiceSourceType.manual,
          status: InvoiceStatus.confirmed,
          createdAt: localTime,
          updatedAt: localTime,
        ),
      );
      final gateway = _RecordingPullGateway([
        SyncPullChange(
          id: 'same-content',
          updatedAt: serverTime,
          revision: 1,
          payload: {
            'id': 'same-content',
            'sellerName': 'Same Store',
            'currencyCode': 'VND',
            'subtotalMinor': 100,
            'taxMinor': 0,
            'totalMinor': 100,
            'sourceType': 'manual',
            'status': 'confirmed',
            'createdAt': localTime.toIso8601String(),
            'updatedAt': serverTime.toIso8601String(),
            'lines': <Object?>[],
            'evidence': <Object?>[],
            'tags': <Object?>[],
          },
        ),
      ]);
      final coordinator = SyncPullCoordinator(
        repository: repository,
        cursors: DriftSyncCursorStore(database),
        gateway: gateway,
      );

      final result = await coordinator.runOnce(userId: 'user-1');

      expect(result.conflicts, 0);
      expect(result.applied, 1);
      expect(await repository.watchInvoiceConflicts().first, isEmpty);
    },
  );

  test(
    'applies a remote reference delta without creating a local outbox event',
    () async {
      final gateway = _RecordingPullGateway([
        SyncPullChange(
          id: '1',
          aggregateType: 'category',
          updatedAt: DateTime.utc(2026, 8, 31, 3),
          revision: 1,
          payload: {
            'id': 'remote-category',
            'name': 'Cloud category',
            'iconName': 'category',
            'colorValue': 123,
            'isSystem': false,
          },
        ),
      ]);
      final coordinator = SyncPullCoordinator(
        repository: repository,
        cursors: DriftSyncCursorStore(database),
        gateway: gateway,
        aggregateType: 'category',
      );

      final result = await coordinator.runOnce(userId: 'user-1');

      expect(result.applied, 1);
      expect(
        (await repository.watchCategories().first).map((item) => item.id),
        contains('remote-category'),
      );
      expect(
        await database
            .customSelect('SELECT COUNT(*) AS count FROM sync_outbox_events')
            .getSingle()
            .then((row) => row.read<int>('count')),
        0,
      );
    },
  );

  test('rejects a page whose cursor is not strictly increasing', () async {
    final firstTime = DateTime.utc(2026, 8, 31, 4);
    final gateway = _RecordingPullGateway([
      _change(
        id: 'remote-1',
        revision: 1,
        sellerName: 'First',
        updatedAt: firstTime,
      ),
      _change(
        id: 'remote-2',
        revision: 1,
        sellerName: 'Second',
        updatedAt: firstTime.subtract(const Duration(minutes: 1)),
      ),
    ]);
    final coordinator = SyncPullCoordinator(
      repository: repository,
      cursors: DriftSyncCursorStore(database),
      gateway: gateway,
    );

    await expectLater(
      coordinator.runOnce(userId: 'user-1'),
      throwsA(isA<FormatException>()),
    );
    expect(await repository.findById('remote-1'), isNull);
  });

  test('rejects a reference delta without an entity id', () async {
    final gateway = _RecordingPullGateway([
      SyncPullChange(
        id: '1',
        aggregateType: 'category',
        updatedAt: DateTime.utc(2026, 8, 31, 5),
        revision: 1,
        payload: {'name': 'Missing id'},
      ),
    ]);
    final coordinator = SyncPullCoordinator(
      repository: repository,
      cursors: DriftSyncCursorStore(database),
      gateway: gateway,
      aggregateType: 'category',
    );

    await expectLater(
      coordinator.runOnce(userId: 'user-1'),
      throwsA(isA<FormatException>()),
    );
  });
}

SyncPullChange _change({
  required String id,
  required int revision,
  required String sellerName,
  required DateTime updatedAt,
}) {
  return SyncPullChange(
    id: id,
    updatedAt: updatedAt,
    revision: revision,
    payload: {
      'id': id,
      'sellerName': sellerName,
      'currencyCode': 'VND',
      'subtotalMinor': 100,
      'taxMinor': 0,
      'totalMinor': 100,
      'sourceType': 'manual',
      'status': 'confirmed',
      'createdAt': updatedAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'revision': revision,
      'lines': <Object?>[],
      'evidence': <Object?>[],
      'tags': <Object?>[],
    },
  );
}

class _RecordingPullGateway implements SyncPullGateway {
  _RecordingPullGateway(this.pages);

  final List<SyncPullChange> pages;
  final cursors = <SyncCursor?>[];
  bool _returned = false;

  @override
  bool get isConfigured => true;

  @override
  Future<SyncPullPage> pull({
    required String userId,
    String aggregateType = 'invoice',
    SyncCursor? cursor,
    int limit = 50,
  }) async {
    cursors.add(cursor);
    if (_returned) return const SyncPullPage(changes: [], hasMore: false);
    _returned = true;
    return SyncPullPage(changes: pages, hasMore: false);
  }
}
