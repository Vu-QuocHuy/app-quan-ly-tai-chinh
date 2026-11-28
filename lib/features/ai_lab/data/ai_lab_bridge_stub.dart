/// Non-web platforms have no `window.postMessage`; nothing to listen to.
void Function() startAiLabBridge(
  void Function(Object? data, String origin) onMessage,
) => () {};

/// Non-web platforms have no parent window to post to.
void postAiLabEvent(Map<String, Object?> event, String targetOrigin) {}
