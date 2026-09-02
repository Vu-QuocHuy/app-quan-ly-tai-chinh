import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

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
    return PendingImport(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      diskName: json['diskName'] as String,
      kind: PendingImportKind.values.byName(json['kind'] as String),
    );
  }

  Map<String, String> toJson() => {
    'id': id,
    'fileName': fileName,
    'diskName': diskName,
    'kind': kind.name,
  };
}

class PendingImportStore {
  PendingImportStore({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  Future<List<PendingImport>> list() async {
    final directory = await _directory();
    final manifest = File('${directory.path}/manifest.json');
    if (!await manifest.exists()) return const [];

    try {
      final decoded = jsonDecode(await manifest.readAsString());
      if (decoded is! List) return const [];
      final items = decoded
          .whereType<Map>()
          .map((item) => PendingImport.fromJson(item.cast<String, dynamic>()))
          .where((item) => File(_filePath(directory, item)).existsSync())
          .toList(growable: false);
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
    final directory = await _directory();
    final item = PendingImport(
      id: _uuid.v4(),
      fileName: fileName,
      diskName: '${_uuid.v4()}.bin',
      kind: kind,
    );
    await File(_filePath(directory, item)).writeAsBytes(bytes, flush: true);
    final items = [...await list(), item];
    await _writeManifest(directory, items);
    return item;
  }

  Future<Uint8List> readBytes(PendingImport item) async {
    final directory = await _directory();
    return File(_filePath(directory, item)).readAsBytes();
  }

  Future<String> filePath(PendingImport item) async {
    final directory = await _directory();
    return _filePath(directory, item);
  }

  Future<void> remove(PendingImport item) async {
    final directory = await _directory();
    final file = File(_filePath(directory, item));
    if (await file.exists()) await file.delete();
    final items = (await list()).where((current) => current.id != item.id);
    await _writeManifest(directory, items);
  }

  Future<Directory> _directory() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/pending-imports');
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

  static String _filePath(Directory directory, PendingImport item) =>
      '${directory.path}/${item.diskName}';
}
