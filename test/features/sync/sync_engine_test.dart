import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/database/app_database.dart';
import 'package:hoadon_insight/features/invoices/data/drift_invoice_repository.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/features/sync/application/sync_engine.dart';
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
