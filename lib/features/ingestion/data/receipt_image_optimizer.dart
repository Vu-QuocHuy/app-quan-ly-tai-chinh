import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

typedef OcrImagePayload = ({Uint8List bytes, String mimeType});

/// Prepares a receipt photo for the OCR request.
///
/// [use1600Profile] is the `ai.extract.image_1600` flag (O2): shrink the long
/// side to 1600 px (JPEG q80), bake EXIF rotation and also shrink files under
/// 2 MB. Off (B0) keeps the behaviour of `main`: files up to 2 MB are sent as
/// they are, larger ones are resized to 2048 px (JPEG q85).
Future<OcrImagePayload> optimizeReceiptImageForOcr(
  Uint8List bytes, {
  required String mimeType,
  bool use1600Profile = false,
}) {
  if (use1600Profile) {
    return compute(_resizeReceiptImage1600, (bytes, mimeType));
  }
  if (bytes.length <= 2 * 1024 * 1024) {
    return Future.value((bytes: bytes, mimeType: mimeType));
  }
  return compute(_resizeReceiptImageLegacy, (bytes, mimeType));
}

OcrImagePayload _resizeReceiptImageLegacy((Uint8List, String) input) {
  final (bytes, mimeType) = input;
  final decoded = image.decodeImage(bytes);
  if (decoded == null) return (bytes: bytes, mimeType: mimeType);

  final oriented = image.bakeOrientation(decoded);
  final longestSide = oriented.width > oriented.height
      ? oriented.width
      : oriented.height;
  if (longestSide <= 2048) return (bytes: bytes, mimeType: mimeType);

  final scale = 2048 / longestSide;
  final resized = image.copyResize(
    oriented,
    width: (oriented.width * scale).round(),
    height: (oriented.height * scale).round(),
    interpolation: image.Interpolation.linear,
  );
  return (
    bytes: Uint8List.fromList(image.encodeJpg(resized, quality: 85)),
    mimeType: 'image/jpeg',
  );
}

OcrImagePayload _resizeReceiptImage1600((Uint8List, String) input) {
  final (bytes, mimeType) = input;
  image.Image? decoded;
  try {
    decoded = image.decodeImage(bytes);
  } on Object {
    return (bytes: bytes, mimeType: mimeType);
  }
  if (decoded == null) return (bytes: bytes, mimeType: mimeType);

  final needsOrientation =
      decoded.exif.imageIfd.orientation != null &&
      decoded.exif.imageIfd.orientation != 1;
  final oriented = image.bakeOrientation(decoded);
  final longestSide = oriented.width > oriented.height
      ? oriented.width
      : oriented.height;
  if (longestSide <= 1600 && !needsOrientation) {
    return (bytes: bytes, mimeType: mimeType);
  }

  final resized = longestSide > 1600
      ? image.copyResize(
          oriented,
          width: (oriented.width * 1600 / longestSide).round(),
          height: (oriented.height * 1600 / longestSide).round(),
          interpolation: image.Interpolation.linear,
        )
      : oriented;
  return (
    bytes: Uint8List.fromList(image.encodeJpg(resized, quality: 80)),
    mimeType: 'image/jpeg',
  );
}
