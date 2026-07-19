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
- Two WebView portability fixes live in the shared `viewer.html`:
  1. **Viewport height.** The Mol\* host is `position: fixed; inset: 0`. The plain `height: 100%`
     chain (`html > body > host`) collapses to a **0-height, black canvas** in the Android System
     WebView (`<body>` resolves its percentage height to 0 there) even though iOS WKWebView resolves
     it fine. Fixed positioning sizes against the window on both platforms.
  2. **Float blending.** When the WebGL stack lacks `EXT_float_blend` (the emulator, and some low-end
     GPUs), init falls back from WBOIT to plain `blended` transparency with multisampling off, so no
     pass blends into a floating-point buffer. Real mobile/desktop GPUs expose the extension and keep
     WBOIT — no visual change there.
- Verified rendering 1CRN (ribbon + surface) on both `-gpu host` and `-gpu swiftshader_indirect`
  emulators. In `BuildConfig.DEBUG`, WebView remote debugging is on — inspect via
  `chrome://inspect` or `adb forward tcp:9333 localabstract:webview_devtools_remote_<pid>`.
