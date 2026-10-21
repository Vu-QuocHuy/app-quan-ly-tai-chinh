import 'dart:io';

Future<void> deleteVoiceFile(String? path) async {
  if (path == null) return;
  try {
    await File(path).delete();
  } on FileSystemException {
    // The temporary recording may already have been removed by the platform.
  }
}
