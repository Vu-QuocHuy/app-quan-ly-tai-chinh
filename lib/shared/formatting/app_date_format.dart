import 'package:intl/intl.dart';

/// Định dạng ngày giờ tiếng Việt. Nguồn sự thật duy nhất.
///
/// Thay hai formatter viết tay bằng nội suy chuỗi và bốn literal
/// `DateFormat('dd/MM/yyyy')` rời rạc nằm rải trong các màn hình.
abstract final class AppDateFormat {
  // KHÔNG truyền locale tường minh. `DateFormat` với locale không mặc định ném
  // `LocaleDataException` nếu chưa gọi `initializeDateFormatting(...)` — khác
  // với `NumberFormat`, vốn có sẵn ký hiệu số nên không cần khởi tạo. Trong app
  // thì `GlobalMaterialLocalizations` lo việc đó, nhưng bất kỳ chỗ nào dựng
  // widget mà không có delegate (widget test, hoặc gọi sớm trước khi delegate
  // load xong) sẽ crash.
  //
  // An toàn vì cả hai pattern đều THUẦN SỐ: không tên tháng, không tên thứ,
  // nên locale không làm đổi kết quả.
  static final DateFormat _short = DateFormat('dd/MM/yyyy');
  static final DateFormat _dateTime = DateFormat('dd/MM/yyyy HH:mm');

  /// `04/09/2026`
  static String shortDate(DateTime value) => _short.format(value);

  /// `04/09/2026 14:30`
  static String dateTime(DateTime value) => _dateTime.format(value);

  /// Mô tả tương đối, dùng cho "đồng bộ lần cuối", lịch sử import, xung đột.
  /// Quá 7 ngày thì rơi về ngày tuyệt đối vì lúc đó "38 ngày trước" vô nghĩa.
  static String relative(DateTime value, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final diff = reference.difference(value);

    if (diff.isNegative) return shortDate(value);
    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';
    return shortDate(value);
  }
}
