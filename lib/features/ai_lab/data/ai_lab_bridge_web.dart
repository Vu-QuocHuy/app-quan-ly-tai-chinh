import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('window')
external JSObject get _window;

/// Listens to `window` `message` events and forwards `event.data` (converted
/// to plain Dart objects) with `event.origin`.
void Function() startAiLabBridge(
  void Function(Object? data, String origin) onMessage,
) {
  final JSFunction listener = ((JSObject event) {
    try {
      final origin = event['origin'].dartify();
      final data = event['data'].dartify();
      onMessage(data, origin is String ? origin : '');
    } catch (_) {
      // A malformed message must never crash the app.
    }
  }).toJS;
  _window.callMethodVarArgs('addEventListener'.toJS, ['message'.toJS, listener]);
  return () {
    _window.callMethodVarArgs('removeEventListener'.toJS, [
      'message'.toJS,
      listener,
    ]);
  };
}
