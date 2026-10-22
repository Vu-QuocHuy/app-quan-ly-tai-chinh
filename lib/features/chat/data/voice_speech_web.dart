import 'dart:js_interop';

@JS('_finmiSpeechSupported')
external bool _rawFinmiSpeechSupported();

@JS('_finmiStartSpeech')
external void _rawFinmiStartSpeech(
  JSString lang,
  JSFunction onResult,
  JSFunction onError,
  JSFunction onEnd,
);

@JS('_finmiStopSpeech')
external void _rawFinmiStopSpeech();

bool isWebSpeechSupported() {
  try {
    return _rawFinmiSpeechSupported();
  } catch (_) {
    return false;
  }
}

void startWebSpeech({
  required String lang,
  required void Function(String text) onResult,
  required void Function(String error) onError,
  required void Function() onEnd,
}) {
  try {
    _rawFinmiStartSpeech(
      lang.toJS,
      ((JSString text) => onResult(text.toDart)).toJS,
      ((JSString err) => onError(err.toDart)).toJS,
      (() => onEnd()).toJS,
    );
  } catch (e) {
    onError(e.toString());
  }
}

void stopWebSpeech() {
  try {
    _rawFinmiStopSpeech();
  } catch (_) {}
}
