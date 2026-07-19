# MolApp — Android

Native Android shell (Kotlin + Jetpack Compose + WebView) around the same Mol\* web viewer the
iOS app uses. The web core (`viewer.html` + `molstar/`) lives in `../MolApp/Resources` and is the
single source of truth — a Gradle task (`copyWebAssets`) copies it into `app/src/main/assets` at
build time, so it is never duplicated in git.

## Build

Requires a JDK 17 and the Android SDK. On this machine:

```sh
cd android
JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew assembleDebug
```

`local.properties` points Gradle at the SDK (`sdk.dir=...`); it is git-ignored — create it locally.

## Run

```sh
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.donghan.molapp/.MainActivity
```

Load a structure by PDB id (`load 1crn`), the command bar, or File ▸ Open Structure (a local
`.pdb`/`.cif`).

## Notes

- The JS↔native bridge is shared with iOS via `viewer.html`'s `postToNative()` shim: iOS receives
  over a `WKScriptMessageHandler`, Android over the `MolAppAndroid` `@JavascriptInterface`.
- Mol\* uses floating-point WebGL render targets. Some emulator GPUs lack `EXT_float_blend`, which
  breaks the 3D paint (the structure still loads — the Objects panel populates); use a real device
  or a SwiftShader emulator (`-gpu swiftshader_indirect`) to see rendering.
