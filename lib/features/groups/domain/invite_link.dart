/// Nội dung QR mời. Spec B sẽ thêm biến thể cho bill.
sealed class InviteLink {
  const InviteLink();

  static const _scheme = 'hoadoninsight';
  static const _groupHost = 'join-group';
  static final _codePattern = RegExp(r'^[0-9A-F]{8}$');

  /// Nhận URI `hoadoninsight://join-group?code=...` hoặc mã trơn.
  /// Trả `null` khi không phải mã mời hợp lệ.
  static InviteLink? parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri != null && uri.hasScheme) {
      if (uri.scheme != _scheme || uri.host != _groupHost) return null;
      return _group(uri.queryParameters['code']);
    }
    return _group(text);
  }

  static String groupUri(String code) => Uri(
    scheme: _scheme,
    host: _groupHost,
    queryParameters: {'code': code},
  ).toString();

  static GroupInviteLink? _group(String? code) {
    final normalized = code?.trim().toUpperCase();
    if (normalized == null || !_codePattern.hasMatch(normalized)) return null;
    return GroupInviteLink(normalized);
  }
}

final class GroupInviteLink extends InviteLink {
  const GroupInviteLink(this.code);

  final String code;
}
