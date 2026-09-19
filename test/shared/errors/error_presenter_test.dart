import 'dart:io' show SocketException;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/errors/app_exception.dart';
import 'package:hoadon_insight/shared/errors/error_presenter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('friendlyMessage', () {
    test('giữ nguyên câu tiếng Việt của AppException', () {
      expect(
        friendlyMessage(const ValidationException('Số tiền không hợp lệ.')),
        'Số tiền không hợp lệ.',
      );
    });

    test('mất mạng nói rõ dữ liệu vẫn an toàn trên máy', () {
      final message = friendlyMessage(const SocketException('failed'));
      expect(message, contains('Không có kết nối mạng'));
      expect(message, contains('trên máy'));
    });

    test('bóc tiền tố kiểu khỏi FormatException', () {});

    test('bóc tiền tố "Bad state:" khỏi StateError', () {
      expect(
        friendlyMessage(StateError('Cloud sync chưa được cấu hình.')),
        'Cloud sync chưa được cấu hình.',
      );
    });

    test('PlatformException rơi về message của nó', () {
      expect(
        friendlyMessage(
          PlatformException(code: 'x', message: 'Thiết bị từ chối.'),
        ),
        'Thiết bị từ chối.',
      );
    });

    test('lỗi lạ vẫn ra một câu tiếng Việt, không phải chuỗi kiểu', () {
      final message = friendlyMessage(Exception('boom'));
      expect(message, 'Đã có lỗi xảy ra. Hãy thử lại.');
      expect(message, isNot(contains('Exception')));
    });

    test('không hiển thị message thô của Supabase AuthException', () {
      final message = friendlyMessage(
        const AuthException('Email address "secret@example.com" is invalid'),
      );
      expect(
        message,
        'Không thể hoàn tất xác thực. Hãy kiểm tra thông tin và thử lại.',
      );
      expect(message, isNot(contains('secret@example.com')));
    });

    test('không bao giờ để lộ chuỗi kỹ thuật ra UI', () {
      final errors = <Object>[
        const SocketException("Failed host lookup: 'x.supabase.co'"),
        Exception('PostgrestException(message: JWT expired, code: PGRST301)'),
        ArgumentError('null'),
      ];
      for (final error in errors) {
        final message = friendlyMessage(error);
        expect(message, isNot(contains('Exception:')));
        expect(message, isNot(contains('errno')));
        expect(message, isNot(contains('PGRST')));
      }
    });
  });

  group('technicalDetail', () {
    test('giữ đủ chuỗi gốc cho mục "Chi tiết kỹ thuật"', () {
      final detail = technicalDetail(const FormatException('lỗi gốc'));
      expect(detail, contains('lỗi gốc'));
    });

    test('kèm stack trace khi có', () {
      final detail = technicalDetail(
        Exception('x'),
        StackTrace.fromString('#0 main'),
      );
      expect(detail, contains('#0 main'));
    });
  });
}
