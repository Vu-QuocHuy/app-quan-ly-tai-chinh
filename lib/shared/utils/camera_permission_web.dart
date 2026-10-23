import 'dart:js_interop';

@JS('_finmiRequestCameraPermission')
external JSPromise<JSBoolean> _rawRequestCameraPermission();

Future<bool> requestBrowserCameraPermission() async {
  try {
    final promise = _rawRequestCameraPermission();
    final jsBool = await promise.toDart;
    return jsBool.toDart;
  } catch (e) {
    return false;
  }
}
