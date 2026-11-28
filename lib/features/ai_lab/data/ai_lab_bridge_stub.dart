/// Non-web platforms have no `window.postMessage`; nothing to listen to.
void Function() startAiLabBridge(
  void Function(Object? data, String origin) onMessage,
) => () {};
