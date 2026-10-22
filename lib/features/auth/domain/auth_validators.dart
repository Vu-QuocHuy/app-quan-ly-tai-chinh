abstract final class AuthValidators {
  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Hãy nhập email.';
    if (email.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(email)) {
      return 'Email chưa đúng định dạng.';
    }
    final atIndex = email.lastIndexOf('@');
    final localPart = email.substring(0, atIndex);
    final domain = email.substring(atIndex + 1);
    if (localPart.startsWith('.') ||
        localPart.endsWith('.') ||
        localPart.contains('..') ||
        domain.startsWith('.') ||
        domain.endsWith('.') ||
        domain.contains('..')) {
      return 'Email chưa đúng định dạng.';
    }
    return null;
  }

  static String? phone(String? value) {
    final phone = value?.trim() ?? '';
    if (phone.isEmpty) return 'Vui lòng nhập số điện thoại.';
    if (!RegExp(r'^0[0-9]{9}$').hasMatch(phone)) {
      return 'Số điện thoại phải gồm đúng 10 số và bắt đầu bằng 0.';
    }
    return null;
  }
}
