import 'dart:typed_data';

import 'package:crypto/crypto.dart';

abstract final class SourceHasher {
  static String sha256Of(Uint8List bytes) => sha256.convert(bytes).toString();
}
