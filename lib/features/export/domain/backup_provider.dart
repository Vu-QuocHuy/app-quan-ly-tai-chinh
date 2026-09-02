import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

enum BackupArtifactType { json, encrypted, csv, pdf }

class BackupArtifact {
  const BackupArtifact({
    required this.fileName,
    required this.bytes,
    required this.mimeType,
    required this.extension,
    required this.type,
  });

  final String fileName;
  final Uint8List bytes;
  final String mimeType;
  final String extension;
  final BackupArtifactType type;
}

/// Boundary for local files and future user-selected cloud providers.
abstract interface class BackupProvider {
  String get id;

  bool get isConfigured;

  Future<Uri?> save(BackupArtifact artifact);
}

class FilePickerBackupProvider implements BackupProvider {
  const FilePickerBackupProvider();

  @override
  String get id => 'local-file';

  @override
  bool get isConfigured => true;

  @override
  Future<Uri?> save(BackupArtifact artifact) {
    return FilePicker.saveFile(
      dialogTitle: _dialogTitle(artifact.type),
      fileName: artifact.fileName,
      bytes: artifact.bytes,
      mimeType: artifact.mimeType,
      type: FileType.custom,
      allowedExtensions: [artifact.extension],
    );
  }

  String _dialogTitle(BackupArtifactType type) {
    return switch (type) {
      BackupArtifactType.json => 'Xuất dữ liệu hóa đơn JSON',
      BackupArtifactType.encrypted => 'Xuất backup hóa đơn mã hóa',
      BackupArtifactType.csv => 'Xuất dữ liệu hóa đơn CSV',
      BackupArtifactType.pdf => 'Xuất báo cáo chi tiêu PDF',
    };
  }
}
