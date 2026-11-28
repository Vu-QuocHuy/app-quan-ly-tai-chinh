import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

typedef OcrImagePayload = ({Uint8List bytes, String mimeType});

Future<OcrImagePayload> optimizeReceiptImageForOcr(
  Uint8List bytes, {
  required String mimeType,
}) {
  return compute(_resizeReceiptImage, (bytes, mimeType));
}

OcrImagePayload _resizeReceiptImage((Uint8List, String) input) {
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
