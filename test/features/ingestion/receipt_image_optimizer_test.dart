import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/ingestion/data/receipt_image_optimizer.dart';
import 'package:image/image.dart' as image;

void main() {
  test('O2 ON: keeps small receipt images unchanged', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);

    final result = await optimizeReceiptImageForOcr(
      bytes,
      mimeType: 'image/png',
      use1600Profile: true,
    );

    expect(result.bytes, orderedEquals(bytes));
    expect(result.mimeType, 'image/png');
  });

  test('O2 ON: resizes large receipt images to 1600 px and sends JPEG', () async {
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
      use1600Profile: true,
    );
    final decoded = image.decodeImage(result.bytes)!;

    expect(result.mimeType, 'image/jpeg');
    expect(decoded.width, 1600);
    expect(decoded.height, lessThanOrEqualTo(1600));
  });

  test(
    'resizes high resolution images even when the file is under 2 MB',
    () async {
      final bytes = Uint8List.fromList(
        image.encodeJpg(image.Image(width: 2000, height: 1000), quality: 80),
      );
      expect(bytes.length, lessThan(2 * 1024 * 1024));

      final result = await optimizeReceiptImageForOcr(
        bytes,
        mimeType: 'image/jpeg',
        use1600Profile: true,
      );
      expect(image.decodeImage(result.bytes)!.width, 1600);
    },
  );

  test('bakes EXIF orientation on a small image', () async {
    final source = image.Image(width: 1200, height: 800);
    source.exif.imageIfd.orientation = 6;
    final bytes = Uint8List.fromList(image.encodeJpg(source));

    final result = await optimizeReceiptImageForOcr(
      bytes,
      mimeType: 'image/jpeg',
      use1600Profile: true,
    );
    final decoded = image.decodeImage(result.bytes)!;
    expect(decoded.width, 800);
    expect(decoded.height, 1200);
  });

  group('O2 OFF (B0) keeps the behaviour of main', () {
    test('returns the same bytes instance for small images', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);

      final result = await optimizeReceiptImageForOcr(
        bytes,
        mimeType: 'image/png',
      );

      expect(identical(result.bytes, bytes), isTrue);
      expect(result.mimeType, 'image/png');
    });

    test('does not resize a 2000 px image that is under 2 MB', () async {
      final bytes = Uint8List.fromList(
        image.encodeJpg(image.Image(width: 2000, height: 1000), quality: 80),
      );
      expect(bytes.length, lessThan(2 * 1024 * 1024));

      final result = await optimizeReceiptImageForOcr(
        bytes,
        mimeType: 'image/jpeg',
      );

      expect(identical(result.bytes, bytes), isTrue);
    });

    test('resizes a large image to 2048 px', () async {
      final source = image.Image(width: 2400, height: 1800);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          final value =
              (x * 1103515245 + y * 12345 + x * y * 1013904223) & 255;
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
    });
  });
}
