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

/// Posts [event] to `window.parent` with [targetOrigin], only when the app runs
/// inside an iframe (`window.parent != window`).
void postAiLabEvent(Map<String, Object?> event, String targetOrigin) {
  try {
    final parent = _window['parent'];
    if (parent == null || !parent.isA<JSObject>()) return;
    final parentObject = parent as JSObject;
    if (parentObject.strictEquals(_window).toDart) return;
    parentObject.callMethodVarArgs('postMessage'.toJS, [
      event.jsify(),
      targetOrigin.toJS,
    ]);
  } catch (_) {
    // Cross-origin or detached parent: ignore.
  }
}
