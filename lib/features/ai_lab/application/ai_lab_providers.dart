import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The assistant message produced by the latest chat turn (AI Lab, debug).
@immutable
final class AiLabAnswer {
  const AiLabAnswer({required this.messageId, required this.text});

  final String messageId;
  final String text;
}

/// A question the AI Lab wants the chat screen to send (control panel preset
/// buttons, batch runner, web bridge). The chat screen sends it and sets the
/// provider back to `null` as soon as it starts handling it.
final aiLabPromptRequestProvider = StateProvider<String?>((ref) => null);

/// Published by the chat screen after every assistant reply in debug builds,
/// so the batch runner can check the answer text.
final aiLabLastAnswerProvider = StateProvider<AiLabAnswer?>((ref) => null);
