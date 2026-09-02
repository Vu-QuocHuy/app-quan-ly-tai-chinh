import 'sync_models.dart';

abstract interface class SyncIdentityProvider {
  Future<String?> currentUserId();
}

abstract interface class SyncGateway {
  bool get isConfigured;

  Future<void> push(String userId, SyncOutboxEntry entry);
}

abstract interface class SyncPullGateway {
  bool get isConfigured;

  Future<SyncPullPage> pull({
    required String userId,
    String aggregateType = 'invoice',
    SyncCursor? cursor,
    int limit = 50,
  });
}

class DisabledSyncIdentityProvider implements SyncIdentityProvider {
  const DisabledSyncIdentityProvider();

  @override
  Future<String?> currentUserId() async => null;
}

class DisabledSyncGateway implements SyncGateway {
  const DisabledSyncGateway();

  @override
  bool get isConfigured => false;

  @override
  Future<void> push(String userId, SyncOutboxEntry entry) {
    throw StateError('Cloud sync chưa được cấu hình.');
  }
}
