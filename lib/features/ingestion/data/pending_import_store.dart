import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';

enum PendingImportKind { document, image }

class PendingImport {
  const PendingImport({
    required this.id,
    required this.fileName,
    required this.diskName,
    required this.kind,
  });

  final String id;
  final String fileName;
  final String diskName;
  final PendingImportKind kind;

  factory PendingImport.fromJson(Map<String, dynamic> json) {
    final item = tryParse(json);
    if (item == null) {
      throw const FormatException('Manifest import không hợp lệ.');
    }
    return item;
  }

  static PendingImport? tryParse(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final fileName = value['fileName'];
    final diskName = value['diskName'];
    final kindName = value['kind'];
    if (id is! String || !_isSafeIdentifier(id)) return null;
    if (fileName is! String || !_isSafeFileName(fileName)) return null;
    if (diskName is! String || !_isSafeDiskName(diskName)) return null;
    if (kindName is! String) return null;
    PendingImportKind kind;
    try {
      kind = PendingImportKind.values.byName(kindName);
    } on ArgumentError {
      return null;
    }
    return PendingImport(
      id: id,
      fileName: fileName,
      diskName: diskName,
      kind: kind,
    );
  }

  static bool _isSafeIdentifier(String value) =>
      value.isNotEmpty &&
      value.length <= 128 &&
      !value.contains('/') &&
      !value.contains('\\') &&
      !value.contains(RegExp(r'[\u0000-\u001F]'));

  static bool _isSafeFileName(String value) =>
      value.isNotEmpty &&
      value.length <= 255 &&
      value != '.' &&
      value != '..' &&
      !value.contains('/') &&
      !value.contains('\\') &&
      !value.contains(RegExp(r'[\u0000-\u001F]'));

  static bool _isSafeDiskName(String value) =>
      value.isNotEmpty &&
      value.length <= 255 &&
      value != '.' &&
      value != '..' &&
      value.endsWith('.bin') &&
      !value.contains('/') &&
      !value.contains('\\') &&
      !value.contains(':') &&
      !value.contains(RegExp(r'[\u0000-\u001F]'));

  Map<String, String> toJson() => {
    'id': id,
    'fileName': fileName,
    'diskName': diskName,
    'kind': kind.name,
  };
}

class PendingImportStore {
  static const maxPendingItems = 100;

  PendingImportStore({
    Uuid? uuid,
    String? scope,
    Future<Directory> Function()? directoryProvider,
  }) : _uuid = uuid ?? const Uuid(),
       _scope = _normalizeScope(scope),
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Uuid _uuid;
  final String? _scope;
  final Future<Directory> Function() _directoryProvider;

  Future<List<PendingImport>> list() {
    return _withMutationLock(_listUnlocked);
  }

  Future<List<PendingImport>> _listUnlocked() async {
    final directory = await _directory();
    final manifest = File('${directory.path}/manifest.json');
    if (!await manifest.exists()) return const [];

    try {
      final decoded = jsonDecode(await manifest.readAsString());
      if (decoded is! List) return const [];
      final items = <PendingImport>[];
      final seenIds = <String>{};
      final seenDiskNames = <String>{};
      for (final raw in decoded) {
        final item = PendingImport.tryParse(raw);
        if (item == null ||
            !seenIds.add(item.id) ||
            !seenDiskNames.add(item.diskName)) {
          continue;
        }
        if (await File(_filePath(directory, item)).exists()) items.add(item);
      }
      if (items.length != decoded.length) {
        await _writeManifest(directory, items);
      }
      return items;
    } on Object {
      return const [];
    }
  }

  Future<PendingImport> enqueue({
    required Uint8List bytes,
    required String fileName,
    required PendingImportKind kind,
  }) async {
    if (bytes.isEmpty || bytes.length > AppConstants.maxImportBytes) {
      throw const FileSystemException(
        'File import phải có kích thước từ 1 đến 15 MB.',
      );
    }
    if (!PendingImport._isSafeFileName(fileName)) {
      throw const FileSystemException('Tên file import không hợp lệ.');
    }
    return _withMutationLock(() async {
      final directory = await _directory();
      final existingItems = await _listUnlocked();
      if (existingItems.length >= maxPendingItems) {
        throw const FileSystemException('Hàng đợi import đã đạt giới hạn.');
      }
      final item = PendingImport(
        id: _uuid.v4(),
        fileName: fileName,
        diskName: '${_uuid.v4()}.bin',
        kind: kind,
      );
      final file = File(_filePath(directory, item));
      await file.writeAsBytes(bytes, flush: true);
      try {
        final items = [...existingItems, item];
        await _writeManifest(directory, items);
      } on Object {
        if (await file.exists()) await file.delete();
        rethrow;
      }
      return item;
    });
  }

  Future<Uint8List> readBytes(PendingImport item) async {
    final directory = await _directory();
    final file = File(_filePath(directory, item));
    final size = await file.length();
    if (size == 0 || size > AppConstants.maxImportBytes) {
      throw const FileSystemException('File import tạm không hợp lệ.');
    }
    return file.readAsBytes();
  }

  Future<String> filePath(PendingImport item) async {
    final directory = await _directory();
    return _filePath(directory, item);
  }

  Future<void> remove(PendingImport item) async {
    await _withMutationLock(() async {
      final directory = await _directory();
      final file = File(_filePath(directory, item));
      if (await file.exists()) await file.delete();
      final items = (await _listUnlocked()).where(
        (current) => current.id != item.id,
      );
      await _writeManifest(directory, items);
    });
  }

  Future<void> clear() async {
    await _withMutationLock(() async {
      final directory = await _directory();
      final lock = File('${directory.path}/.manifest.lock');
      await for (final entity in directory.list()) {
        if (entity is File && entity.path != lock.path) await entity.delete();
      }
    });
  }

  Future<void> clearAll({bool includeLegacy = false}) async {
    await clear();
    if (includeLegacy && _scope != null) {
      await PendingImportStore(directoryProvider: _directoryProvider).clear();
    }
  }

  Future<T> _withMutationLock<T>(Future<T> Function() operation) async {
    final directory = await _directory();
    final lock = File('${directory.path}/.manifest.lock');
    var acquired = false;
    for (var attempt = 0; attempt < 120; attempt++) {
      try {
        await lock.create(exclusive: true);
        acquired = true;
        break;
      } on FileSystemException {
        if (await lock.exists()) {
          final modified = await lock.lastModified();
          if (DateTime.now().difference(modified) >
              const Duration(seconds: 30)) {
            await lock.delete();
            continue;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    if (!acquired) {
      throw const FileSystemException('Không khóa được hàng đợi import.');
    }
    try {
      return await operation();
    } finally {
      if (await lock.exists()) await lock.delete();
    }
  }

  Future<Directory> _directory() async {
    final root = await _directoryProvider();
    final directory = Directory(
      _scope == null
          ? '${root.path}/pending-imports'
          : '${root.path}/pending-imports/$_scope',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> _writeManifest(
    Directory directory,
    Iterable<PendingImport> items,
  ) async {
    final manifest = File('${directory.path}/manifest.json');
    final temporary = File('${directory.path}/manifest.json.tmp');
    await temporary.writeAsString(
      jsonEncode(items.map((item) => item.toJson()).toList(growable: false)),
      flush: true,
    );
    await temporary.rename(manifest.path);
  }

  static String _filePath(Directory directory, PendingImport item) {
    if (!PendingImport._isSafeDiskName(item.diskName)) {
      throw ArgumentError.value(item.diskName, 'diskName');
    }
    return '${directory.path}/${item.diskName}';
  }

  static String? _normalizeScope(String? value) {
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
