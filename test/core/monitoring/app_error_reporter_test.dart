import 'package:flutter_test/flutter_test.dart';

import 'package:hoadon_insight/core/errors/app_exception.dart';
import 'package:hoadon_insight/core/monitoring/app_error_reporter.dart';

void main() {
  test(
    'redacts sensitive fields before invoking the monitoring sink',
    () async {
      final reports = <AppErrorReport>[];
      final reporter = AppErrorReporter(
        sink: reports.add,
        clock: () => DateTime.utc(2026, 9, 17, 12),
      );

      await reporter.report(
        const ValidationException(
          'authorization: Bearer secret-token email test@example.com',
        ),
        StackTrace.fromString(
          'at https://example.com/path token=another-secret test@example.com',
        ),
        source: 'review form',
        fatal: false,
      );

      expect(reports, hasLength(1));
      final report = reports.single;
      expect(report.source, 'review_form');
      expect(report.message, isNot(contains('secret-token')));
      expect(report.message, isNot(contains('test@example.com')));
      expect(report.stackTrace, isNot(contains('another-secret')));
      expect(report.stackTrace, isNot(contains('test@example.com')));
      expect(report.toMap()['fatal'], isFalse);
    },
  );

  test('does not forward raw messages from unknown errors', () async {
    final reports = <AppErrorReport>[];
    final reporter = AppErrorReporter(sink: reports.add);

    await reporter.report(
      StateError('contains private user input'),
      null,
      source: 'test',
      fatal: true,
    );

    expect(reports.single.message, isNot(contains('private user input')));
    expect(reports.single.message, contains('Không thể hoàn tất tác vụ'));
  });
}
