import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/sync_gateway.dart';
import '../domain/sync_models.dart';

typedef SupabaseInvoiceSyncInvoker =
    Future<void> Function({
      required String operation,
      required Map<String, dynamic> payload,
      required int revision,
    });

typedef SupabaseReferenceSyncInvoker =
    Future<void> Function({
      required String eventId,
      required String aggregateType,
      required String operation,
      required Map<String, dynamic> payload,
    });

typedef SupabaseDeltaPullInvoker =
    Future<SyncPullPage> Function({
      required String aggregateType,
      required SyncCursor? cursor,
      required int limit,
    });

class SupabaseSyncIdentityProvider implements SyncIdentityProvider {
  const SupabaseSyncIdentityProvider(this._client);

  final SupabaseClient _client;

  @override
  Future<String?> currentUserId() async => _client.auth.currentUser?.id;
}

class SupabaseSyncGateway implements SyncGateway, SyncPullGateway {
  SupabaseSyncGateway(SupabaseClient client)
    : this.withInvoker(
        currentUserId: () => client.auth.currentUser?.id,
        invoke:
            ({required operation, required payload, required revision}) async {
              await client.rpc<void>(
                'apply_invoice_sync',
                params: {
                  'p_operation': operation,
                  'p_payload': payload,
                  'p_revision': revision,
                },
              );
            },
        invokeReference:
            ({
              required eventId,
              required aggregateType,
              required operation,
              required payload,
            }) async {
              await client.rpc<void>(
                'apply_reference_sync',
                params: {
                  'p_event_id': eventId,
                  'p_aggregate_type': aggregateType,
                  'p_operation': operation,
                  'p_payload': payload,
                },
              );
            },
        pull:
            ({required aggregateType, required cursor, required limit}) async {
              final functionName = aggregateType == 'invoice'
                  ? 'pull_invoice_changes'
                  : 'pull_reference_changes';
              final dynamic response = await client.rpc(
                functionName,
                params: {
                  if (aggregateType != 'invoice')
                    'p_aggregate_type': aggregateType,
                  'p_since': cursor?.updatedAt?.toUtc().toIso8601String(),
                  'p_after_id': cursor?.updatedId,
                  'p_limit': limit,
                },
              );
              if (response is! List) {
                throw const FormatException('Delta response không hợp lệ.');
              }
              return _decodePage(
                response,
                aggregateType: aggregateType,
                limit: limit,
              );
            },
      );

  const SupabaseSyncGateway.withInvoker({
    required String? Function() currentUserId,
    required SupabaseInvoiceSyncInvoker invoke,
    SupabaseReferenceSyncInvoker? invokeReference,
    SupabaseDeltaPullInvoker? pull,
  }) : _currentUserId = currentUserId,
       _invoke = invoke,
       _invokeReference = invokeReference,
       _pull = pull;

  final String? Function() _currentUserId;
  final SupabaseInvoiceSyncInvoker _invoke;
  final SupabaseReferenceSyncInvoker? _invokeReference;
  final SupabaseDeltaPullInvoker? _pull;

  @override
  bool get isConfigured => true;

  @override
  Future<void> push(String userId, SyncOutboxEntry entry) async {
    final authenticatedUserId = _currentUserId();
    if (authenticatedUserId == null || authenticatedUserId != userId) {
      throw const AuthException('Phiên đăng nhập Supabase không hợp lệ.');
    }
    final rawPayload = entry.payloadJson;
    if (rawPayload == null || rawPayload.trim().isEmpty) {
      throw const FormatException('Tác vụ đồng bộ không có payload.');
    }
    final decoded = jsonDecode(rawPayload);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Payload đồng bộ không hợp lệ.');
    }

    if (entry.aggregateType == 'invoice') {
      await _invoke(
        operation: entry.operation.name,
        payload: decoded,
        revision: entry.revision,
      );
      return;
    }
    final invokeReference = _invokeReference;
    if (invokeReference == null) {
      throw UnsupportedError(
        'Chưa hỗ trợ đồng bộ ${entry.aggregateType} lên Supabase.',
      );
    }
    await invokeReference(
      eventId: entry.id,
      aggregateType: entry.aggregateType,
      operation: entry.operation.name,
      payload: decoded,
    );
  }

  @override
  Future<SyncPullPage> pull({
    required String userId,
    String aggregateType = 'invoice',
    SyncCursor? cursor,
    int limit = 50,
  }) async {
    final authenticatedUserId = _currentUserId();
    if (authenticatedUserId == null || authenticatedUserId != userId) {
      throw const AuthException('Phiên đăng nhập Supabase không hợp lệ.');
    }
    final pull = _pull;
    if (pull == null) {
      throw StateError('Pull gateway chưa được cấu hình.');
    }
    return pull(
      aggregateType: aggregateType,
      cursor: cursor,
      limit: limit.clamp(1, 200),
    );
  }

  static SyncPullPage _decodePage(
    Object? response, {
    required String aggregateType,
    required int limit,
  }) {
    if (response is! List) {
      throw const FormatException('Delta response không hợp lệ.');
    }
    final changes = <SyncPullChange>[];
    for (final raw in response) {
      if (raw is! Map) {
        throw const FormatException('Delta record không hợp lệ.');
      }
      final row = Map<String, dynamic>.from(raw);
      final id = '${row['id'] ?? ''}'.trim();
      final updatedAt = DateTime.tryParse('${row['updated_at']}');
      final revision = row['revision'] is num
          ? (row['revision'] as num).toInt()
          : int.tryParse('${row['revision']}');
      final rawPayload = row['payload'];
      if (id.isEmpty || updatedAt == null || revision == null) {
        throw const FormatException('Delta record thiếu cursor.');
      }
      if (rawPayload is! Map) {
        throw const FormatException('Delta payload không hợp lệ.');
      }
      changes.add(
        SyncPullChange(
          id: id,
          aggregateType: aggregateType,
          operation: '${row['operation'] ?? 'upsert'}',
          updatedAt: updatedAt.toLocal(),
          revision: revision,
          payload: Map<String, dynamic>.from(rawPayload),
        ),
      );
    }
    return SyncPullPage(
      changes: List.unmodifiable(changes),
      hasMore: changes.length >= limit,
    );
  }
}
