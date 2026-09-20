# MolApp

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/donghanlee)

Mol\*-powered molecule viewer.

There are three shells in this repo over one shared web core:

| Directory | Shell | Targets |
| --- | --- | --- |
| **`flutter_app/`** | **Flutter / Dart** | **iOS, Android, macOS, Windows** |
| `linux/` | GTK 3 / WebKitGTK (Python) | Linux |
| `MolApp/` | SwiftUI | iPadOS / iOS |

**`flutter_app/` is the one to work in for the mobile and desktop targets it covers.** See
[`flutter_app/README.md`](flutter_app/README.md) for setup, per-platform requirements and known
gaps. The SwiftUI shell is the reference implementation the Flutter port was checked against.
Flutter ships to both the App Store and Google Play. The former Jetpack Compose shell (`android/`)
and the Flutter Linux target were removed; they live on at the git tags `native-android-ref` and
`flutter-linux-ref`.

**Linux is served by `linux/`, not by Flutter.** `flutter_inappwebview_linux` renders through WPE
WebKit 2.40+, which no current Ubuntu ships at all, so the Flutter Linux target was dropped. The GTK shell runs the same
`viewer.html` on stock WebKitGTK 4.1 with no build step; see
[`linux/README.md`](linux/README.md).

## The shared web core

`MolApp/Resources/viewer.html` plus `MolApp/Resources/molstar/` are the actual viewer, and are the
**single source of truth for all three shells**. Edit only that copy:

- Flutter copies it with `dart run tool/sync_web_assets.dart`.
- iOS bundles it directly as a target resource.
- Linux loads it straight from this directory (`$MOLAPP_WEB_ROOT` overrides).

The shells talk to it over one JSON protocol: `window.molapp.handleNativeCommand({id, command,
payload})` in, command results and events back out.

## Build

```sh
# Flutter — iOS, Android, macOS, Windows
cd flutter_app && flutter pub get && dart run tool/sync_web_assets.dart
flutter run -d macos            # or windows / an android or ios device

# Linux — no build step; run from the checkout, or install the .deb
sudo apt-get install -y python3-gi python3-gi-cairo gir1.2-webkit2-4.1 gir1.2-gtk-3.0 python3-pil
cd linux && ./molapp-linux
linux/packaging/build-deb.sh && sudo apt-get install -y ./linux/dist/molapp_*.deb

# SwiftUI (iPad)
xcodebuild -project MolApp.xcodeproj -scheme MolApp -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.4.1' build CODE_SIGNING_ALLOWED=NO

```

## Apple Pencil

- **Hover residue tooltip**: hovering the Pencil over an atom/residue shows its identity label near
  the cursor before selection. Requires a physical iPad + Apple Pencil — the Simulator does not emit
  hover events. On desktop the same tooltip follows the mouse.
- **Distance / angle / dihedral measurement**: Measure ▸ Distance / Angle / Dihedral Mode, then pick
  2 / 3 / 4 atoms to draw the measurement (Å or °) between them. Atom-level picking; pick more sets
  to add, or Clear Measurements to remove. Also available as the `measure`, `measure angle`,
  `measure dihedral`, and `measure clear` commands.

Still planned:

- Screenshot annotation and sharing for communicating marked-up structure views.

## Support

MolApp is free. If it helps your work, you can [buy me a coffee](https://buymeacoffee.com/donghanlee).
