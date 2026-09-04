/// Quyết định redirect của router, tách riêng thành một file KHÔNG phụ thuộc
/// widget nào.
///
/// Tách ra vì `app_router.dart` import toàn bộ cây màn hình, nên bất kỳ test
/// nào chạm vào nó cũng kéo theo `pdfrx` — hiện không compile được trên một số
/// phiên bản SDK. Logic cổng đăng nhập là thứ dễ hồi quy nhất trong app, nên nó
/// phải test được mà không cần dựng gì.
///
/// Trả `null` nghĩa là đi thẳng, không redirect.
///
/// App là local-first: OCR, SQLite, import và toàn bộ thống kê chạy offline.
/// Nếu build không có cấu hình cloud — chính là APK mà CI dựng — thì KHÔNG có
/// gì để đăng nhập, nên chặn ở đây làm app không dùng được và mâu thuẫn với
/// lời hứa local-first trong README.
///
/// Có cloud nhưng chưa đăng nhập vẫn dùng được mọi thứ local. Chỉ route THẬT SỰ
/// cần phiên mới bị chặn. Đăng nhập là một banner bỏ được, không phải một bức
/// tường ở màn hình đầu tiên.
String? authRedirect({
  required String location,
  required bool isConfigured,
  required bool isSignedIn,
}) {
  final isAuthRoute = location == '/auth';

  if (!isConfigured) {
    return isAuthRoute ? '/' : null;
  }

  /// `/settings/account` cố ý KHÔNG nằm trong danh sách: nó chính là nơi người
  /// dùng tới để đăng nhập, và nó dựng cùng widget với `/auth`.
  const cloudOnly = {'/settings/conflicts'};
  if (!isSignedIn && cloudOnly.contains(location)) return '/auth';

  if (isSignedIn && isAuthRoute) return '/';
  return null;
}
