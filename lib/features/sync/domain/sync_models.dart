import 'package:flutter/foundation.dart';

enum SyncOutboxState { pending, sending, sent, failed }

enum SyncOperation { upsert, delete }

@immutable
class SyncOutboxEntry {
  const SyncOutboxEntry({
    required this.id,
    required this.aggregateType,
    required this.aggregateId,
    required this.operation,
    required this.revision,
    required this.state,
    required this.attemptCount,
    required this.availableAt,
    required this.createdAt,
    this.payloadJson,
    this.lastError,
  });

  final String id;
  final String aggregateType;
  final String aggregateId;
  final SyncOperation operation;
  final String? payloadJson;
  final int revision;
  final SyncOutboxState state;
  final int attemptCount;
  final DateTime availableAt;
  final DateTime createdAt;
  final String? lastError;
}

@immutable
class SyncHealth {
  const SyncHealth({
    required this.pendingCount,
    required this.failedCount,
    required this.cloudConfigured,
  });

  final int pendingCount;
  final int failedCount;
  final bool cloudConfigured;

  bool get isHealthy => failedCount == 0;
}

@immutable
class SyncCursor {
  const SyncCursor({this.updatedAt, this.updatedId});

  final DateTime? updatedAt;
  final String? updatedId;
}

@immutable
class SyncPullChange {
  const SyncPullChange({
    required this.id,
    required this.updatedAt,
    required this.revision,
    required this.payload,
    this.aggregateType = 'invoice',
    this.operation = 'upsert',
  });

  final String id;
  final DateTime updatedAt;
  final int revision;
  final Map<String, dynamic> payload;
  final String aggregateType;
  final String operation;

  SyncCursor get cursor => SyncCursor(updatedAt: updatedAt, updatedId: id);
}

@immutable
class SyncPullPage {
  const SyncPullPage({required this.changes, required this.hasMore});

  final List<SyncPullChange> changes;
  final bool hasMore;

  SyncCursor? get cursor => changes.lastOrNull?.cursor;
}

@immutable
class SyncPullResult {
  const SyncPullResult({
    required this.applied,
    required this.skipped,
    required this.conflicts,
    required this.hasMore,
  });

  final int applied;
  final int skipped;
  final int conflicts;
  final bool hasMore;
}
