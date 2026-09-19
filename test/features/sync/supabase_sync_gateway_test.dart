import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:hoadon_insight/features/sync/data/supabase_sync_gateway.dart';
import 'package:hoadon_insight/features/sync/domain/sync_models.dart';

void main() {
  test('sends an invoice event through the atomic RPC', () async {
    String? capturedOperation;
    String? capturedExpectedUserId;
    Map<String, dynamic>? capturedPayload;
    int? capturedRevision;
    final gateway = SupabaseSyncGateway.withInvoker(
      currentUserId: () => 'user-1',
      invoke:
          ({
            required expectedUserId,
            required operation,
            required payload,
            required revision,
          }) async {
            capturedExpectedUserId = expectedUserId;
            capturedOperation = operation;
            capturedPayload = payload;
            capturedRevision = revision;
          },
    );
    final entry = _entry(
      payloadJson:
          '{"id":"invoice-1","sellerName":"Cửa hàng",'
          '"currencyCode":"VND","subtotalMinor":100000,"taxMinor":0,'
          '"totalMinor":100000,"sourceType":"manual","status":"confirmed",'
          '"createdAt":"2026-08-31T00:00:00.000Z",'
          '"updatedAt":"2026-08-31T00:00:00.000Z","revision":3}',
    );

    await gateway.push('user-1', entry);

    expect(capturedOperation, 'upsert');
    expect(capturedExpectedUserId, 'user-1');
    expect(capturedRevision, 3);
    expect(capturedPayload, containsPair('id', 'invoice-1'));
  });

  test('rejects a mismatched authenticated user', () async {
    var invoked = false;
    final gateway = SupabaseSyncGateway.withInvoker(
      currentUserId: () => 'user-1',
      invoke:
          ({
            required expectedUserId,
            required operation,
            required payload,
            required revision,
          }) async {
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
          ({
            required expectedUserId,
            required operation,
            required payload,
            required revision,
          }) async {},
      invokeReference:
          ({
            required expectedUserId,
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

  test('rejects unsupported aggregates before invoking Supabase', () async {
    var invoked = false;
    final gateway = SupabaseSyncGateway.withInvoker(
      currentUserId: () => 'user-1',
      invoke:
          ({
            required expectedUserId,
            required operation,
            required payload,
            required revision,
          }) async {
            invoked = true;
          },
    );

    await expectLater(
      gateway.push(
        'user-1',
        _entry(
          aggregateType: 'unknown',
          aggregateId: 'unknown-1',
          payloadJson: '{"id":"unknown-1"}',
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(invoked, isFalse);
  });

  test(
    'rejects a payload whose id differs from the outbox aggregate',
    () async {
      var invoked = false;
      final gateway = SupabaseSyncGateway.withInvoker(
        currentUserId: () => 'user-1',
        invoke:
            ({
              required expectedUserId,
              required operation,
              required payload,
              required revision,
            }) async {
              invoked = true;
            },
      );

      await expectLater(
        gateway.push('user-1', _entry(payloadJson: '{"id":"another-invoice"}')),
        throwsA(isA<FormatException>()),
      );
      expect(invoked, isFalse);
    },
  );

  test('rejects malformed invoice payload before invoking Supabase', () async {
    var invoked = false;
    final gateway = SupabaseSyncGateway.withInvoker(
      currentUserId: () => 'user-1',
      invoke:
          ({
            required expectedUserId,
            required operation,
            required payload,
            required revision,
          }) async {
            invoked = true;
          },
    );

    await expectLater(
      gateway.push(
        'user-1',
        _entry(
          payloadJson:
              '{"id":"invoice-1","sellerName":"Cửa hàng",'
              '"currencyCode":"VND","subtotalMinor":-1}',
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(invoked, isFalse);
  });

  test('records pull telemetry without blocking synchronization', () async {
    String? capturedDirection;
    String? capturedAggregateType;
    int? capturedStatusCode;
    int? capturedBatchSize;
    final gateway = SupabaseSyncGateway.withInvoker(
      currentUserId: () => 'user-1',
      invoke:
          ({
            required expectedUserId,
            required operation,
            required payload,
            required revision,
          }) async {},
      pull: ({required aggregateType, required cursor, required limit}) async {
        return const SyncPullPage(changes: [], hasMore: false);
      },
      recordMetric:
          ({
            required direction,
            required aggregateType,
            required statusCode,
            required durationMs,
            required batchSize,
            errorCode,
          }) async {
            capturedDirection = direction;
            capturedAggregateType = aggregateType;
            capturedStatusCode = statusCode;
            capturedBatchSize = batchSize;
            expect(durationMs, inInclusiveRange(0, 600000));
            expect(errorCode, isNull);
          },
    );

    final result = await gateway.pull(userId: 'user-1');

    expect(result.changes, isEmpty);
    expect(capturedDirection, 'pull');
    expect(capturedAggregateType, 'invoice');
    expect(capturedStatusCode, 200);
    expect(capturedBatchSize, 0);
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
