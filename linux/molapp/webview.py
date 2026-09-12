"""The Mol* viewport: `viewer.html` in a WebKitGTK web view, wired to :class:`MolStarBridge`.

WebKitGTK is the Linux member of the same WebKit family the iOS/macOS shells use, so the shared web
core needs no Linux branch: `postToNative` in viewer.html already falls through to
`window.webkit.messageHandlers.molapp.postMessage`, which is exactly what
`register_script_message_handler("molapp")` installs here.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Callable

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("WebKit2", "4.1")

from gi.repository import Gdk, GLib, WebKit2  # noqa: E402  (must follow require_version)

from .bridge import MolStarBridge  # noqa: E402

#: Name of the JS→native handler. viewer.html posts to it through `window.webkit.messageHandlers`,
#: the same channel name the iOS shell registers on WKWebView.
HANDLER_NAME = "molapp"

#: Cursor tracking for the hover tooltip. The label itself comes from Mol*'s own hover
#: subscription; this only supplies where to draw it. Touch is excluded — a finger drag is a camera
#: rotation, not a hover.
_HOVER_SCRIPT_SOURCE = f"""
(function () {{
  function post(payload) {{
    var handlers = window.webkit && window.webkit.messageHandlers;
    if (handlers && handlers.{HANDLER_NAME}) handlers.{HANDLER_NAME}.postMessage(payload);
  }}
  var lastPost = 0;
  document.addEventListener('pointermove', function (e) {{
    if (e.pointerType === 'touch') return;
    if (e.timeStamp - lastPost < 32) return;
    lastPost = e.timeStamp;
    post({{ event: 'hoverPoint', x: e.clientX, y: e.clientY }});
  }}, {{ passive: true, capture: true }});
  document.addEventListener('pointerleave', function (e) {{
    if (e.pointerType === 'touch') return;
    post({{ event: 'hoverPoint', x: null, y: null }});
  }}, {{ passive: true, capture: true }});
}})();
"""


class ViewerAssetsMissing(Exception):
    pass


def viewer_html_path() -> str:
    """Locates the shared web core — `MolApp/Resources/viewer.html`, the single source of truth all
    four shells run. Checked in order: an explicit override, the repo checkout this file sits in,
    then the installed data directories."""
    candidates = []
    override = os.environ.get("MOLAPP_WEB_ROOT")
    if override:
        candidates.append(override)
    repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    candidates.append(os.path.join(repo_root, "MolApp", "Resources"))
    candidates.append("/usr/share/molapp/web")
    candidates.append("/usr/local/share/molapp/web")

    for directory in candidates:
        path = os.path.join(directory, "viewer.html")
        if os.path.isfile(path):
            return path
    raise ViewerAssetsMissing(
        "Could not find viewer.html. Looked in: " + ", ".join(candidates) + ". "
        "Set MOLAPP_WEB_ROOT to the directory holding viewer.html and molstar/."
    )


class MolStarWebView:
    """Owns the `WebKit2.WebView` widget and implements the bridge's JS runner."""

    def __init__(self, bridge: MolStarBridge, on_hover_point: Callable[[object], None] | None = None):
        self.bridge = bridge
        self._on_hover_point = on_hover_point

        content_manager = WebKit2.UserContentManager()
        content_manager.register_script_message_handler(HANDLER_NAME)
        content_manager.connect(
            f"script-message-received::{HANDLER_NAME}", self._on_script_message
        )
        content_manager.add_script(
            WebKit2.UserScript.new(
                _HOVER_SCRIPT_SOURCE,
                WebKit2.UserContentInjectedFrames.TOP_FRAME,
                WebKit2.UserScriptInjectionTime.START,
                None,
                None,
            )
        )

        self.widget = WebKit2.WebView.new_with_user_content_manager(content_manager)
        settings = self.widget.get_settings()
        # molstar.js is loaded relative to viewer.html on a file:// URL.
        settings.set_property("allow-file-access-from-file-urls", True)
        settings.set_property("allow-universal-access-from-file-urls", True)
        settings.set_property("enable-webgl", True)
        settings.set_property("enable-developer-extras", bool(os.environ.get("MOLAPP_DEBUG")))
        # ON_DEMAND, not ALWAYS: Mol* is WebGL, so acceleration switches on for it either way, and
        # ALWAYS kills the web process outright on a machine with no GPU (a headless CI runner).
        settings.set_property(
            "hardware-acceleration-policy", WebKit2.HardwareAccelerationPolicy.ON_DEMAND
        )
        self.widget.set_background_color(_rgba(0x0B, 0x0F, 0x14))

        # Right-drag pans the Mol* camera, so WebKit's own context menu would fire on every pan.
        self.widget.connect("context-menu", lambda *_: True)
        self.widget.connect("load-failed", self._on_load_failed)
        self.widget.connect("web-process-terminated", self._on_web_process_terminated)
        if os.environ.get("MOLAPP_DEBUG"):
            self.widget.connect(
                "console-message-sent",
                lambda _view, message: print(f"[viewer] {message.get_text()}", flush=True),
            )

        self.load()

    def load(self) -> None:
        self.bridge.attach(self)
        self.widget.load_uri(Path(viewer_html_path()).absolute().as_uri())

    # MARK: - MolStarJsRunner

    def evaluate(self, source: str) -> None:
        self.widget.evaluate_javascript(source, -1, None, None, None, None, None)

    def call_async(self, source: str, on_done: Callable[[object | None, str | None], None]) -> None:
        def on_ready(_view, result, _data) -> None:
            try:
                value = self.widget.call_async_javascript_function_finish(result)
            except GLib.Error as error:
                on_done(None, error.message)
                return
            on_done(_python_value(value), None)

        self.widget.call_async_javascript_function(source, -1, None, None, None, None, on_ready, None)

    # MARK: - Inbound

    def _on_script_message(self, _manager, result) -> None:
        message = _decode_message(result)
        if message is None:
            return

        # Cursor position for the tooltip comes from the injected listener, not from viewer.html,
        # so it is handled here rather than in the bridge's viewer-protocol switch.
        if message.get("event") == "hoverPoint":
            x, y = message.get("x"), message.get("y")
            point = (float(x), float(y)) if isinstance(x, (int, float)) and isinstance(y, (int, float)) else None
            self.bridge.update_hover_point(point)
            if self._on_hover_point is not None:
                self._on_hover_point(point)
            return

        self.bridge.receive_message(message)

    def _on_load_failed(self, _view, _load_event, failing_uri, error) -> bool:
        # A cancelled load is what a second load_uri looks like, not a failure to report.
        if error.matches(WebKit2.NetworkError.quark(), WebKit2.NetworkError.CANCELLED):
            return False
        self.bridge.receive_message({
            "event": "viewerError", "fatal": True,
            "message": f"Viewer failed to load: {error.message}",
        })
        return False

    def _on_web_process_terminated(self, _view, _reason) -> None:
        # The viewer's JS is gone, so it cannot report its own death. Reload from the file rather
        # than reload(): after a crash every command sent meanwhile would hit a dead page.
        self.bridge.report_error("The viewer process stopped; reloading.")
        self.load()


def _decode_message(result) -> dict | None:
    """viewer.html posts an object; the hover script posts one too. Both arrive as a JSCValue."""
    value = result.get_js_value() if hasattr(result, "get_js_value") else result
    try:
        raw = value.to_json(0) if value.is_object() else value.to_string()
        message = json.loads(raw)
        # A string payload is a JSON document in its own right (the shape the Android shell posts).
        if isinstance(message, str):
            message = json.loads(message)
    except (ValueError, TypeError):
        return None
    return message if isinstance(message, dict) else None


def _python_value(value) -> object | None:
    if value is None or value.is_null() or value.is_undefined():
        return None
    if value.is_string():
        return value.to_string()
    if value.is_boolean():
        return value.to_boolean()
    if value.is_number():
        return value.to_double()
    return value.to_json(0)


def _rgba(red: int, green: int, blue: int):
    return Gdk.RGBA(red / 255, green / 255, blue / 255, 1.0)


__all__ = ["MolStarWebView", "ViewerAssetsMissing", "viewer_html_path"]
