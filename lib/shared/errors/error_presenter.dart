import 'dart:io' show SocketException;

import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException, StorageException;

import '../../core/errors/app_exception.dart';

/// Biến một object lỗi bất kỳ thành một câu tiếng Việt hoặc tiếng Anh mà người dùng cuối đọc
/// được. Chuỗi kỹ thuật gốc KHÔNG bao giờ tới UI trực tiếp — `AppErrorState`
/// giấu nó sau ExpansionTile "Chi tiết kỹ thuật".
String friendlyMessage(Object error, {bool isEn = false}) {
  // `SqliteException` cố ý nhận diện bằng tên kiểu thay vì import:
  // `sqlite3` chỉ là dependency transitive (qua drift), nên import thẳng sẽ
  // kích hoạt lint `depend_on_referenced_packages` và làm CI đỏ.
  if (error.runtimeType.toString() == 'SqliteException') {
    return isEn
        ? 'Could not read local data on device. Please restart the app.'
        : 'Không đọc được dữ liệu trên thiết bị. Hãy khởi động lại ứng dụng.';
  }

  return switch (error) {
    // AppException đã mang sẵn văn bản sạch.
    final AppException e => e.message,

    final SocketException _ =>
      isEn
          ? 'No network connection. Data is still saved on your device.'
          : 'Không có kết nối mạng. Dữ liệu vẫn được lưu trên máy của bạn.',

    final AuthException e => () {
      final msg = e.message.toLowerCase();
      if (msg.contains('unsupported provider') ||
          msg.contains('provider is not enabled') ||
          msg.contains('provider not enabled')) {
        return isEn
            ? 'Google Sign-In is not enabled on Supabase. Please enable Google Provider in Supabase Dashboard.'
            : 'Đăng nhập Google chưa được kích hoạt trên hệ thống máy chủ (Supabase). Vui lòng bật Google Provider trong Supabase Dashboard.';
      }
      return switch (e.statusCode) {
        '400' =>
          isEn
              ? 'Invalid email or password.'
              : 'Email hoặc mật khẩu chưa đúng.',
        '422' =>
          isEn
              ? 'Invalid account information. Please check and try again.'
              : 'Thông tin tài khoản chưa hợp lệ. Hãy kiểm tra và thử lại.',
        '429' =>
          isEn
              ? 'Too many attempts. Please wait a minute and try again.'
              : 'Bạn thử quá nhiều lần. Hãy chờ một phút rồi thử lại.',
        _ =>
          isEn
              ? 'Authentication could not be completed. Please check your info and try again.'
              : 'Không thể hoàn tất xác thực. Hãy kiểm tra thông tin và thử lại.',
      };
    }(),

    final PostgrestException e => switch (e.code) {
      'PGRST301' =>
        isEn
            ? 'Login session expired. Please sign in again.'
            : 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.',
      // UF001: RPC chủ động gửi câu tiếng Việt/thông điệp cho người dùng.
      'UF001' => e.message,
      '23505' =>
        isEn
            ? 'This data already exists on the server.'
            : 'Dữ liệu này đã tồn tại trên máy chủ.',
      _ =>
        isEn
            ? 'Server rejected the request. Local data is not affected.'
            : 'Máy chủ từ chối yêu cầu. Dữ liệu trên máy không bị ảnh hưởng.',
    },

    final StorageException _ =>
      isEn
          ? 'Could not download backup file. Please check connection and try again.'
          : 'Không tải được tệp sao lưu. Hãy kiểm tra kết nối rồi thử lại.',

    final MissingPluginException _ =>
      isEn
          ? 'This feature is not supported on the current platform.'
          : 'Tính năng này chưa hỗ trợ trên nền tảng hiện tại.',

    final PlatformException e =>
      e.message ??
          (isEn
              ? 'Device denied this operation.'
              : 'Thiết bị từ chối thao tác này.'),

    // FormatException và StateError trong repo này đã mang câu tiếng Việt —
    // chỉ cần bóc cái tiền tố kiểu ra.
    final FormatException e => e.message.toString(),
    final StateError e => e.message,

    _ =>
      isEn
          ? 'An error occurred. Please try again.'
          : 'Đã có lỗi xảy ra. Hãy thử lại.',
  };
}

/// Chuỗi kỹ thuật đầy đủ, chỉ hiển thị sau khi người dùng bung
/// "Chi tiết kỹ thuật".
String technicalDetail(Object error, [StackTrace? stack]) =>
    stack == null ? error.toString() : '$error\n\n$stack';
