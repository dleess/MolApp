import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'molstar_bridge.dart';

/// Asset path of the shared web core, synced from ../MolApp/Resources by tool/sync_web_assets.dart.
const String kViewerAssetPath = 'assets/web/viewer.html';

/// Name of the JS→Dart handler. viewer.html never sees it: it posts through the generic
/// `window.molappPostMessage` hook installed by [_bridgeUserScript].
const String _handlerName = 'molapp';

/// Installed before viewer.html's own script runs, so `postToNative` finds a transport on its very
/// first call (the fatal-init error path can fire before anything else).
///
/// Messages posted before the plugin's JS bridge exists are buffered in `__molappOut` and drained
/// either by the next post or by [MolStarWebView._drainPendingMessages] after load — `viewerReady`
/// is posted once and must not be lost to a race.
const String _bridgeUserScriptSource = '''
(function () {
  window.__molappOut = window.__molappOut || [];
  window.molappPostMessage = function (payload) {
    var bridge = window.flutter_inappwebview;
    if (bridge && typeof bridge.callHandler === 'function') {
      while (window.__molappOut.length) {
        bridge.callHandler('$_handlerName', window.__molappOut.shift());
      }
      bridge.callHandler('$_handlerName', payload);
    } else {
      window.__molappOut.push(payload);
    }
  };

  // Cursor tracking for the hover tooltip. The label itself already comes from Mol*'s own hover
  // subscription; this only supplies where to draw it. Touch is excluded — a finger drag is a
  // camera rotation, not a hover.
  var lastPost = 0;
  document.addEventListener('pointermove', function (e) {
    if (e.pointerType === 'touch') return;
    if (e.timeStamp - lastPost < 32) return;
    lastPost = e.timeStamp;
    window.molappPostMessage(JSON.stringify({ event: 'hoverPoint', x: e.clientX, y: e.clientY }));
  }, { passive: true, capture: true });

  document.addEventListener('pointerleave', function (e) {
    if (e.pointerType === 'touch') return;
    window.molappPostMessage(JSON.stringify({ event: 'hoverPoint', x: null, y: null }));
  }, { passive: true, capture: true });
})();
''';

/// Settings for the viewer webview. The Mol* canvas owns every gesture: no page scrolling,
/// bouncing or double-tap zoom.
///
/// On Android the plugin implements `disable*Scroll` with an `OnTouchListener` that consumes every
/// `ACTION_MOVE` when both are set (InAppWebView.java), so the page never receives `touchmove` and
/// one-finger rotation is dead. viewer.html already pins scrolling itself (`overflow: hidden`,
/// `touch-action: none`, `user-scalable=no`), so Android skips the flags.
@visibleForTesting
InAppWebViewSettings viewerWebViewSettings() {
  final isAndroid = defaultTargetPlatform == TargetPlatform.android;
  return InAppWebViewSettings(
    isInspectable: kDebugMode,
    disableVerticalScroll: !isAndroid,
    disableHorizontalScroll: !isAndroid,
    disallowOverScroll: true,
    supportZoom: false,
    builtInZoomControls: false,
    javaScriptCanOpenWindowsAutomatically: false,
    allowsBackForwardNavigationGestures: false,
    // molstar.js is loaded relative to viewer.html on a file:// URL.
    allowFileAccessFromFileURLs: true,
    allowUniversalAccessFromFileURLs: true,
    transparentBackground: false,
  );
}

/// The Mol* viewport. Hosts viewer.html in the platform webview and wires it to [bridge].
class MolStarWebView extends StatefulWidget {
  const MolStarWebView({super.key, required this.bridge});

  final MolStarBridge bridge;

  @override
  State<MolStarWebView> createState() => _MolStarWebViewState();
}

class _MolStarWebViewState extends State<MolStarWebView> {
  /// Bumped when the Android renderer dies. Reloading the page in the same WebView leaves the
  /// plugin's JS bridge broken (`_javaInjectedObject._callHandler is not a function`), so the key
  /// change tears the dead platform view down and builds a fresh one, bridge included.
  int _rebuildEpoch = 0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Apple Pencil hover does not reach JS inside a webview, so forward it from Flutter. On
      // platforms where the platform view swallows hover this is simply never called, and the
      // injected pointermove listener covers the mouse case instead.
      onPointerHover: (event) {
        if (event.kind != PointerDeviceKind.stylus &&
            event.kind != PointerDeviceKind.invertedStylus) {
          return;
        }
        widget.bridge.updateHoverPoint(event.localPosition);
        widget.bridge.sendHover(event.localPosition.dx, event.localPosition.dy);
      },
      child: InAppWebView(
        key: ValueKey<int>(_rebuildEpoch),
        initialFile: kViewerAssetPath,
        initialSettings: viewerWebViewSettings(),
        initialUserScripts: UnmodifiableListView<UserScript>(<UserScript>[
          UserScript(
            source: _bridgeUserScriptSource,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        ]),
        // Without this the Flutter gesture arena wins on Android/iOS and one-finger rotate,
        // two-finger pan and pinch never reach Mol*.
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
        },
        onWebViewCreated: (controller) {
          controller.addJavaScriptHandler(
            handlerName: _handlerName,
            callback: (args) {
              if (args.isNotEmpty) _handleRawMessage(args.first);
              return null;
            },
          );
          widget.bridge.attach(_InAppWebViewJsRunner(controller));
        },
        onLoadStop: (controller, url) => _drainPendingMessages(controller),
        onReceivedError: (controller, request, error) {
          // Sub-resource failures (a missing icon) must not blank the viewer.
          if (request.isForMainFrame != true) return;
          widget.bridge.reportError('Viewer failed to load: ${error.description}');
        },
        onConsoleMessage: (_, message) {
          if (kDebugMode) debugPrint('[viewer] ${message.message}');
        },
        onWebContentProcessDidTerminate: (controller) {
          // The viewer's JS is gone, so it cannot report its own death. Reload from the asset
          // rather than reload(): after a crash every command sent meanwhile would hit a dead page.
          widget.bridge.attach(_InAppWebViewJsRunner(controller));
          controller.loadFile(assetFilePath: kViewerAssetPath);
        },
        onRenderProcessGone: (controller, detail) {
          // Android's counterpart of the callback above. Registering it flips the plugin's
          // useOnRenderProcessGone setting; without it a dead renderer (OOM on keyboard resize
          // of the WebGL canvas, or a WebView update) makes Android kill the whole app.
          setState(() => _rebuildEpoch++);
        },
      ),
    );
  }

  Future<void> _drainPendingMessages(InAppWebViewController controller) async {
    final raw = await controller.evaluateJavascript(
      source: '(function () {'
          ' var q = window.__molappOut || []; window.__molappOut = [];'
          ' return JSON.stringify(q); })()',
    );
    if (raw is! String || raw.isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is! List) return;
    for (final message in decoded) {
      _handleRawMessage(message);
    }
  }

  void _handleRawMessage(Object? raw) {
    Map<String, dynamic>? message;
    if (raw is String) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) message = decoded.cast<String, dynamic>();
    } else if (raw is Map) {
      message = raw.cast<String, dynamic>();
    }
    if (message == null) return;

    // Cursor position for the tooltip comes from the injected listener, not from viewer.html, so
    // it is handled here rather than in the bridge's viewer-protocol switch.
    if (message['event'] == 'hoverPoint') {
      final x = message['x'];
      final y = message['y'];
      widget.bridge.updateHoverPoint(
        x is num && y is num ? Offset(x.toDouble(), y.toDouble()) : null,
      );
      return;
    }

    widget.bridge.receiveMessage(message);
  }

  @override
  void dispose() {
    widget.bridge.detach();
    super.dispose();
  }
}

class _InAppWebViewJsRunner implements MolStarJsRunner {
  _InAppWebViewJsRunner(this._controller);

  final InAppWebViewController _controller;

  @override
  Future<void> evaluate(String source) async {
    await _controller.evaluateJavascript(source: source);
  }

  @override
  Future<Object?> callAsync(String source) async {
    final result = await _controller.callAsyncJavaScript(functionBody: source);
    if (result == null) return null;
    if (result.error != null) throw StateError(result.error!);
    return result.value;
  }
}
