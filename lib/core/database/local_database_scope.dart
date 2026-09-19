import 'package:shared_preferences/shared_preferences.dart';

abstract final class LocalDatabaseScope {
  static const legacyDatabaseName = 'hoadon_insight';
  static const signedOutDatabaseName = 'hoadon_insight_signed_out';

  static const _legacyOwnerKey = 'local_database.legacy_owner.v1';
  static String? _legacyOwnerId;
  static Future<void>? _loadOperation;
  static Future<void>? _bindingOperation;

  static Future<void> initialize({String? userId}) async {
    await _ensureLoaded();
    await bindUser(userId);
  }

  static Future<void> bindUser(String? userId) async {
    final previous = _bindingOperation;
    if (previous != null) await previous;
    if (_legacyOwnerId != null) return;

    final operation = _bindUser(userId);
    _bindingOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_bindingOperation, operation)) _bindingOperation = null;
    }
  }

  static Future<bool> ownsLegacyDatabase(String? userId) async {
    await _ensureLoaded();
    return _legacyOwnerId != null && _normalizeUserId(userId) == _legacyOwnerId;
  }

  static Future<void> releaseLegacyDatabase(String? userId) async {
    await _ensureLoaded();
    if (!await ownsLegacyDatabase(userId)) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_legacyOwnerKey);
    _legacyOwnerId = null;
  }

  static bool isValidUserId(String? userId) => _normalizeUserId(userId) != null;

  static String databaseName({
    required String? userId,
    required bool cloudConfigured,
  }) {
    return databaseNameFor(
      userId: userId,
      cloudConfigured: cloudConfigured,
      legacyOwnerId: _legacyOwnerId,
    );
  }

  static String databaseNameFor({
    required String? userId,
    required bool cloudConfigured,
    required String? legacyOwnerId,
  }) {
    if (!cloudConfigured) return legacyDatabaseName;
    final normalizedUserId = _normalizeUserId(userId);
    if (normalizedUserId == null) return signedOutDatabaseName;
    if (normalizedUserId == _normalizeUserId(legacyOwnerId)) {
      return legacyDatabaseName;
    }
    return 'hoadon_insight_user_${normalizedUserId.replaceAll('-', '')}';
  }

  static Future<void> _bindUser(String? userId) async {
    await _ensureLoaded();
    if (_legacyOwnerId != null) return;
    final normalizedUserId = _normalizeUserId(userId);
    if (normalizedUserId == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_legacyOwnerKey, normalizedUserId);
    _legacyOwnerId = normalizedUserId;
  }

  static Future<void> _ensureLoaded() async {
    final loaded = _loadOperation;
    if (loaded != null) {
      await loaded;
      return;
    }
    final operation = _loadOwner();
    _loadOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_loadOperation, operation)) _loadOperation = null;
    }
  }

  static Future<void> _loadOwner() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _legacyOwnerId = _normalizeUserId(preferences.getString(_legacyOwnerKey));
    } on Object {
      _legacyOwnerId = null;
    }
  }

  static String? _normalizeUserId(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }
}
