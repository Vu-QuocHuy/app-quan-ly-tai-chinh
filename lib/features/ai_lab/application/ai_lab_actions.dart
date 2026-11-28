import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/monitoring/ai_lab_store.dart';
import '../../../core/monitoring/ai_telemetry.dart';
import '../../../core/providers/app_providers.dart';
import 'ai_lab_import_hook.dart';
import 'ai_lab_providers.dart';

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

  /// Sets the AI optimisation flags of this app instance at runtime. [spec] is
  /// `'b0'` (all off), `'b1'` (all on) or a `Map<String, bool>` keyed by flag
  /// key (unknown keys ignored, absent keys unchanged).
  void setFlags(Object spec);

  /// Clears AI Lab state, telemetry and the local chat history. Never deletes
  /// invoices or other user data.
  Future<void> resetLocal();
}

typedef AiLabAssetLoader = Future<ByteData> Function(String assetPath);

/// Real implementation behind the control panel.
class DefaultAiLabActions implements AiLabActions {
  DefaultAiLabActions(this._ref, {AiLabAssetLoader? loadAsset})
    : _loadAsset = loadAsset ?? rootBundle.load;

  final Ref _ref;
  final AiLabAssetLoader _loadAsset;

  @override
  Future<void> askPreset(String text) async {
    _ref.read(aiLabPromptRequestProvider.notifier).state = text;
  }

  @override
  Future<void> importAsset(String assetPath) async {
    final data = await _loadAsset(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final name = assetPath.split('/').last;
    _ref.read(aiLabImportRequestProvider.notifier).state = XFile.fromData(
      Uint8List.fromList(bytes),
      name: name,
      path: name, // native XFile derives `name` from the path
      mimeType: 'image/png',
    );
  }

  @override
  void setFault(String? fault) => AiLabStore.instance.fault = fault;

  @override
  void setTamperTotal(bool on) => AiLabStore.instance.tamperExtractTotal = on;

  @override
  void setFlags(Object spec) {
    final overrides = _ref.read(aiFlagOverridesProvider);
    switch (spec) {
      case 'b0':
        overrides.setAll(false);
      case 'b1':
        overrides.setAll(true);
      case Map<String, bool>():
        overrides.applyMap(spec);
      default:
        throw ArgumentError.value(spec, 'spec', 'phải là b0, b1 hoặc Map');
    }
  }

  @override
  Future<void> resetLocal() async {
    AiLabStore.instance.reset();
    _ref.read(aiLabPromptRequestProvider.notifier).state = null;
    _ref.read(aiLabLastAnswerProvider.notifier).state = null;
    await AiTelemetry.instance.clear();
    // Local chat history only (`clearAll` never touches the cloud copy).
    // Invoices, incomes and every other preference stay as they are.
    try {
      await _ref
          .read(chatHistoryStoreProvider)
          .clearAll(includeLegacy: true);
    } on Object {
      // Nothing to clear is fine.
    }
  }
}

final aiLabActionsProvider = Provider<AiLabActions>(
  (ref) => DefaultAiLabActions(ref),
);
