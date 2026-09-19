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
    final invoiceDownload = await download.runOnce(
      userId: userId,
      batchSize: batchSize,
    );
    final referenceResults = <SyncPullResult>[];
    for (final coordinator in referenceDownloads) {
      referenceResults.add(
        await coordinator.runOnce(userId: userId, batchSize: batchSize),
      );
    }
    return SyncRunSummary(
      upload: upload,
      download: invoiceDownload,
      referenceDownloads: List.unmodifiable(referenceResults),
    );
  }
}
