import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

typedef OcrImagePayload = ({Uint8List bytes, String mimeType});

Future<OcrImagePayload> optimizeReceiptImageForOcr(
  Uint8List bytes, {
  required String mimeType,
}) {
  if (bytes.length <= 2 * 1024 * 1024) {
    return Future.value((bytes: bytes, mimeType: mimeType));
  }
  return compute(_resizeReceiptImage, (bytes, mimeType));
}

OcrImagePayload _resizeReceiptImage((Uint8List, String) input) {
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
