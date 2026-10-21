import 'voice_file_cleanup_stub.dart'
    if (dart.library.io) 'voice_file_cleanup_io.dart'
    as implementation;

Future<void> deleteVoiceFile(String? path) =>
    implementation.deleteVoiceFile(path);
