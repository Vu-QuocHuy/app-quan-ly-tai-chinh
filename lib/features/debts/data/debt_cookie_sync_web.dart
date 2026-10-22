import 'dart:convert';
import 'dart:js_interop';

@JS('_finmiGetCookie')
external JSString _rawFinmiGetCookie(JSString name);

@JS('_finmiSetCookie')
external void _rawFinmiSetCookie(JSString name, JSString value);

const _cookieName = 'finmi_shared_debt_notifs';

List<Map<String, dynamic>> readSharedDebtNotificationsCookie() {
  try {
    final raw = _rawFinmiGetCookie(_cookieName.toJS).toDart;
    if (raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
  } catch (_) {}
  return const [];
}

void writeSharedDebtNotificationsCookie(List<Map<String, dynamic>> items) {
  try {
    final jsonStr = jsonEncode(items);
    _rawFinmiSetCookie(_cookieName.toJS, jsonStr.toJS);
  } catch (_) {}
}
