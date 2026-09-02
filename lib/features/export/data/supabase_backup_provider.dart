import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/backup_provider.dart';

class CloudBackupEntry {
  const CloudBackupEntry({
    required this.path,
    required this.fileName,
    required this.createdAt,
    required this.sizeBytes,
  });

  final String path;
  final String fileName;
  final DateTime? createdAt;
  final int? sizeBytes;
}

/// Uploads encrypted backup artifacts to a private, user-scoped bucket.
class SupabaseBackupProvider implements BackupProvider {
  const SupabaseBackupProvider(this._client);

  static const bucketName = 'invoice-backups';

  final SupabaseClient _client;

  @override
  String get id => 'supabase-private-backup';

  @override
  bool get isConfigured => _client.auth.currentSession != null;

  @override
  Future<Uri?> save(BackupArtifact artifact) async {
    final user = _requireUser();
    if (artifact.type != BackupArtifactType.encrypted) {
      throw StateError('Cloud backup chỉ nhận tệp backup đã mã hóa.');
    }

    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final path = '${user.id}/$stamp-${artifact.fileName}';
    await _client.storage
        .from(bucketName)
        .uploadBinary(
          path,
          artifact.bytes,
          fileOptions: FileOptions(
            contentType: artifact.mimeType,
            upsert: false,
          ),
        );
    return Uri(scheme: 'supabase', host: bucketName, path: '/$path');
  }

  Future<List<CloudBackupEntry>> list({int limit = 50}) async {
    final user = _requireUser();
    final files = await _client.storage
        .from(bucketName)
        .list(
          path: user.id,
          searchOptions: SearchOptions(
            limit: limit < 1 ? 1 : (limit > 100 ? 100 : limit),
            sortBy: const SortBy(column: 'created_at', order: 'desc'),
          ),
        );
    return files
        .where((file) => file.name.endsWith('.hdbak'))
        .map(
          (file) => CloudBackupEntry(
            path: '${user.id}/${file.name}',
            fileName: _displayName(file.name),
            createdAt: DateTime.tryParse(file.createdAt ?? ''),
            sizeBytes: (file.metadata?['size'] as num?)?.toInt(),
          ),
        )
        .toList(growable: false);
  }

  Future<Uint8List> download(CloudBackupEntry entry) async {
    _validateOwnedPath(entry.path);
    return _client.storage.from(bucketName).download(entry.path);
  }

  Future<void> delete(CloudBackupEntry entry) async {
    _validateOwnedPath(entry.path);
    await _client.storage.from(bucketName).remove([entry.path]);
  }

  Future<int> prune({
    Duration retention = const Duration(days: 90),
    int maxFiles = 20,
  }) async {
    final entries = await list(limit: 100);
    final cutoff = DateTime.now().toUtc().subtract(retention);
    final paths = <String>[];
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final expired = entry.createdAt?.toUtc().isBefore(cutoff) ?? false;
      if (expired || index >= maxFiles) {
        _validateOwnedPath(entry.path);
        paths.add(entry.path);
      }
    }
    if (paths.isEmpty) return 0;
    await _client.storage.from(bucketName).remove(paths);
    return paths.length;
  }

  User _requireUser() {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Hãy đăng nhập trước khi sử dụng backup Supabase.');
    }
    return user;
  }

  void _validateOwnedPath(String path) {
    final user = _requireUser();
    if (!path.startsWith('${user.id}/') || path.contains('..')) {
      throw StateError('Đường dẫn backup không thuộc tài khoản hiện tại.');
    }
  }

  static String _displayName(String storedName) {
    final separator = storedName.indexOf('-');
    if (separator <= 0 || separator == storedName.length - 1) {
      return storedName;
    }
    final prefix = storedName.substring(0, separator);
    return int.tryParse(prefix) == null
        ? storedName
        : storedName.substring(separator + 1);
  }
}
