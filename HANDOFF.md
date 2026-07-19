# HANDOFF: Port MolApp to run on Android + iPhone (both render the Mol* viewer)

**Written:** 2026-07-19 · **Working dir:** `/Users/donghanlee/work/projects/molapp` · **Branch:** `feat/android-iphone-port`

> Note: this file previously held the completed "1.0.2 App Store ship" handoff (2026-07-16). That
> task is done (1.0.2/build 8 was WAITING_FOR_REVIEW; ids also live in memory `molapp-appstore-status.md`).
> Overwritten with the current task.

## Goal
MolApp (thin native shell + Mol* WebGL viewer in a WebView) runs on **both** iPhone and Android,
with the 3D structure actually **rendering** (not just loading). Acceptance test: `load 1crn` shows
the crambin ribbon on an iPhone sim AND an Android emulator.

## Status
**Done and verified.** Working tree **clean** — everything committed. Branch `feat/android-iphone-port`
is 4 commits ahead of `master`, **not merged** (merge never requested — confirm before doing it).

1CRN ribbon renders on:
- iOS iPhone 17 sim ✅
- Android emulator `-gpu host` (Apple M4 / Metal via ANGLE) ✅
- Android emulator `-gpu swiftshader_indirect` (software, the AVD's default) ✅

Ribbon + surface both render; interactive rotation throws 0 GL errors.

## What worked
- **Root-caused the Android black screen via live CDP inspection.** Enabled WebView remote
  debugging, `adb forward tcp:9333 localabstract:webview_devtools_remote_<pid>`, then
  `Runtime.evaluate` to read the real canvas. It was **411×0** (zero height) — that was the whole
  black-screen mystery. Structure loaded fine (`boundingSphere` 26.78); nothing to paint on a
  0-height canvas. **[still applied — remote debugging is on in DEBUG builds]**
- **CSS fix `#molstar-host { position: fixed; inset: 0 }`** in `MolApp/Resources/viewer.html`.
  The `html>body>#molstar-host { height:100% }` chain collapses to 0 in the Android System WebView
  (`document.body` clientHeight = 0 while `document.documentElement` clientHeight = 842). Fixed
  positioning sizes against the window instead. This is the real fix; affects **all** Android
  devices. iOS unaffected. **[still applied — committed 6c89280]**
- **EXT_float_blend fallback** in `viewer.html` init: probe the extension, and when absent
  `viewer.plugin.canvas3d.setProps({ transparency: 'blended', multiSample: { mode: 'off' } })`.
  Mol*'s default `transparency:"wboit"` blends into float buffers (needs EXT_float_blend); the
  emulator WebView lacks it → `GL_INVALID_OPERATION`. **[still applied — committed 6c89280]**
- Verifying fixes **live via CDP before editing the file** (set `host.style.position='fixed'` +
  `canvas3d.handleResize()` → canvas became 411×841). Grounded, no guessing.

## What didn't work
- **Earlier claim "black = emulator GPU EXT_float_blend limitation, works on real device" was WRONG.**
  Primary cause was the 0-height canvas (a CSS bug hitting all Android devices). Don't repeat that
  diagnosis. EXT_float_blend was a real but *secondary* issue.
- **`transparency:'blended'` alone did NOT kill the float-blend errors** — MSAA sample-accumulation
  also blends into fp16. Needed `multiSample:{mode:'off'}` too. (Both now in the fallback.)
- **"0 float-blend errors" seen while the canvas was still 0-height was a false negative** — nothing
  was drawing, so no draws to fail. Only trust GL-error counts once the canvas has non-zero height
  and a structure is loaded.
- Switching the emulator to `-gpu host` did **not** by itself expose EXT_float_blend — the Android
  System WebView's ANGLE doesn't surface it regardless of host GPU. So the fallback is genuinely
  needed on the emulator; real mobile GPUs (Adreno/Mali/Apple) do expose it.

## Key files & commands
- `MolApp/Resources/viewer.html` — shared web core (single source of truth for iOS + Android). Holds
  the CSS fix (`#molstar-host`, ~line 24), `detectWebGLCapabilities()` + the float-blend fallback
  (in `initializeViewer`, ~line 2056 / ~line 2124), and a one-line `[MolApp][GL]` capability log.
- `android/app/src/main/java/com/donghan/molapp/MainActivity.kt` — `createWebView()` calls
  `WebView.setWebContentsDebuggingEnabled(true)` under `if (BuildConfig.DEBUG)`; `onConsoleMessage`
  forwards JS console → Logcat tag `MolApp/JS`.
- `android/app/build.gradle` — `buildFeatures { buildConfig true }` (needed for `BuildConfig.DEBUG`);
  `copyWebAssets` task copies `../MolApp/Resources` (viewer.html + molstar) into assets at build time.
- Android build/run:
  ```sh
  cd /Users/donghanlee/work/projects/molapp/android
  JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew assembleDebug -q
  ~/Library/Android/sdk/platform-tools/adb install -r app/build/outputs/apk/debug/app-debug.apk
  ~/Library/Android/sdk/platform-tools/adb shell am start -n com.donghan.molapp/.MainActivity
  ```
- iOS build/run:
  ```sh
  xcodebuild -project MolApp.xcodeproj -scheme MolApp \
    -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/molapp_dd build
  xcrun simctl install <SIM_UDID> /tmp/molapp_dd/Build/Products/Debug-iphonesimulator/MolApp.app
  xcrun simctl launch <SIM_UDID> com.donghan.MolApp
  ```
  (iOS bundle id: `com.donghan.MolApp`; Android applicationId: `com.donghan.molapp` — different case.)
- CDP inspection helper (outside repo, session scratchpad — may not persist):
  `/private/tmp/claude-501/-Users-donghanlee-work-projects-molapp/37ee0721-d689-4c32-9167-d7422de746c6/scratchpad/cdp.py`
  (`python3 cdp.py <ws_url> "<js expr>"`, no deps, raw-socket WebSocket). `probe.js` there measures
  canvas size + screenshot brightness. Re-derivable if gone.
- iOS Simulator taps are in **points, not pixels** (per user CLAUDE.md). Android `adb shell input`
  taps are in **pixels**; the emulator screenshots came back at display×1.20 scale.

## Next steps
1. Nothing required to meet the goal — met and verified. Stop unless the user asks for more.
2. If landing it: open a PR / merge `feat/android-iphone-port` → `master` (commit `6c89280` is the
   render fix on top of the port). **Confirm first — not yet requested.**
3. If Play Store shipping comes up: default Google Play account is **lee.donghan@gmail.com** (never
   kbsi.bionmr, per user CLAUDE.md); needs a signed release bundle. App Store: bump to the NEXT
   available version (see memory `molapp-appstore-status.md`).

## Open questions / risks
- **No real physical Android device tested** (none available). Confidence rests on the fix being
  GPU-agnostic + both emulator GPU modes passing. Real hardware also has EXT_float_blend, so it takes
  the WBOIT path, which is exercised on iOS. Low risk, but **unverified on real Android hardware.**
- Android features still iOS-only (deliberate, not blockers for the goal): state save/open, image
  export, print, per-object color swatch row in the Objects panel.
- Emulator `emulator-5554` is currently running `-gpu swiftshader_indirect`. `adb forward tcp:9333`
  may still be set. Neither affects the repo.
- The `[MolApp][GL]` console log fires on every viewer init (one line, also on iOS console). Kept as a
  deliberate diagnostic; remove if judged noise.
