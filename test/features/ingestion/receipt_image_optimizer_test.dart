import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/ingestion/data/receipt_image_optimizer.dart';
import 'package:image/image.dart' as image;

void main() {
  test('keeps small receipt images unchanged', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);

    final result = await optimizeReceiptImageForOcr(
      bytes,
      mimeType: 'image/png',
    );

    expect(identical(result.bytes, bytes), isTrue);
    expect(result.mimeType, 'image/png');
  });

  test('resizes large receipt images and sends JPEG', () async {
    final source = image.Image(width: 2400, height: 1800);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final value = (x * 1103515245 + y * 12345 + x * y * 1013904223) & 255;
        source.setPixelRgb(x, y, value, (value * 3) & 255, (value * 7) & 255);
      }
    }
    final bytes = Uint8List.fromList(image.encodeJpg(source, quality: 100));
    expect(bytes.length, greaterThan(2 * 1024 * 1024));

    final result = await optimizeReceiptImageForOcr(
      bytes,
      mimeType: 'image/png',
    );
    final decoded = image.decodeImage(result.bytes)!;

    expect(result.mimeType, 'image/jpeg');
    expect(decoded.width, 2048);
    expect(decoded.height, lessThanOrEqualTo(2048));
  });
}
