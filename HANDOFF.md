# HANDOFF: Samsung Flip foldable fix shipped to master; Android 1.0.4 built but not uploaded to Play

**Written:** 2026-07-22 · **Working dir:** `/Users/donghanlee/work/projects/molapp` · **Branch:** `master` (synced to `origin/master`, HEAD `0ba6b3c`)

## Goal
User report: "samsung flip 에서 큰화면과 작은 화면으로 왔다 갔다 할때 molecule이 사라진다. 큰화면과 작은 화면을 바꾸더라도 같은 줌 상태로 보이게 해."

Done = folding/unfolding no longer clears the viewer, and the camera (zoom + rotation) is identical before and after. **Met** — verified on the emulator, not on physical Flip hardware.

## Status
**Code work 100% done and merged. Two PRs landed this session; nothing is left half-applied.**
- `5f9880b` PR #17 — the foldable fix (`AndroidManifest.xml`, 1 line). **[still applied, merged]**
- `0ba6b3c` PR #18 — API 36 toolchain + version bump that had been sitting uncommitted in the tree from an earlier session. **[still applied, merged]**
- Working tree: only this `HANDOFF.md` rewrite. No debugging leftovers, no temporary logging, no reverted-but-not-restored edits.
- The `test34` emulator was used for verification and is **SHUT DOWN** (`adb emu kill`).
- **Not shipped anywhere.** Android 1.0.4 / versionCode 3 exists only as source — no AAB built, no Play upload. iOS untouched (`project.pbxproj` still `MARKETING_VERSION = 1.0.3`, `CURRENT_PROJECT_VERSION = 9`).

## What worked
- **Root cause via `configChanges`.** `MainActivity` declared `android:configChanges="orientation|screenSize|keyboardHidden"`. A fold/unfold also changes `smallestScreenSize`, `screenLayout` and `density`; undeclared changes make Android recreate the activity, and `MainActivity.onCreate` builds a fresh `WebView` + reloads `viewer.html`, so the structure and the Mol* camera are gone. Fix = declare them: `android/app/src/main/AndroidManifest.xml:16` is now `orientation|screenSize|smallestScreenSize|screenLayout|density|uiMode|keyboardHidden`. No Kotlin and no `viewer.html` change was needed — if the activity survives, the camera is simply never touched. **[still applied]**
- **Reproducing a fold on a non-foldable emulator:** `adb shell wm size 720x1600` / `adb shell wm size reset`. Same class of configuration change, and it reproduced the bug exactly (viewer reset to "Ready for structure loading" / "No objects").
- **Two cheap recreation detectors** (no instrumentation needed, this is how the before/after was proven):
  - `adb logcat -d | grep -c "MolApp\]\[GL\] webgl2"` — `viewer.html` logs a WebGL probe line on every init, so a non-zero count after a resize means the WebView reloaded.
  - `adb logcat -d | grep -i "finishDrawing of relaunch"` — WindowManager logs the activity relaunch. **Filter by package**; other apps on the emulator (`treasurehunter`, `permissioncontroller`) relaunch too and produced a false positive once.
- **Before/after evidence:** before the fix, one resize → 1 GL re-init + `finishDrawing of relaunch: ... com.donghan.molapp/.MainActivity`, viewer empty. After: large→small, small→large, and resize-while-backgrounded all give 0 re-inits, 0 relaunches, and the restored screenshot is pixel-identical to the pre-resize one (the molecule had been rotated first, so this proves camera state, not just "something rendered").
- Build + install loop: `cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew assembleDebug` then `adb install -r app/build/outputs/apk/debug/app-debug.apk`. `./gradlew clean assembleDebug` also passes on the new AGP 8.9.2 / Gradle 8.11.1 / API 36 toolchain.

## What didn't work
- **PDB-ID loading is impossible on this emulator.** The WebView is Chromium 113 and `https://files.rcsb.org` fails the TLS handshake: `ERROR:ssl_client_socket_impl.cc(992) handshake failed; returned -1, SSL error code 1, net_error -202` (`ERR_CERT_AUTHORITY_INVALID`). Status sticks at "Loading 1CRN" forever. Don't retry PDB-ID loads here — push a local file instead (below). Not a code bug; the host fetches the same URL fine (`curl` → 200).
- **A hung network load poisons every later load.** `viewer.html` serializes commands through `nativeCommandQueue`, so after the failed 1CRN fetch a *local* file load also hung at "Loading 1CRN.pdb" for 60+ s. Fix: `adb shell am force-stop com.donghan.molapp` and relaunch before loading locally. This cost ~10 min before it was understood.
- **Booting `test34` plainly gives no DNS** (already in memory, re-confirmed): boot it as `emulator -avd test34 -no-snapshot-load -no-boot-anim -dns-server 8.8.8.8,1.1.1.1`. Even then ICMP is blocked, so a `ping` "failure" is not evidence of anything — but DNS resolution does work.
- **`adb shell ping ...` wedged the foreground bash call** (2-minute timeout, exit 143), and `timeout` is not on this macOS PATH. Use `adb shell sleep N` for waits instead; that behaved.
- **Pinch-zoom cannot be driven from `adb`** (`input swipe` is single-touch). Worked around by dragging to rotate the molecule first — camera preservation is then visible in the screenshot without needing to change zoom.

## Key files & commands
- `android/app/src/main/AndroidManifest.xml:16` — the fix lives here, one attribute.
- `android/app/src/main/java/com/donghan/molapp/MainActivity.kt:72` `onCreate` / `:109` `createWebView` — where the WebView is created and, before the fix, recreated. `:271` `onDestroy` destroys it.
- `MolApp/Resources/viewer.html` — shared web core and the single source of truth; Android copies it at build via the `copyWebAssets` Gradle task (`android/app/build.gradle:59`), and `android/app/src/main/assets/` is gitignored. **Edit only the `MolApp/Resources/` copy.**
- `emulator -avd test34 -no-snapshot-load -no-boot-anim -dns-server 8.8.8.8,1.1.1.1` — boot. `adb`/`emulator` are not on PATH; they live under `~/Library/Android/sdk/{platform-tools,emulator}/`.
- Load a structure offline: `adb push <local>.pdb /sdcard/Download/` then in-app **Open Structure** → Downloads → tap the file. On a 1080x2400 emulator the taps were: Open Structure `(262, 518)`, first file tile `(296, 908)`. Rendering 1CRN takes ~20 s on the software GL emulator.
- Play release build: `cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew bundleRelease` → `android/app/build/outputs/bundle/release/app-release.aab`. Signing creds are read from `~/.gradle/gradle.properties`; keystore details live in the `molapp-play-store-status` memory file, not in git and not repeated here.

## Next steps
1. **Confirm on real Flip hardware.** This is the one thing that could not be checked. If the molecule still clears there, read the risk below before writing any code.
2. **Ship Android 1.0.4** if the user wants it out: `./gradlew bundleRelease`, upload versionCode 3 to Play. Play rejects `targetSdk < 35`; we are on 36, so that is fine. A rejected upload still burns its versionCode.
3. **Check the 1.0.3 App Store review outcome** — it was `WAITING_FOR_REVIEW` as of 2026-07-19 and nobody has polled since. The `molapp-appstore-status` memory has the version/submission ids and the polling flow. If iOS ships next it is 1.0.4 / build 10+, and `MARKETING_VERSION` must be sed-edited in `MolApp.xcodeproj/project.pbxproj` (agvtool does not apply it).
4. **Check Play closed-testing opt-in progress** (7/12 testers as of 2026-07-20; production access needs ≥12 for ≥14 days).

## Open questions / risks
- **Physical Flip behaviour is UNVERIFIED.** The emulator resize is the same class of configuration change, but the Flip's cover screen ↔ main screen is also a *display* switch, and some OEM display switches relaunch the activity regardless of `configChanges`. If that turns out to be the case, the next lever is retaining the `WebView`/`MolStarBridge` in a `ViewModel` so it survives recreation — a `WebView` held there must not leak the Activity context. Process death (fold, leave it folded, system kills the app) is covered by nothing and would need real state save/restore through the existing `serializeMolAppState` / `loadState` bridge round-trip.
- **Small viewports are heavily occluded.** At 720x1600 the info card (top) and the objects panel (bottom) cover most of the canvas; on a Flip cover screen the molecule could be largely hidden behind them and *read* as "disappeared" even though it is rendering. Deliberately left alone — that is a layout question, not this bug. If the user reports it again, collapsing those panels below some width is the change.
- **iOS was not touched and not re-tested.** The fix is Android-only by nature (a WKWebView is not destroyed by an iPad Split View resize), but that assumption was not exercised this session.
- Leftover on the emulator only: `/sdcard/Download/1CRN.pdb` was pushed for testing. Harmless, and the emulator is off.
