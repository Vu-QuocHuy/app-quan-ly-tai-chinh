/// Simple energy VAD for native PCM recording. Silence is measured after real
/// speech, never after opening the microphone or an empty transcript.
class VoiceActivity {
  VoiceActivity({this.silence = const Duration(milliseconds: 2500)});
  final Duration silence;
  DateTime? _candidate;
  DateTime? _lastSpeech;
  bool hasSpeech = false;
  bool _finished = false;

  bool sample(double decibels, DateTime now) {
    if (_finished || !decibels.isFinite) return false;
    if (decibels > -40) {
      _candidate ??= now;
      if (now.difference(_candidate!) >= const Duration(milliseconds: 150)) {
        hasSpeech = true;
        _lastSpeech = now;
      }
    } else {
      _candidate = null;
    }
    if (hasSpeech &&
        _lastSpeech != null &&
        now.difference(_lastSpeech!) >= silence) {
      _finished = true;
      return true;
    }
    return false;
  }
}
