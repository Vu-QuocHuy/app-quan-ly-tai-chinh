sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
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
