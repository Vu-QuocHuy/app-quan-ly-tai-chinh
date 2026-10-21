import 'package:hoadon_insight/features/sync/application/sync_coordinator.dart';
import 'package:hoadon_insight/features/sync/application/sync_engine.dart';
import 'package:hoadon_insight/features/sync/application/sync_pull_coordinator.dart';

class FakeSyncCoordinator implements SyncCoordinator {
  FakeSyncCoordinator({this.error});

  final Object? error;
  int calls = 0;

  @override
  List<SyncPullCoordinator> get referenceDownloads => const [];

  @override
  Future<SyncRunSummary> runOnce({int batchSize = 50}) async {
    calls++;
    if (error != null) throw error!;
    return const SyncRunSummary(
      upload: SyncRunResult(
        pushed: 0,
        failed: 0,
        configured: true,
        signedIn: true,
      ),
    );
  }
}
