import 'dart:io' show SocketException;

import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException, StorageException;

import '../../core/errors/app_exception.dart';

/// Biến một object lỗi bất kỳ thành một câu tiếng Việt mà người dùng cuối đọc
/// được. Chuỗi kỹ thuật gốc KHÔNG bao giờ tới UI trực tiếp — `AppErrorState`
/// giấu nó sau ExpansionTile "Chi tiết kỹ thuật".
String friendlyMessage(Object error) {
  // `SqliteException` cố ý nhận diện bằng tên kiểu thay vì import:
  // `sqlite3` chỉ là dependency transitive (qua drift), nên import thẳng sẽ
  // kích hoạt lint `depend_on_referenced_packages` và làm CI đỏ.
  if (error.runtimeType.toString() == 'SqliteException') {
    return 'Không đọc được dữ liệu trên thiết bị. Hãy khởi động lại ứng dụng.';
  }

  return switch (error) {
    // AppException đã mang sẵn văn bản tiếng Việt sạch.
    final AppException e => e.message,

    final SocketException _ =>
      'Không có kết nối mạng. Dữ liệu vẫn được lưu trên máy của bạn.',

    final AuthException e => switch (e.statusCode) {
      '400' => 'Email hoặc mật khẩu chưa đúng.',
      '422' => 'Mật khẩu chưa đủ mạnh. Hãy dùng ít nhất 8 ký tự.',
      '429' => 'Bạn thử quá nhiều lần. Hãy chờ một phút rồi thử lại.',
      _ => e.message,
    },

    final PostgrestException e => switch (e.code) {
      'PGRST301' => 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.',
      '23505' => 'Dữ liệu này đã tồn tại trên máy chủ.',
      _ => 'Máy chủ từ chối yêu cầu. Dữ liệu trên máy không bị ảnh hưởng.',
    },

    final StorageException _ =>
      'Không tải được tệp sao lưu. Hãy kiểm tra kết nối rồi thử lại.',

    final MissingPluginException _ =>
      'Tính năng này chưa hỗ trợ trên nền tảng hiện tại.',

    final PlatformException e => e.message ?? 'Thiết bị từ chối thao tác này.',

    // FormatException và StateError trong repo này đã mang câu tiếng Việt —
    // chỉ cần bóc cái tiền tố kiểu ra.
    final FormatException e => e.message.toString(),
    final StateError e => e.message,

    _ => 'Đã có lỗi xảy ra. Hãy thử lại.',
  };
}

/// Chuỗi kỹ thuật đầy đủ, chỉ hiển thị sau khi người dùng bung
/// "Chi tiết kỹ thuật".
String technicalDetail(Object error, [StackTrace? stack]) =>
    stack == null ? error.toString() : '$error\n\n$stack';
