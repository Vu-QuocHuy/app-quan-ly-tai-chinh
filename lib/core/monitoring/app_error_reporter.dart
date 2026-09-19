import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../errors/app_exception.dart';

typedef ErrorReportSink = FutureOr<void> Function(AppErrorReport report);

final class AppErrorReport {
  const AppErrorReport({
    required this.source,
    required this.errorType,
    required this.message,
    required this.fatal,
    required this.occurredAt,
    this.stackTrace,
  });

  final String source;
  final String errorType;
  final String message;
  final bool fatal;
  final DateTime occurredAt;
  final String? stackTrace;

  Map<String, Object?> toMap() => {
    'source': source,
    'error_type': errorType,
    'message': message,
    'fatal': fatal,
    'occurred_at': occurredAt.toIso8601String(),
    if (stackTrace != null) 'stack_trace': stackTrace,
  };
}

final class AppErrorReporter {
  AppErrorReporter({ErrorReportSink? sink, DateTime Function()? clock})
    : _sink = sink,
      _clock = clock ?? DateTime.now;

  static final instance = AppErrorReporter();

  ErrorReportSink? _sink;
  final DateTime Function() _clock;
  bool _installed = false;
  FlutterExceptionHandler? _previousFlutterErrorHandler;
  bool Function(Object, StackTrace)? _previousPlatformErrorHandler;

  void configure({ErrorReportSink? sink}) {
    _sink = sink;
  }

  void install() {
    if (_installed) return;
    _installed = true;
    _previousFlutterErrorHandler = FlutterError.onError;
    _previousPlatformErrorHandler = PlatformDispatcher.instance.onError;

    FlutterError.onError = (details) {
      unawaited(
        report(
          details.exception,
          details.stack,
          source: 'flutter',
          fatal: true,
        ),
      );
      final previous = _previousFlutterErrorHandler;
      if (previous != null) {
        previous(details);
      } else {
        assert(() {
          FlutterError.presentError(details);
          return true;
        }());
      }
    };

    PlatformDispatcher.instance.onError = (error, stackTrace) {
      unawaited(report(error, stackTrace, source: 'platform', fatal: true));
      return _previousPlatformErrorHandler?.call(error, stackTrace) ?? false;
    };
  }

  Future<void> report(
    Object error,
    StackTrace? stackTrace, {
    required String source,
    required bool fatal,
  }) async {
    final safeReport = AppErrorReport(
      source: _safeDimension(source),
      errorType: _safeDimension(error.runtimeType.toString()),
      message: safeErrorMessage(error),
      fatal: fatal,
      occurredAt: _clock().toUtc(),
      stackTrace: _safeStackTrace(stackTrace),
    );

    developer.log(
      safeReport.message,
      name: 'hoadon_insight.${safeReport.source}',
      level: fatal ? 1000 : 900,
      stackTrace: safeReport.stackTrace == null
          ? null
          : StackTrace.fromString(safeReport.stackTrace!),
    );

    final sink = _sink;
    if (sink == null) return;
    try {
      await sink(safeReport);
    } catch (sinkError, sinkStackTrace) {
      developer.log(
        'Không thể gửi báo cáo lỗi.',
        name: 'hoadon_insight.monitoring',
        error: safeErrorMessage(sinkError),
        stackTrace: _safeStackTrace(sinkStackTrace) == null
            ? null
            : StackTrace.fromString(_safeStackTrace(sinkStackTrace)!),
      );
    }
  }

  static String _safeDimension(String value) {
    final normalized = value.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    return normalized.length <= 64
        ? normalized
        : '${normalized.substring(0, 61)}...';
  }

  static String? _safeStackTrace(StackTrace? stackTrace) {
    final raw = stackTrace?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    final redacted = raw
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
    if (redacted.isEmpty) return null;
    return redacted.length <= 4_000
        ? redacted
        : '${redacted.substring(0, 3_997)}...';
  }
}
