import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class QrPayload {
  const QrPayload({required this.rawValue, required this.kind, this.uri});

  final String rawValue;
  final QrPayloadKind kind;
  final Uri? uri;
}

enum QrPayloadKind { url, text }

abstract final class QrPayloadParser {
  static QrPayload parse(String value) {
    final raw = value.trim();
    if (raw.isEmpty) throw const FormatException('QR không chứa dữ liệu.');
    final uri = Uri.tryParse(raw);
    final isHttpUrl =
        uri != null &&
        (uri.scheme.toLowerCase() == 'http' ||
            uri.scheme.toLowerCase() == 'https') &&
        uri.host.isNotEmpty;
    return QrPayload(
      rawValue: raw,
      kind: isHttpUrl ? QrPayloadKind.url : QrPayloadKind.text,
      uri: isHttpUrl ? uri : null,
    );
  }
}

class QrScannerService {
  Future<QrPayload?> scanFile(String filePath) async {
    final scanner = BarcodeScanner(formats: const [BarcodeFormat.qrCode]);
    try {
      final barcodes = await scanner.processImage(
        InputImage.fromFilePath(filePath),
      );
      for (final barcode in barcodes) {
        final rawValue = barcode.rawValue ?? barcode.displayValue;
        if (rawValue == null || rawValue.trim().isEmpty) continue;
        return QrPayloadParser.parse(rawValue);
      }
      return null;
    } finally {
      await scanner.close();
    }
  }
}
