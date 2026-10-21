/// Nội dung QR mời: vào nhóm (mã 8 ký tự) hoặc vào một bill (mã 10 ký tự).
sealed class InviteLink {
  const InviteLink();

  static const _scheme = 'hoadoninsight';
  static const _groupHost = 'join-group';
  static const _billHost = 'join-bill';
  static final _groupCodePattern = RegExp(r'^[0-9A-F]{8}$');
  static final _billCodePattern = RegExp(r'^[0-9A-F]{10}$');

  /// Nhận URI `hoadoninsight://join-group?code=...`,
  /// `hoadoninsight://join-bill?code=...` hoặc mã trơn (8 ký tự là nhóm,
  /// 10 ký tự là bill). Trả `null` khi không phải mã mời hợp lệ.
  static InviteLink? parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri != null && uri.hasScheme) {
      if (uri.scheme != _scheme) return null;
      final code = uri.queryParameters['code'];
      return switch (uri.host) {
        _groupHost => _group(code),
        _billHost => _bill(code),
        _ => null,
      };
    }
    return _group(text) ?? _bill(text);
  }

  static String groupUri(String code) => _uri(_groupHost, code);

  static String billUri(String code) => _uri(_billHost, code);

  static String _uri(String host, String code) => Uri(
    scheme: _scheme,
    host: host,
    queryParameters: {'code': code},
  ).toString();

  static String? _normalize(String? code, RegExp pattern) {
    final normalized = code?.trim().toUpperCase();
    if (normalized == null || !pattern.hasMatch(normalized)) return null;
    return normalized;
  }

  static GroupInviteLink? _group(String? code) {
    final normalized = _normalize(code, _groupCodePattern);
    return normalized == null ? null : GroupInviteLink(normalized);
  }

  static BillInviteLink? _bill(String? code) {
    final normalized = _normalize(code, _billCodePattern);
    return normalized == null ? null : BillInviteLink(normalized);
  }
}

final class GroupInviteLink extends InviteLink {
  const GroupInviteLink(this.code);

  final String code;
}

final class BillInviteLink extends InviteLink {
  const BillInviteLink(this.code);

  final String code;
}
