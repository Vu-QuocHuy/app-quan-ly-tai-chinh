import 'import_coordinator.dart';

enum ImportQueueDecision { completed, deferred }

typedef ImportQueueOutcomeHandler =
    Future<ImportQueueDecision> Function(
      ImportQueueJob job,
      ImportOutcome outcome,
    );

class ImportQueueJob {
  const ImportQueueJob({
    required this.fileName,
    required this.operation,
    this.onCompleted,
    this.onDeferred,
  });

  final String fileName;
  final Future<ImportOutcome> Function() operation;
  final Future<void> Function()? onCompleted;
  final Future<void> Function()? onDeferred;
}

class ImportQueueProgress {
  const ImportQueueProgress({
    required this.currentIndex,
    required this.total,
    required this.completed,
    required this.currentFileName,
    required this.failureCount,
    required this.isRunning,
  });

  final int currentIndex;
  final int total;
  final int completed;
  final String? currentFileName;
  final int failureCount;
  final bool isRunning;

  double get fraction => total == 0 ? 0 : completed / total;
}

class ImportQueueFailure {
  const ImportQueueFailure({required this.job, required this.error});

  final ImportQueueJob job;
  final Object error;
}

class ImportQueueSummary {
  const ImportQueueSummary({
    required this.total,
    required this.succeeded,
    required this.failures,
    this.deferred = 0,
    this.cancelled = false,
  });

  final int total;
  final int succeeded;
  final List<ImportQueueFailure> failures;
  final int deferred;
  final bool cancelled;

  int get failed => failures.length;
}

class ImportQueueController {
  bool _isRunning = false;
  bool _cancelRequested = false;

  bool get isRunning => _isRunning;

  void cancel() {
    if (_isRunning) _cancelRequested = true;
  }

  Future<ImportQueueSummary> run({
    required Iterable<ImportQueueJob> jobs,
    required ImportQueueOutcomeHandler onOutcome,
    required void Function(ImportQueueProgress progress) onProgress,
    void Function(ImportQueueFailure failure)? onFailure,
  }) async {
    if (_isRunning) {
      throw StateError('Hàng đợi import đang được xử lý.');
    }
    final pending = List<ImportQueueJob>.unmodifiable(jobs);
    if (pending.isEmpty) {
      return const ImportQueueSummary(total: 0, succeeded: 0, failures: []);
    }

    _isRunning = true;
    _cancelRequested = false;
    final failures = <ImportQueueFailure>[];
    var succeeded = 0;
    var deferred = 0;
    try {
      for (var index = 0; index < pending.length; index++) {
        if (_cancelRequested) break;
        final job = pending[index];
        _notifyProgress(
          onProgress,
          ImportQueueProgress(
            currentIndex: index + 1,
            total: pending.length,
            completed: succeeded + deferred,
            currentFileName: job.fileName,
            failureCount: failures.length,
            isRunning: true,
          ),
        );
        try {
          final outcome = await job.operation();
          final decision = await onOutcome(job, outcome);
          if (decision == ImportQueueDecision.completed) {
            await job.onCompleted?.call();
            succeeded++;
          } else {
            await job.onDeferred?.call();
            deferred++;
          }
        } on Object catch (error) {
          final failure = ImportQueueFailure(job: job, error: error);
          failures.add(failure);
          _notifyFailure(onFailure, failure);
        }
      }
      _notifyProgress(
        onProgress,
        ImportQueueProgress(
          currentIndex: 0,
          total: pending.length,
          completed: succeeded + deferred,
          currentFileName: null,
          failureCount: failures.length,
          isRunning: false,
        ),
      );
      return ImportQueueSummary(
        total: pending.length,
        succeeded: succeeded,
        deferred: deferred,
        failures: List.unmodifiable(failures),
        cancelled: _cancelRequested,
      );
    } finally {
      _isRunning = false;
    }
  }

  void _notifyProgress(
    void Function(ImportQueueProgress progress) callback,
    ImportQueueProgress progress,
  ) {
    try {
      callback(progress);
    } on Object {
      return;
    }
  }

  void _notifyFailure(
    void Function(ImportQueueFailure failure)? callback,
    ImportQueueFailure failure,
  ) {
    if (callback == null) return;
    try {
      callback(failure);
    } on Object {
      return;
    }
  }
}
