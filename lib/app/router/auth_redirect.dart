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
/// App yêu cầu cấu hình Supabase và đăng nhập trước khi vào bất kỳ route dữ
/// liệu nào. Sau lần đăng nhập đầu tiên, session đã lưu cho phép mở dữ liệu
/// local khi offline; các thao tác cloud sẽ được thử lại khi có mạng.
String? authRedirect({
  required String location,
  required bool isConfigured,
  required bool isSignedIn,
}) {
  final isAuthRoute = location == '/auth';

  if (!isConfigured) return isAuthRoute ? null : '/auth';

  if (!isSignedIn && !isAuthRoute) return '/auth';

  if (isSignedIn && isAuthRoute) return '/';
  return null;
}
