import '../domain/sync_gateway.dart';
import '../domain/sync_models.dart';
import 'sync_engine.dart';
import 'sync_pull_coordinator.dart';

class SyncRunSummary {
  const SyncRunSummary({
    required this.upload,
    this.download,
    this.referenceDownloads = const [],
  });

  final SyncRunResult upload;
  final SyncPullResult? download;
  final List<SyncPullResult> referenceDownloads;

  Iterable<SyncPullResult> get _downloads => [?download, ...referenceDownloads];

  int get applied => _downloads.fold(0, (total, item) => total + item.applied);
  int get skipped => _downloads.fold(0, (total, item) => total + item.skipped);
  int get conflicts =>
      _downloads.fold(0, (total, item) => total + item.conflicts);
  bool get hasMore => _downloads.any((item) => item.hasMore);
}

class SyncCoordinator {
  SyncCoordinator({
    required SyncEngine upload,
    required SyncIdentityProvider identity,
    required SyncPullCoordinator? download,
    this.referenceDownloads = const [],
  }) : _upload = upload,
       _identity = identity,
       _download = download;

  final SyncEngine _upload;
  final SyncIdentityProvider _identity;
  final SyncPullCoordinator? _download;
  final List<SyncPullCoordinator> referenceDownloads;
  Future<SyncRunSummary>? _inFlight;

  Future<SyncRunSummary> runOnce({int batchSize = 50}) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final operation = _runOnce(batchSize: batchSize);
    _inFlight = operation;
    return operation.whenComplete(() {
      if (identical(_inFlight, operation)) _inFlight = null;
    });
  }

  Future<SyncRunSummary> _runOnce({required int batchSize}) async {
    final upload = await _upload.runOnce(batchSize: batchSize);
    if (!upload.configured || !upload.signedIn) {
      return SyncRunSummary(upload: upload);
    }

    final userId = await _identity.currentUserId();
    final download = _download;
    if (userId == null || download == null) {
      return SyncRunSummary(upload: upload);
    }

    // Pull categories first so foreign keys exist for invoices, budgets, and rules.
    SyncPullResult? categoryResult;
    final otherCoordinators = <SyncPullCoordinator>[];
    for (final coordinator in referenceDownloads) {
      if (coordinator.aggregateType == 'category') {
        categoryResult = await coordinator.runOnce(
          userId: userId,
          batchSize: batchSize,
        );
      } else {
        otherCoordinators.add(coordinator);
      }
    }

    // Pull remaining aggregates in parallel to eliminate sequential round-trip latency.
    final parallelDownloads = await Future.wait([
      download.runOnce(userId: userId, batchSize: batchSize),
      ...otherCoordinators.map(
        (coordinator) =>
            coordinator.runOnce(userId: userId, batchSize: batchSize),
      ),
    ]);

    final invoiceDownload = parallelDownloads.first;
    final otherResults = parallelDownloads.sublist(1);

    final referenceResults = <SyncPullResult>[];
    var otherIndex = 0;
    for (final coordinator in referenceDownloads) {
      if (coordinator.aggregateType == 'category') {
        if (categoryResult != null) referenceResults.add(categoryResult);
      } else {
        referenceResults.add(otherResults[otherIndex++]);
      }
    }

    return SyncRunSummary(
      upload: upload,
      download: invoiceDownload,
      referenceDownloads: List.unmodifiable(referenceResults),
    );
  }
}
