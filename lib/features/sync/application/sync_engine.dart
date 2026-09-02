import '../data/drift_sync_outbox_store.dart';
import '../domain/sync_gateway.dart';

class SyncRunResult {
  const SyncRunResult({
    required this.pushed,
    required this.failed,
    required this.configured,
    this.signedIn = false,
  });

  final int pushed;
  final int failed;
  final bool configured;
  final bool signedIn;
}

class SyncEngine {
  const SyncEngine({
    required DriftSyncOutboxStore store,
    required SyncIdentityProvider identity,
    required SyncGateway gateway,
  }) : _store = store,
       _identity = identity,
       _gateway = gateway;

  final DriftSyncOutboxStore _store;
  final SyncIdentityProvider _identity;
  final SyncGateway _gateway;

  bool get isConfigured => _gateway.isConfigured;

  Future<SyncRunResult> runOnce({int batchSize = 50}) async {
    if (!_gateway.isConfigured) {
      return const SyncRunResult(pushed: 0, failed: 0, configured: false);
    }
    final userId = await _identity.currentUserId();
    if (userId == null) {
      return const SyncRunResult(pushed: 0, failed: 0, configured: true);
    }

    await _store.recoverInterrupted();
    final entries = await _store.fetchDue(limit: batchSize);
    var pushed = 0;
    var failed = 0;
    for (final entry in entries) {
      await _store.markSending(entry);
      try {
        await _gateway.push(userId, entry);
        await _store.markSent(entry);
        pushed++;
      } on Object catch (error) {
        await _store.markFailed(entry, error);
        failed++;
      }
    }
    await _store.deleteSentBefore(
      DateTime.now().subtract(const Duration(days: 30)),
    );
    return SyncRunResult(
      pushed: pushed,
      failed: failed,
      configured: true,
      signedIn: true,
    );
  }
}
