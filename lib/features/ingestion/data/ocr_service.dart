import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  Future<String> recognizeText(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final image = InputImage.fromFilePath(imagePath);
      final result = await recognizer.processImage(image);
      return result.text;
    } finally {
      await recognizer.close();
    }
  }

  Future<List<String>> scanQrPayloads(String imagePath) async {
    final scanner = BarcodeScanner(formats: const [BarcodeFormat.qrCode]);
    try {
      final image = InputImage.fromFilePath(imagePath);
      final results = await scanner.processImage(image);
      return results
          .map((item) => item.rawValue)
          .whereType<String>()
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    } finally {
      await scanner.close();
    }
  }
}
