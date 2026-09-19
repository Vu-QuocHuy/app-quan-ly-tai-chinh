import 'dart:async';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/database/app_database.dart';
import 'package:hoadon_insight/features/invoices/data/drift_invoice_repository.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/features/sync/application/sync_coordinator.dart';
import 'package:hoadon_insight/features/sync/application/sync_engine.dart';
import 'package:hoadon_insight/features/sync/application/sync_pull_coordinator.dart';
import 'package:hoadon_insight/features/sync/data/drift_sync_cursor_store.dart';
import 'package:hoadon_insight/features/sync/data/drift_sync_outbox_store.dart';
import 'package:hoadon_insight/features/sync/domain/sync_gateway.dart';
import 'package:hoadon_insight/features/sync/domain/sync_models.dart';

void main() {
  late AppDatabase database;
  late DriftInvoiceRepository invoices;
  late DriftSyncOutboxStore outbox;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    invoices = DriftInvoiceRepository(database);
    outbox = DriftSyncOutboxStore(database);
  });

  tearDown(() => database.close());

  test(
    'recovers interrupted entries and marks matching revision synced',
    () async {
      final now = DateTime(2026, 8, 30);
      await invoices.saveInvoice(
        InvoiceEntity(
          id: 'sync-1',
          sellerName: 'Sync Store',
          currencyCode: 'VND',
          subtotalMinor: 100,
          taxMinor: 0,
          totalMinor: 100,
          sourceType: InvoiceSourceType.manual,
          status: InvoiceStatus.confirmed,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final pending = (await outbox.fetchDue()).single;
      await outbox.markSending(pending);
      await database.customUpdate(
        'UPDATE sync_outbox_events SET updated_at = ?',
        variables: [Variable(now.subtract(const Duration(minutes: 11)))],
        updates: {database.syncOutboxEvents},
      );

      final gateway = _RecordingGateway();
      final engine = SyncEngine(
        store: outbox,
        identity: const _Identity(),
        gateway: gateway,
      );
      final result = await engine.runOnce();

      expect(result.pushed, 1);
      expect(result.failed, 0);
      expect(gateway.entries.single.aggregateId, 'sync-1');
      expect(
        (await invoices.findById('sync-1'))?.syncState,
        InvoiceSyncState.synced,
      );
      expect((await outbox.fetchDue()), isEmpty);
    },
  );

  test('keeps entries local when cloud is disabled', () async {
    final engine = SyncEngine(
      store: outbox,
      identity: const DisabledSyncIdentityProvider(),
      gateway: const DisabledSyncGateway(),
    );

    final result = await engine.runOnce();
    expect(result.configured, isFalse);
    expect(result.pushed, 0);
  });

  test('coalesces concurrent sync calls', () async {
    final now = DateTime(2026, 8, 30);
    await invoices.saveInvoice(
      InvoiceEntity(
        id: 'sync-concurrent',
        sellerName: 'Sync Store',
        currencyCode: 'VND',
        subtotalMinor: 100,
        taxMinor: 0,
        totalMinor: 100,
        sourceType: InvoiceSourceType.manual,
        status: InvoiceStatus.confirmed,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final gateway = _BlockingGateway();
    final engine = SyncEngine(
      store: outbox,
      identity: const _Identity(),
      gateway: gateway,
    );

    final first = engine.runOnce();
    await gateway.started.future;
    final second = engine.runOnce();
    gateway.release.complete();
    final results = await Future.wait([first, second]);

    expect(results, hasLength(2));
    expect(results.every((result) => result.pushed == 1), isTrue);
    expect(gateway.entries, hasLength(1));
  });

  test('claims an outbox event atomically across engine instances', () async {
    await invoices.saveInvoice(
      InvoiceEntity(
        id: 'sync-atomic',
        sellerName: 'Sync Store',
        currencyCode: 'VND',
        subtotalMinor: 100,
        taxMinor: 0,
        totalMinor: 100,
        sourceType: InvoiceSourceType.manual,
        status: InvoiceStatus.confirmed,
        createdAt: DateTime(2026, 8, 30),
        updatedAt: DateTime(2026, 8, 30),
      ),
    );
    final gateway = _BlockingGateway();
    final first = SyncEngine(
      store: outbox,
      identity: const _Identity(),
      gateway: gateway,
    );
    final second = SyncEngine(
      store: outbox,
      identity: const _Identity(),
      gateway: gateway,
    );

    final firstRun = first.runOnce();
    await gateway.started.future;
    final secondRun = second.runOnce();
    gateway.release.complete();
    final results = await Future.wait([firstRun, secondRun]);

    expect(results.map((result) => result.pushed).reduce((a, b) => a + b), 1);
    expect(gateway.entries, hasLength(1));
  });

  test('coalesces the full upload and pull cycle', () async {
    final pullGateway = _BlockingPullGateway();
    final pull = SyncPullCoordinator(
      repository: invoices,
      cursors: DriftSyncCursorStore(database),
      gateway: pullGateway,
    );
    final coordinator = SyncCoordinator(
      upload: SyncEngine(
        store: outbox,
        identity: const _Identity(),
        gateway: _RecordingGateway(),
      ),
      identity: const _Identity(),
      download: pull,
    );

    final first = coordinator.runOnce();
    await pullGateway.started.future;
    final second = coordinator.runOnce();
    pullGateway.release.complete();
    final summaries = await Future.wait([first, second]);

    expect(summaries, hasLength(2));
    expect(pullGateway.calls, 1);
  });
}

class _Identity implements SyncIdentityProvider {
  const _Identity();

  @override
  Future<String?> currentUserId() async => 'user-1';
}

class _RecordingGateway implements SyncGateway {
  final entries = <SyncOutboxEntry>[];

  @override
  bool get isConfigured => true;

  @override
  Future<void> push(String userId, SyncOutboxEntry entry) async {
    entries.add(entry);
  }
}

class _BlockingGateway implements SyncGateway {
  final entries = <SyncOutboxEntry>[];
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  bool get isConfigured => true;

  @override
  Future<void> push(String userId, SyncOutboxEntry entry) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    entries.add(entry);
  }
}

class _BlockingPullGateway implements SyncPullGateway {
  final started = Completer<void>();
  final release = Completer<void>();
  var calls = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<SyncPullPage> pull({
    required String userId,
    String aggregateType = 'invoice',
    SyncCursor? cursor,
    int limit = 50,
  }) async {
    calls++;
    if (!started.isCompleted) started.complete();
    await release.future;
    return const SyncPullPage(changes: [], hasMore: false);
  }
}
