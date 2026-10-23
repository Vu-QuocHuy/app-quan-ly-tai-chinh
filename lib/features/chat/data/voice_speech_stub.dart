bool isWebSpeechSupported() => false;

void startWebSpeech({
  required String lang,
  required void Function(String text) onResult,
  required void Function(String error) onError,
  required void Function() onEnd,
  required void Function() onSilence,
}) {}

void stopWebSpeech({bool cancel = false}) {}
