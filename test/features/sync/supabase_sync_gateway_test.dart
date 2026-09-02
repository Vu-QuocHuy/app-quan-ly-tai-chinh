import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:hoadon_insight/features/sync/data/supabase_sync_gateway.dart';
import 'package:hoadon_insight/features/sync/domain/sync_models.dart';

void main() {
  test('sends an invoice event through the atomic RPC', () async {
    String? capturedOperation;
    Map<String, dynamic>? capturedPayload;
    int? capturedRevision;
    final gateway = SupabaseSyncGateway.withInvoker(
      currentUserId: () => 'user-1',
      invoke:
          ({required operation, required payload, required revision}) async {
            capturedOperation = operation;
            capturedPayload = payload;
            capturedRevision = revision;
          },
    );
    final entry = _entry(
      payloadJson: '{"id":"invoice-1","sellerName":"Cửa hàng"}',
    );

    await gateway.push('user-1', entry);

    expect(capturedOperation, 'upsert');
    expect(capturedRevision, 3);
    expect(capturedPayload, containsPair('id', 'invoice-1'));
  });

  test('rejects a mismatched authenticated user', () async {
    var invoked = false;
    final gateway = SupabaseSyncGateway.withInvoker(
      currentUserId: () => 'user-1',
      invoke:
          ({required operation, required payload, required revision}) async {
            invoked = true;
          },
    );

    await expectLater(
      gateway.push('another-user', _entry(payloadJson: '{"id":"x"}')),
      throwsA(isA<AuthException>()),
    );
    expect(invoked, isFalse);
  });

  test('sends reference data through the reference RPC', () async {
    String? capturedType;
    String? capturedOperation;
    Map<String, dynamic>? capturedPayload;
    final gateway = SupabaseSyncGateway.withInvoker(
      currentUserId: () => 'user-1',
      invoke:
          ({required operation, required payload, required revision}) async {},
      invokeReference:
          ({
            required eventId,
            required aggregateType,
            required operation,
            required payload,
          }) async {
            expect(eventId, 'event-1');
            capturedType = aggregateType;
            capturedOperation = operation;
            capturedPayload = payload;
          },
    );

    await gateway.push(
      'user-1',
      _entry(
        aggregateType: 'budget',
        aggregateId: '2026-08-food',
        payloadJson:
            '{"id":"2026-08-food","monthKey":"2026-08",'
            '"categoryId":"food","limitMinor":2000000}',
      ),
    );

    expect(capturedType, 'budget');
    expect(capturedOperation, 'upsert');
    expect(capturedPayload, containsPair('limitMinor', 2000000));
  });
}

SyncOutboxEntry _entry({
  required String payloadJson,
  String aggregateType = 'invoice',
  String aggregateId = 'invoice-1',
}) {
  final now = DateTime(2026, 8, 31);
  return SyncOutboxEntry(
    id: 'event-1',
    aggregateType: aggregateType,
    aggregateId: aggregateId,
    operation: SyncOperation.upsert,
    payloadJson: payloadJson,
    revision: 3,
    state: SyncOutboxState.pending,
    attemptCount: 0,
    availableAt: now,
    createdAt: now,
  );
}
