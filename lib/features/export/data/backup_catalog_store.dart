import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum BackupRecordType { json, encrypted, csv, pdf }

class BackupRecord {
  const BackupRecord({
    required this.type,
    required this.fileName,
    required this.createdAt,
  });

  final BackupRecordType type;
  final String fileName;
  final DateTime createdAt;

  String get label => switch (type) {
    BackupRecordType.json => 'JSON đầy đủ',
    BackupRecordType.encrypted => 'Backup mã hóa',
    BackupRecordType.csv => 'CSV',
    BackupRecordType.pdf => 'Báo cáo PDF',
  };

  Map<String, Object?> toJson() => {
    'type': type.name,
    'fileName': fileName,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory BackupRecord.fromJson(Map<String, Object?> json) {
    final rawType = json['type'];
    final fileName = json['fileName'];
    final createdAt = json['createdAt'];
    if (rawType is! String ||
        fileName is! String ||
        fileName.trim().isEmpty ||
        createdAt is! String) {
      throw const FormatException('Metadata backup không hợp lệ.');
    }
    return BackupRecord(
      type: BackupRecordType.values.byName(rawType),
      fileName: fileName,
      createdAt: DateTime.parse(createdAt),
    );
  }
}

class BackupCatalogStore {
  const BackupCatalogStore({this.maxRecords = 20, this.scope});

  static const storageKey = 'backup.catalog.v1';

  final int maxRecords;
  final String? scope;

  String get _storageKey =>
      scope == null ? storageKey : '$storageKey.${scope!.trim()}';

  Future<List<BackupRecord>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final records = <BackupRecord>[];
      for (final item in decoded.whereType<Map>()) {
        try {
          records.add(BackupRecord.fromJson(Map<String, Object?>.from(item)));
        } on Object {
          // Ignore one corrupt history row while preserving the rest.
        }
      }
      records.sort((left, right) => right.createdAt.compareTo(left.createdAt));
      return records.take(maxRecords).toList(growable: false);
    } on Object {
      return const [];
    }
  }

  Future<void> record(BackupRecord record) async {
    final existing = await load();
    final records = [record, ...existing]
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(
        records
            .take(maxRecords)
            .map((item) => item.toJson())
            .toList(growable: false),
      ),
    );
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
  }

  Future<void> clearAll({bool includeLegacy = false}) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
    if (includeLegacy && scope != null) await preferences.remove(storageKey);
  }

  Future<void> prune({Duration retention = const Duration(days: 90)}) async {
    final cutoff = DateTime.now().toUtc().subtract(retention);
    final retained = (await load())
        .where((record) => record.createdAt.toUtc().isAfter(cutoff))
        .take(maxRecords)
        .toList(growable: false);
    final preferences = await SharedPreferences.getInstance();
    if (retained.isEmpty) {
      await preferences.remove(_storageKey);
      return;
    }
    await preferences.setString(
      _storageKey,
      jsonEncode(retained.map((item) => item.toJson()).toList()),
    );
  }
}
