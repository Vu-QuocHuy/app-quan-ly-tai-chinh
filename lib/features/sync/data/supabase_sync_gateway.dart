import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'invoice_sync_codec.dart';
import 'reference_sync_codec.dart';
import '../domain/sync_gateway.dart';
import '../domain/sync_models.dart';

typedef SupabaseInvoiceSyncInvoker =
    Future<void> Function({
      required String expectedUserId,
      required String operation,
      required Map<String, dynamic> payload,
      required int revision,
    });

typedef SupabaseReferenceSyncInvoker =
    Future<void> Function({
      required String expectedUserId,
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

typedef SupabaseSyncMetricRecorder =
    Future<void> Function({
      required String direction,
      required String aggregateType,
      required int statusCode,
      required int durationMs,
      required int batchSize,
      String? errorCode,
    });

class SupabaseSyncIdentityProvider implements SyncIdentityProvider {
  const SupabaseSyncIdentityProvider(this._client);

  final SupabaseClient _client;

  @override
  Future<String?> currentUserId() async => _client.auth.currentUser?.id;
}

class SupabaseSyncGateway implements SyncGateway, SyncPullGateway {
  static const _maxSafeInteger = 9007199254740991;

  SupabaseSyncGateway(SupabaseClient client)
    : this.withInvoker(
        currentUserId: () => client.auth.currentUser?.id,
        invoke:
            ({
              required expectedUserId,
              required operation,
              required payload,
              required revision,
            }) async {
              await client.rpc<void>(
                'apply_invoice_sync_checked',
                params: {
                  'p_expected_user_id': expectedUserId,
                  'p_operation': operation,
                  'p_payload': payload,
                  'p_revision': revision,
                },
              );
            },
        invokeReference:
            ({
              required expectedUserId,
              required eventId,
              required aggregateType,
              required operation,
              required payload,
            }) async {
              await client.rpc<void>(
                'apply_reference_sync_checked',
                params: {
                  'p_expected_user_id': expectedUserId,
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
        recordMetric:
            ({
              required direction,
              required aggregateType,
              required statusCode,
              required durationMs,
              required batchSize,
              errorCode,
            }) async {
              await client.rpc<void>(
                'record_sync_request_metric',
                params: {
                  'p_direction': direction,
                  'p_aggregate_type': aggregateType,
                  'p_status_code': statusCode,
                  'p_duration_ms': durationMs,
                  'p_batch_size': batchSize,
                  'p_error_code': errorCode,
                },
              );
            },
      );

  const SupabaseSyncGateway.withInvoker({
    required String? Function() currentUserId,
    required SupabaseInvoiceSyncInvoker invoke,
    SupabaseReferenceSyncInvoker? invokeReference,
    SupabaseDeltaPullInvoker? pull,
    SupabaseSyncMetricRecorder? recordMetric,
  }) : _currentUserId = currentUserId,
       _invoke = invoke,
       _invokeReference = invokeReference,
       _pull = pull,
       _recordMetric = recordMetric ?? _ignoreSyncMetric;

  final String? Function() _currentUserId;
  final SupabaseInvoiceSyncInvoker _invoke;
  final SupabaseReferenceSyncInvoker? _invokeReference;
  final SupabaseDeltaPullInvoker? _pull;
  final SupabaseSyncMetricRecorder _recordMetric;

  @override
  bool get isConfigured => true;

  @override
  Future<void> push(String userId, SyncOutboxEntry entry) async {
    final startedAt = DateTime.now();
    var statusCode = 200;
    try {
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
      if (!isSupportedSyncAggregateType(entry.aggregateType)) {
        throw FormatException('Aggregate không hỗ trợ: ${entry.aggregateType}');
      }
      final payloadId = decoded['id'];
      if (payloadId is! String ||
          payloadId.trim() != entry.aggregateId.trim()) {
        throw const FormatException('Payload đồng bộ không khớp aggregate id.');
      }
      _validatePushPayload(entry, decoded);

      if (entry.aggregateType == 'invoice') {
        await _invoke(
          expectedUserId: userId,
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
        expectedUserId: userId,
        eventId: entry.id,
        aggregateType: entry.aggregateType,
        operation: entry.operation.name,
        payload: decoded,
      );
    } on Object {
      statusCode = 500;
      rethrow;
    } finally {
      await _recordMetricSafely(
        direction: 'push',
        aggregateType: entry.aggregateType,
        statusCode: statusCode,
        durationMs: _durationMs(startedAt),
        batchSize: 1,
        errorCode: statusCode == 200 ? null : 'SYNC_FAILED',
      );
    }
  }

  static void _validatePushPayload(
    SyncOutboxEntry entry,
    Map<String, dynamic> payload,
  ) {
    if (entry.operation == SyncOperation.delete) {
      final deletedAt = payload['deletedAt'];
      if (deletedAt != null &&
          (deletedAt is! String || DateTime.tryParse(deletedAt) == null)) {
        throw const FormatException('Payload xóa đồng bộ không hợp lệ.');
      }
      return;
    }
    switch (entry.aggregateType) {
      case 'invoice':
        InvoiceSyncCodec.fromPayload(payload, revision: entry.revision);
      case 'category':
        ReferenceSyncCodec.categoryFromPayload(payload);
      case 'budget':
        ReferenceSyncCodec.budgetFromPayload(payload);
      case 'merchant_rule':
        ReferenceSyncCodec.merchantRuleFromPayload(payload);
      default:
        throw FormatException('Aggregate không hỗ trợ: ${entry.aggregateType}');
    }
  }

  @override
  Future<SyncPullPage> pull({
    required String userId,
    String aggregateType = 'invoice',
    SyncCursor? cursor,
    int limit = 50,
  }) async {
    final startedAt = DateTime.now();
    var statusCode = 200;
    var batchSize = 0;
    try {
      final authenticatedUserId = _currentUserId();
      if (authenticatedUserId == null || authenticatedUserId != userId) {
        throw const AuthException('Phiên đăng nhập Supabase không hợp lệ.');
      }
      if (!isSupportedSyncAggregateType(aggregateType)) {
        throw FormatException('Aggregate không hỗ trợ: $aggregateType');
      }
      final pull = _pull;
      if (pull == null) {
        throw StateError('Pull gateway chưa được cấu hình.');
      }
      final page = await pull(
        aggregateType: aggregateType,
        cursor: cursor,
        limit: limit.clamp(1, 200),
      );
      batchSize = page.changes.length;
      return page;
    } on Object {
      statusCode = 500;
      rethrow;
    } finally {
      await _recordMetricSafely(
        direction: 'pull',
        aggregateType: aggregateType,
        statusCode: statusCode,
        durationMs: _durationMs(startedAt),
        batchSize: batchSize,
        errorCode: statusCode == 200 ? null : 'SYNC_FAILED',
      );
    }
  }

  Future<void> _recordMetricSafely({
    required String direction,
    required String aggregateType,
    required int statusCode,
    required int durationMs,
    required int batchSize,
    String? errorCode,
  }) async {
    try {
      await _recordMetric(
        direction: direction,
        aggregateType: aggregateType,
        statusCode: statusCode,
        durationMs: durationMs,
        batchSize: batchSize,
        errorCode: errorCode,
      );
    } on Object {
      return;
    }
  }

  static int _durationMs(DateTime startedAt) {
    final duration = DateTime.now().difference(startedAt).inMilliseconds;
    if (duration < 0) return 0;
    if (duration > 600000) return 600000;
    return duration;
  }

  static SyncPullPage _decodePage(
    Object? response, {
    required String aggregateType,
    required int limit,
  }) {
    if (response is! List) {
      throw const FormatException('Delta response không hợp lệ.');
    }
    if (!isSupportedSyncAggregateType(aggregateType)) {
      throw FormatException('Aggregate không hỗ trợ: $aggregateType');
    }
    final normalizedLimit = limit.clamp(1, 200);
    if (response.length > normalizedLimit) {
      throw const FormatException('Delta response vượt quá giới hạn trang.');
    }
    final changes = <SyncPullChange>[];
    for (final raw in response) {
      if (raw is! Map) {
        throw const FormatException('Delta record không hợp lệ.');
      }
      final row = Map<String, dynamic>.from(raw);
      final rawId = row['id'];
      final id = rawId is String ? rawId.trim() : '';
      final rawUpdatedAt = row['updated_at'];
      final updatedAt = rawUpdatedAt is String
          ? DateTime.tryParse(rawUpdatedAt)
          : null;
      final revision = _integer(row['revision']);
      final rawPayload = row['payload'];
      if (id.isEmpty ||
          id.length > 128 ||
          updatedAt == null ||
          revision == null) {
        throw const FormatException('Delta record thiếu cursor.');
      }
      if (revision < 1 || revision > _maxSafeInteger) {
        throw const FormatException('Delta record có revision không hợp lệ.');
      }
      final rowAggregateType = row['aggregate_type'];
      if (rowAggregateType != null && rowAggregateType != aggregateType) {
        throw const FormatException('Delta record sai aggregate.');
      }
      if (rawPayload is! Map) {
        throw const FormatException('Delta payload không hợp lệ.');
      }
      if (rawPayload.keys.any((key) => key is! String)) {
        throw const FormatException('Delta payload không hợp lệ.');
      }
      final payload = Map<String, dynamic>.from(rawPayload);
      if (aggregateType == 'invoice' &&
          payload['id'] != null &&
          (payload['id'] is! String || payload['id'].trim() != id)) {
        throw const FormatException('Delta invoice sai id.');
      }
      final rawOperation = row['operation'];
      final operation = rawOperation ?? 'upsert';
      if (operation is! String) {
        throw const FormatException('Delta operation không hợp lệ.');
      }
      if (operation != 'upsert' && operation != 'delete') {
        throw const FormatException('Delta operation không hợp lệ.');
      }
      changes.add(
        SyncPullChange(
          id: id,
          aggregateType: aggregateType,
          operation: operation,
          updatedAt: updatedAt.toLocal(),
          revision: revision,
          payload: payload,
        ),
      );
    }
    return SyncPullPage(
      changes: List.unmodifiable(changes),
      hasMore: changes.length >= normalizedLimit,
    );
  }

  static int? _integer(Object? value) {
    if (value is int) {
      return value.abs() <= _maxSafeInteger ? value : null;
    }
    if (value is double && value.isFinite && value == value.roundToDouble()) {
      return value.abs() <= _maxSafeInteger ? value.toInt() : null;
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      return parsed != null && parsed.abs() <= _maxSafeInteger ? parsed : null;
    }
    return null;
  }
}

Future<void> _ignoreSyncMetric({
  required String direction,
  required String aggregateType,
  required int statusCode,
  required int durationMs,
  required int batchSize,
  String? errorCode,
}) async {}
