# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Behavioral rules (surgical changes, no speculative abstractions, verify before claiming done) live in
`AGENTS.md`, together with a list of iOS-specific invariants under "MolApp Project Notes". Read both.
`HANDOFF.md` is the current release state (what is in review on which store, open QA items) — refresh
it when you change release state.

## Architecture: one web core, three shells

`MolApp/Resources/viewer.html` + `MolApp/Resources/molstar/` **are the app**. Every shell is a thin
native host around that one HTML file, and it is the single source of truth — edit only that copy:

| Shell | Dir | Ships as | Web core reaches it by |
| --- | --- | --- | --- |
| Flutter / Dart | `flutter_app/` | Play (Android), macOS `.dmg`, Windows `.zip`; iOS builds but the App Store build is the SwiftUI shell | `dart run tool/sync_web_assets.dart` → `assets/web/` (gitignored) |
| SwiftUI | `MolApp/`, `MolApp.xcodeproj` | App Store (iPadOS/iOS), via the `ship` skill | Xcode target resource, `loadFileURL` |
| GTK 3 / WebKitGTK (Python) | `linux/` | `.deb` from `linux/packaging/build-deb.sh` | reads `../MolApp/Resources` directly (`$MOLAPP_WEB_ROOT` overrides) |

Flutter does **not** serve Linux (`flutter_inappwebview_linux` needs WPE WebKit no Ubuntu ships).
The former Jetpack Compose shell, the Flutter Linux target and the Ralph loop tooling were removed;
they survive at git tags `native-android-ref`, `flutter-linux-ref`, `ralph-ref`.

### The bridge protocol

- Inbound: `window.molapp.handleNativeCommand({id, command, payload})`. Command names are the
  `MolStarCommandName` / `MolStarCommand` enum cases in each shell (`loadLocalStructure`, `loadPdbId`,
  `setRepresentation`, `toggleVisibility`, `setSelection`, `setObjectVisibility`, `setObjectColor`,
  `startMorph`, `superpose`, `setMeasureMode`, `loadState`, `undo`, `redo`, `resetAll`, …).
- Outbound: `postToNative(obj)` in viewer.html tries, in order, `window.molappPostMessage` (Flutter),
  `webkit.messageHandlers.molapp` (WKWebView and WebKitGTK), `window.MolAppAndroid` (legacy). It
  carries command results and events: `viewerReady`, `viewerError`, `objectsAdded`,
  `objectsReplaced`, `objectsVisibility`, `featureVisibility`, `selectionChanged`, `pencilHover`,
  `measurement`, `measurePending`.
- **Enum member names are the wire format.** `MoleculeRepresentation`, `ObjectRepresentation`,
  `MoleculeVisibilityFeature`, `ExportFormat` etc. exist in all three shells with identical raw names,
  and `linux/tests/test_logic.py` pins them. Renaming a case changes the protocol.
- Each shell has the same module split: models (enums, palette, PDB-id/file rules), selection
  expression parser (`select` grammar → AST → `setSelection`), bridge (command queue + JSON + inbound
  events), controller (status line, command bar, actions), web view host, export (PNG →
  PNG/JPEG/GIF/SVG/PDF), manual. `flutter_app/README.md` and `linux/README.md` each carry the
  file-by-file mapping. A behavior change usually lands in viewer.html once and in the shell(s) that
  expose it.
- The command bar (`load 1crn`, `repr`, `show`/`hide`, `select`, `color`, `bg`, `measure`, `super`,
  `morph`, `ss`, `surfpot`, …) is parsed in each shell's controller, not in viewer.html.

## Commands

### Flutter (`cd flutter_app`)

```sh
flutter pub get && dart run tool/sync_web_assets.dart   # sync is required before any build/test
flutter analyze
flutter test                                            # unit + widget
flutter test test/models_test.dart                      # one file
flutter test test/models_test.dart --plain-name 'copyWith'   # one test by name
flutter test integration_test/viewer_bridge_test.dart -d macos   # real webview + real Mol*
flutter run -d macos                                    # or windows / android / ios device
flutter build appbundle --release                       # Play upload
flutter build macos --release && macos/packaging/build-dmg.sh
```

- macOS/iOS need Swift Package Manager off: `flutter config --no-enable-swift-package-manager`.
- Integration tests: **one file per invocation** on macOS desktop; `flutter test integration_test -d macos`
  fails on the second file ("Unable to start the app on the device").
- Android release signing reads `MOLAPP_STORE_FILE` / `MOLAPP_STORE_PASSWORD` / `MOLAPP_KEY_ALIAS` /
  `MOLAPP_KEY_PASSWORD` from `~/.gradle/gradle.properties`; without them it falls back to debug keys.
  `versionCode` comes from pubspec's `+N`.

### SwiftUI (repo root)

```sh
xcodebuild -project MolApp.xcodeproj -scheme MolApp \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.4.1' build CODE_SIGNING_ALLOWED=NO
# tests: same command with `test`; one test: add -only-testing:MolAppTests/MolStarBridgeTests/<name>
```

### Linux (`cd linux`)

```sh
./molapp-linux                                    # run from checkout, no build step; MOLAPP_DEBUG=1 for the inspector
python3 -m unittest discover -s tests             # logic + smoke (smoke needs a display)
xvfb-run -a python3 -m unittest discover -s tests # headless, what CI runs
python3 -m unittest tests.test_logic              # logic only, no display
```

### CI

`.github/workflows/flutter.yml` (analyze/test, windows, apple, android) and `linux.yml` (test,
package) are path-filtered: both also trigger on `MolApp/Resources/**`. The apple and windows jobs
unpack the packaged build and launch it, so a build that cannot find its Mol* assets fails there.
