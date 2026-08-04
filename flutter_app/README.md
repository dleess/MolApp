# MolApp (Flutter)

The Mol\*-powered molecule viewer for **iOS, Android, macOS, Windows and Linux** from one codebase.
This replaces the SwiftUI app in `../MolApp` and the Compose app in `../android`, which stay in the
repo as the reference implementations the port was checked against.

## What is shared and what was rewritten

`viewer.html` + the Mol\* bundle are the app. They were **not** ported — they are the same files the
native apps run, still living in `../MolApp/Resources` as the single source of truth. Only the
native shell moved to Dart:

| Was | Now |
| --- | --- |
| `MolStarBridge.swift` / `.kt` | `lib/src/molstar_bridge.dart` |
| `SelectionExpressionParser.swift` / `.kt` | `lib/src/selection_expression_parser.dart` |
| `MoleculeViewerModels.swift` / `Models.kt` | `lib/src/models.dart` |
| `MoleculeViewerView.swift` / `ViewerController.kt` | `lib/src/viewer_controller.dart` + `lib/src/viewer_page.dart` |
| `MolStarWebView.swift` / `MainActivity.createWebView` | `lib/src/molstar_web_view.dart` |
| `LocalStructureFileLoader.swift` | `lib/src/structure_file.dart` |
| `encodeImage` / `GifEncoder.kt` / print | `lib/src/export.dart` |
| `ManualView.swift` | `lib/src/manual_page.dart` |

The one change to the shared web core is a third branch in `postToNative` (`viewer.html`): a generic
`window.molappPostMessage` hook the Flutter host installs. The iOS `webkit.messageHandlers` and
Android `MolAppAndroid` branches are untouched, so the native apps still build and run.

All five platforms use a single webview plugin, `flutter_inappwebview`: WKWebView on iOS/macOS,
Android System WebView, WebView2 on Windows, WPE WebKit on Linux.

## Setup

```sh
cd flutter_app
flutter pub get
dart run tool/sync_web_assets.dart   # copies viewer.html + molstar/ from ../MolApp/Resources
```

`assets/web/` is gitignored so the 4.8 MB Mol\* bundle lives in git exactly once — the same rule the
Android app's `copyWebAssets` Gradle task follows. **Edit only `../MolApp/Resources`**, then re-sync.
Forgetting the sync fails the build loudly (Flutter cannot find the asset directory); it never ships
a silently broken viewer.

### macOS / iOS: Swift Package Manager must be off

```sh
flutter config --no-enable-swift-package-manager
```

`flutter_inappwebview_macos` declares a macOS 10.14 SPM platform, and its
`ASWebAuthenticationPresentationContextProviding` conformance does not compile at that deployment
target against a current SDK. CocoaPods builds it at the app's own 10.15 target instead, which is
fine. This is a per-machine Flutter setting, not something the repo can carry — CI sets it too.

### Linux: WPE WebKit

```sh
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
  libwpewebkit-1.1-dev libwpebackend-fdo-1.0-dev libwpe-1.0-dev libepoxy-dev
```

The plugin prefers `wpe-platform-2.0` (WPE WebKit 2.40+) and falls back to `wpe-webkit-1.1` +
`wpebackend-fdo-1.0`, which is what Ubuntu ships.

### Windows: NuGet on PATH

`flutter_inappwebview_windows` pulls the WebView2 SDK from NuGet at configure time, so `nuget.exe`
must be on `PATH`.

## Build and run

```sh
flutter run -d macos          # or: -d windows, -d linux, -d <android device>, -d <ios device>
flutter build macos --release
flutter build apk --release   # and: appbundle, ios, windows, linux
```

## Distribution builds

The desktop targets ship as plain archives — nothing to install beyond unpacking, because each build
tree is already self-contained. Both scripts read the version from `pubspec.yaml` and write to
`flutter_app/dist/` (gitignored), mirroring `linux/packaging/build-deb.sh`.

```sh
flutter build macos --release && macos/packaging/build-dmg.sh      # dist/molapp-<v>-macos.dmg
flutter build windows --release; windows\packaging\build-zip.ps1   # dist/molapp-<v>-windows-x64.zip
```

CI builds both on every push, uploads them as artifacts, and proves each one by unpacking it
elsewhere and launching *that* copy — a package that unpacks but cannot find its Mol\* assets would
pass a plain build and fail on the first user's machine. Neither is code-signed, so macOS Gatekeeper
and Windows SmartScreen both warn on first launch.

iOS and Android keep their store pipelines (`flutter build ipa` / `appbundle`); Linux keeps the GTK
shell's `.deb`.

## Tests

```sh
flutter analyze
flutter test                                                   # 103 unit + widget tests
flutter test integration_test/viewer_bridge_test.dart -d macos  # real webview, real Mol*
```

`integration_test/viewer_bridge_test.dart` is the one that matters for a platform bring-up: it boots
the real viewer from the asset bundle, pushes a structure in as text (no network, no file picker),
and checks the object comes back, a per-object command lands, `serializeState` and
`captureImageDataURL` return, and reset clears the scene. Run it with `-d <platform>` to prove a
target is wired end to end.

## Identifiers

| | value | note |
| --- | --- | --- |
| Android `applicationId` | `com.donghan.molapp` | same as the Compose app, so the Play listing carries over |
| iOS bundle id | `com.donghan.MolApp` | matches the App Store app (case-sensitive) |
| macOS bundle id | `com.donghan.molapp` | new target, no existing listing |
| Linux application id | `com.donghan.molapp` | |
| version | `1.0.4+1` (pubspec) | Android was at versionName 1.0.4 / versionCode 3, iOS at 1.0.3 / build 9 |

Android release signing reads `MOLAPP_STORE_FILE` / `MOLAPP_STORE_PASSWORD` / `MOLAPP_KEY_ALIAS` /
`MOLAPP_KEY_PASSWORD` from `~/.gradle/gradle.properties`, the same upload keystore the Compose app
used. Without them the release build falls back to debug keys so `flutter run --release` still works.

**Before uploading to Play, bump `versionCode` past 3** — the Compose app already burned 1–3.
`flutter build` derives it from pubspec's `+1`, so set `version: 1.0.4+4` or pass `--build-number=4`.

## Known gaps versus the native apps

- **Apple Pencil hover tooltip on iPad.** WKWebView does not deliver stylus hover to JS, and the
  native app used a `UIHoverGestureRecognizer` on the web view. Flutter forwards stylus hover through
  a `Listener` (`molstar_web_view.dart`), but whether those events survive the platform view has not
  been checked on real iPad hardware. Mouse hover on desktop works through an injected `pointermove`
  listener and needs nothing from Flutter.
- **Windows and Linux are built by CI, not by hand.** No local hardware;
  `../.github/workflows/flutter.yml` builds both. Neither has been *run*, so the viewport, gestures
  and the file dialogs are unproven there.
- **Foldables.** Flutter's default `configChanges` is a superset of the attribute PR #17 added for
  the Samsung Flip, and the webview lives inside the Flutter view rather than being rebuilt in
  `onCreate`, so that class of bug should be gone — but this was not re-tested on real Flip hardware.
- **GIF export is a single frame**, as in both native apps.
