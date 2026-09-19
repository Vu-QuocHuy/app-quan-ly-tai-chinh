sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

String safeErrorMessage(Object error) {
  final rawMessage = error is AppException ? error.message.trim() : '';
  if (rawMessage.isEmpty) {
    return 'Không thể hoàn tất tác vụ. Vui lòng thử lại.';
  }

  final redacted = rawMessage
      .replaceAllMapped(
        RegExp(
          r'(authorization|api[_-]?key|access[_-]?token|refresh[_-]?token|service[_-]?role|token)\s*[:=]\s*(?:bearer\s+)?[^\s,;}]+',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)}=[đã ẩn]',
      )
      .replaceAll(
        RegExp(r'bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
        'Bearer [đã ẩn]',
      )
      .replaceAll(
        RegExp(r'https?://[^\s]+', caseSensitive: false),
        '[URL đã ẩn]',
      )
      .replaceAll(
        RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+', caseSensitive: false),
        '[email đã ẩn]',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (redacted.isEmpty) {
    return 'Không thể hoàn tất tác vụ. Vui lòng thử lại.';
  }
  return redacted.length <= 240 ? redacted : '${redacted.substring(0, 237)}...';
}

final class ValidationException extends AppException {
  const ValidationException(super.message, {super.cause});
}

final class UnsupportedSourceException extends AppException {
  const UnsupportedSourceException(super.message, {super.cause});
}

final class ExtractionException extends AppException {
  const ExtractionException(super.message, {super.cause});
}

final class NetworkException extends AppException {
  const NetworkException(super.message, {super.cause});
}
