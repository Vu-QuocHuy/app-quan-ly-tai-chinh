import 'package:flutter/foundation.dart';

import '../application/ai_lab_actions.dart';
import 'ai_lab_bridge_stub.dart'
    if (dart.library.js_interop) 'ai_lab_bridge_web.dart'
    as implementation;

/// Origins allowed to drive the app through `window.postMessage` (the demo
/// controller page served by `tool/demo/controller`, port 8090).
const Set<String> aiLabAllowedOrigins = {
  'http://localhost:8090',
  'http://127.0.0.1:8090',
};

const int aiLabMaxAskLength = 500;
const String aiLabAssetPrefix = 'assets/ai_lab/';
const Set<String> aiLabFaults = {'429', '500', 'timeout'};

/// A command received from the controller page.
@immutable
sealed class AiLabCommand {
  const AiLabCommand();
}

class AiLabAsk extends AiLabCommand {
  const AiLabAsk(this.text);
  final String text;

  @override
  bool operator ==(Object other) => other is AiLabAsk && other.text == text;

  @override
  int get hashCode => Object.hash('ask', text);
}

class AiLabFault extends AiLabCommand {
  const AiLabFault(this.fault);

  /// `429`, `500`, `timeout` or `null` (no fault).
  final String? fault;

  @override
  bool operator ==(Object other) => other is AiLabFault && other.fault == fault;

  @override
  int get hashCode => Object.hash('fault', fault);
}

class AiLabImportAsset extends AiLabCommand {
  const AiLabImportAsset(this.assetPath);
  final String assetPath;

  @override
  bool operator ==(Object other) =>
      other is AiLabImportAsset && other.assetPath == assetPath;

  @override
  int get hashCode => Object.hash('importAsset', assetPath);
}

class AiLabTamper extends AiLabCommand {
  const AiLabTamper(this.on);
  final bool on;

  @override
  bool operator ==(Object other) => other is AiLabTamper && other.on == on;

  @override
  int get hashCode => Object.hash('tamper', on);
}

class AiLabReset extends AiLabCommand {
  const AiLabReset();

  @override
  bool operator ==(Object other) => other is AiLabReset;

  @override
  int get hashCode => 'reset'.hashCode;
}

/// Parses a `postMessage` payload. Returns `null` for anything that is not a
/// valid command from an allowed origin. Never throws.
AiLabCommand? parseAiLabMessage(Object? data, String origin) {
  try {
    if (!aiLabAllowedOrigins.contains(origin)) return null;
    if (data is! Map) return null;
    final version = data['ailab'];
    if (version is! num || version != 1) return null;
    final cmd = data['cmd'];
    final value = data['value'];
    switch (cmd) {
      case 'ask':
        if (value is! String) return null;
        if (value.trim().isEmpty || value.length > aiLabMaxAskLength) {
          return null;
        }
        return AiLabAsk(value);
      case 'fault':
        if (value == null) return const AiLabFault(null);
        if (value is String && aiLabFaults.contains(value)) {
          return AiLabFault(value);
        }
        return null;
      case 'importAsset':
        if (value is! String) return null;
        if (!value.startsWith(aiLabAssetPrefix) ||
            value.length == aiLabAssetPrefix.length ||
            value.contains('..') ||
            value.contains(r'\')) {
          return null;
        }
        return AiLabImportAsset(value);
      case 'tamper':
        if (value is! bool) return null;
        return AiLabTamper(value);
      case 'reset':
        return const AiLabReset();
      default:
        return null;
    }
  } catch (_) {
    return null;
  }
}

/// Maps a parsed [command] to the matching [AiLabActions] call.
Future<void> runAiLabCommand(AiLabActions actions, AiLabCommand command) {
  switch (command) {
    case AiLabAsk(:final text):
      return actions.askPreset(text);
    case AiLabFault(:final fault):
      actions.setFault(fault);
      return Future<void>.value();
    case AiLabImportAsset(:final assetPath):
      return actions.importAsset(assetPath);
    case AiLabTamper(:final on):
      actions.setTamperTotal(on);
      return Future<void>.value();
    case AiLabReset():
      return actions.resetLocal();
  }
}

/// Starts listening for controller messages. Returns a function that stops the
/// listener. No-op outside the web platform.
void Function() startAiLabBridge(
  void Function(Object? data, String origin) onMessage,
) => implementation.startAiLabBridge(onMessage);
