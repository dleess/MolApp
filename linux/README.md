# MolApp (Linux)

The GTK 3 / WebKitGTK shell — the fourth shell over the shared web core, alongside SwiftUI
(`../MolApp`), Jetpack Compose (`../android`) and Flutter (`../flutter_app`).

It runs the same `../MolApp/Resources/viewer.html` the other three do, unmodified: WebKitGTK is the
Linux member of the same WebKit family iOS/macOS use, so `postToNative` in viewer.html already
falls through to `window.webkit.messageHandlers.molapp.postMessage` — exactly the channel this
shell registers. No Linux branch was added to the shared core.

## Why not Flutter, when `flutter_app` claims Linux

`flutter_inappwebview_linux` (its only published version, 0.1.0-beta.1) renders through **WPE
WebKit 2.40+**, and no Ubuntu release ships WPE at all any more — jammy was the last, at 2.36. That
is why `.github/workflows/flutter.yml`'s `linux` job has never once passed and carries a
`continue-on-error` on its build step. The alternative Flutter-side webviews are worse fits here:
Flutter's Linux embedder has no platform views, so a GTK-based plugin has to float a native
`WebKitWebView` in a `GtkOverlay` **above** the Flutter surface — and this app draws its entire
chrome (menu bar, info card, Objects panel, command bar) *over* a full-bleed viewport, so every
menu and panel would end up behind the web view.

A GTK shell has neither problem: the web view is a widget in the layout, GTK menus and popovers are
their own windows, and WebKitGTK 4.1 is a stock Ubuntu package with GPU-accelerated WebGL. The
Flutter Linux job stays in CI as the canary it already was.

## Requirements

```sh
sudo apt-get install -y python3-gi python3-gi-cairo gir1.2-webkit2-4.1 gir1.2-gtk-3.0 python3-pil
```

Everything else is the Python standard library. There is no build step — `python3-pil` is only used
by File ▸ Export Display to re-encode the captured PNG as JPEG/GIF/PDF.

## Install

```sh
linux/packaging/build-deb.sh                          # → linux/dist/molapp_1.1.4_all.deb
sudo apt-get install -y ./linux/dist/molapp_*.deb     # apt pulls the GTK/WebKit dependencies
molapp
```

`Architecture: all` — the shell is pure Python and everything native comes from distro packages, so
there is nothing to compile and one package covers every architecture. It installs the code to
`/usr/lib/molapp`, the shared web core to `/usr/share/molapp/web` (the third path
`viewer_html_path()` checks, so the installed app needs no configuration), plus `/usr/bin/molapp`, a
desktop entry and an icon. `apt-get remove molapp` takes it back out.

CI builds the same package on every change, installs it, and re-runs the whole test suite against
the *installed* copy — see the `package` job in `.github/workflows/linux.yml`. The built `.deb` is
attached to that run as an artifact.

## Run from a checkout

```sh
cd linux && ./molapp-linux          # or: PYTHONPATH=. python3 -m molapp
```

The viewer assets are found automatically: `$MOLAPP_WEB_ROOT`, then `../MolApp/Resources` relative
to the checkout, then `/usr/share/molapp/web`. Set `MOLAPP_DEBUG=1` to enable the WebKit inspector
and echo the page's console to stdout.

`molapp.desktop` is the launcher entry the package installs. To use it from a checkout instead,
point its `Exec=` at `linux/molapp-linux` and copy it to `~/.local/share/applications/`.

## Tests

```sh
cd linux
python3 -m unittest discover -s tests             # 43 logic tests + 8 end-to-end, needs a display
xvfb-run -a python3 -m unittest discover -s tests # headless (what CI runs)

# against the installed package rather than this checkout
cd /tmp && PYTHONPATH=/usr/lib/molapp xvfb-run -a python3 -m unittest discover -s ~/MolApp/linux/tests
```

- `tests/test_logic.py` — the wire protocol, the selection-expression parser, every command-bar
  branch, the export encoders. No display needed.
- `tests/test_smoke.py` — boots the real window, the real WebKitGTK view and the real Mol* bundle,
  pushes a structure in as text (no network, no file dialog), and checks the object comes back, a
  per-object command lands, `serializeState` and `captureImageDataURL` return a real rendered
  image, and Reset clears the scene. This is the check that proves the platform is wired end to
  end, the counterpart of `flutter_app/integration_test/viewer_bridge_test.dart`.

## Layout

| File | Role | Ported from |
| --- | --- | --- |
| `molapp/models.py` | enums, palette, PDB-id and local-file rules | `models.dart` / `MoleculeViewerModels.swift` |
| `molapp/selection.py` | `select` expression parser | `selection_expression_parser.dart` |
| `molapp/bridge.py` | command queue, JSON protocol, inbound events | `molstar_bridge.dart` / `MolStarBridge.swift` |
| `molapp/controller.py` | status line, actions, command bar | `viewer_controller.dart` |
| `molapp/export.py` | PNG → PNG/JPEG/GIF/SVG/PDF | `export.dart` |
| `molapp/webview.py` | WebKitGTK host, JS runner | `molstar_web_view.dart` / `MolStarWebView.swift` |
| `molapp/window.py` | the window, chrome and Objects panel | `viewer_page.dart` / `MoleculeViewerView.swift` |
| `molapp/manual.py` | Help ▸ Manual | `manual_page.dart` / `ManualView.swift` |
| `packaging/build-deb.sh` | the `.deb` | — |

Enum member names are the wire format viewer.html reads; `tests/test_logic.py` pins them so a
rename cannot silently change the protocol.

## Known gaps versus the iOS shell

- **Apple Pencil hover** has no Linux equivalent. Mouse hover works: the label comes from Mol*'s own
  hover subscription and the position from a small injected `pointermove` listener, the same split
  the Flutter shell uses.
- **Sharing.** Desktop gets a Save-as dialog instead of the iOS share sheet, as macOS/Windows do.
- **GIF export is a single frame**, as in every other shell.
- **Mol\*'s own chrome** (the control strip at the right edge, the logo) shows through the viewport
  here exactly as it does on the other platforms — an open item against `viewer.html`, not this
  shell.
