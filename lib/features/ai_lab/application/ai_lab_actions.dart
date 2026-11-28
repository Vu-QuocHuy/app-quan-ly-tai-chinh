import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Everything the AI Lab control panel and the web bridge can trigger.
abstract interface class AiLabActions {
  /// Sends [text] as a chat question (through `aiLabPromptRequestProvider`).
  Future<void> askPreset(String text);

  /// Imports the bundled sample image at [assetPath] through the normal
  /// receipt import path.
  Future<void> importAsset(String assetPath);

  /// `x-finmi-fault` to inject: `429`, `500`, `timeout` or `null`.
  void setFault(String? fault);

  /// Simulated OCR error: distort the extracted total before validation.
  void setTamperTotal(bool on);

  /// Clears AI Lab state, telemetry and the local chat history. Never deletes
  /// invoices or other user data.
  Future<void> resetLocal();
}

class _NoopAiLabActions implements AiLabActions {
  const _NoopAiLabActions();

  @override
  Future<void> askPreset(String text) async {}

  @override
  Future<void> importAsset(String assetPath) async {}

  @override
  void setFault(String? fault) {}

  @override
  void setTamperTotal(bool on) {}

  @override
  Future<void> resetLocal() async {}
}

/// Placeholder; replaced by the real implementation in the control-panel work.
final aiLabActionsProvider = Provider<AiLabActions>(
  (ref) => const _NoopAiLabActions(),
);
