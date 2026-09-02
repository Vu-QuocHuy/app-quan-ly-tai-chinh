import '../../../core/errors/app_exception.dart';
import 'extraction.dart';

class InvoiceExtractorRegistry {
  InvoiceExtractorRegistry(Iterable<InvoiceExtractor> extractors)
    : _extractors = List<InvoiceExtractor>.unmodifiable(extractors);

  final List<InvoiceExtractor> _extractors;

  InvoiceExtractor? resolve(ExtractionInput input) {
    for (final extractor in _extractors) {
      if (extractor.canHandle(input)) return extractor;
    }
    return null;
  }

  Future<ExtractionResult> extract(ExtractionInput input) async {
    final extractor = resolve(input);
    if (extractor == null) {
      throw const UnsupportedSourceException(
        'Định dạng file chưa được hỗ trợ.',
      );
    }
    return extractor.extract(input);
  }
}
