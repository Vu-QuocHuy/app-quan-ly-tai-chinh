import 'package:flutter/foundation.dart';

enum ImportJobState {
  queued,
  running,
  awaitingReview,
  succeeded,
  retryScheduled,
  failed,
}

@immutable
class ImportJobEntity {
  const ImportJobEntity({
    required this.id,
    required this.fileName,
    required this.kind,
    required this.state,
    required this.attemptCount,
    required this.maxAttempts,
    required this.createdAt,
    required this.updatedAt,
    this.lastError,
    this.nextRetryAt,
    this.completedAt,
  });

  final String id;
  final String fileName;
  final String kind;
  final ImportJobState state;
  final int attemptCount;
  final int maxAttempts;
  final String? lastError;
  final DateTime? nextRetryAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  bool get canRetry =>
      state == ImportJobState.awaitingReview ||
      state == ImportJobState.failed ||
      state == ImportJobState.retryScheduled;
}
