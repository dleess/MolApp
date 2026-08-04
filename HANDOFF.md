# HANDOFF: Android touch rotation fixed and shipped as 1.1.4 (build 14) — in Play review

**Written:** 2026-08-04 · **Working dir:** `/Users/donghanlee/work/projects/molapp` · **Branch:** `master` (clean; PR #36 merged as `851555e`)

> Replaces the 2026-07-27 HANDOFF (`git show fa1cf8e:HANDOFF.md`). That file's **"Next steps" backlog is still
> open and unstarted** — accessibility of the objects panel, Help undiscoverable on iPhone portrait, the
> landscape left-rail scroll, Mol\* chrome leaking, measure-banner contrast. Read it if you pick any of those up.

## Goal

Report: "Android에서 터치로 molecule이 회전이 안 된다." Done = rotation works, verified on the emulator,
uploaded to Google Play, and submitted for review.

**All of that is done.** Nothing is in flight.

## Status

- Fix merged to `master` (`851555e`, PR #36). Working tree clean, no debugging leftovers.
- `cd flutter_app && flutter analyze` → `No issues found!`; `flutter test` → **122 passing** (was 120; 2 new).
- All five CI jobs passed on #36 (run `30865531304`).
- Play Console: **Closed testing "Alpha", release 7 = `14 (1.1.4)`, "Changes in review"** as of 2026-08-04
  ~09:55. Quick checks were running with ~13 min remaining; changes are sent to review automatically once
  they pass. Not verified past that point.

## The bug and its root cause

`flutter_inappwebview`'s Android `OnTouchListener` returns `true` for **every** `ACTION_MOVE` when
`disableHorizontalScroll` **and** `disableVerticalScroll` are both set:

```java
// ~/.pub-cache/hosted/pub.dev/flutter_inappwebview_android-1.2.0-beta.3/android/src/main/java/
//   com/pichillilorenzo/flutter_inappwebview_android/webview/in_app_webview/InAppWebView.java:556-557
if (customSettings.disableHorizontalScroll && customSettings.disableVerticalScroll) {
  return (event.getAction() == MotionEvent.ACTION_MOVE);
}
```

Consuming the event means the WebView never delivers `touchmove` to the page, so the Mol\* camera has nothing
to act on. Taps still worked (that is why a click could still focus a residue) — only drags died. iOS uses a
different scrollView path and was never affected.

**Fix** (`flutter_app/lib/src/molstar_web_view.dart`): the settings moved into a new
`viewerWebViewSettings()` (`@visibleForTesting`) that drops both flags on Android only —
`disableVerticalScroll: !isAndroid`. `viewer.html` already pins scrolling itself (`overflow: hidden`,
`touch-action: none`, `user-scalable=no`), so nothing scrolls that shouldn't. **[still applied]**

## Evidence (API 36 emulator `test36`, 1CRN loaded, drag `adb shell input swipe 700 1500 300 1200 900`)

| build | `touchmove` reaching the canvas | viewport pixels changed |
| --- | --- | --- |
| fixed | 108 | 19.8% (and 18.79% on a second run after reinstall) |
| flags restored (deliberately reverted, then rebuilt) | **0** | **0.00%** |

Scale is identical before/after and the axis gizmo rotates with the scene, so it is rotation, not zoom.
The user independently confirmed rotation on the emulator ("확인 했슴. 방향 바뀜").

## What worked

- **Instrumenting the JS bridge to find the failing layer.** A temporary listener in
  `_bridgeUserScriptSource` logging `console.log('MOLDBG ' + t)` for touch/pointer events, read back with
  `adb logcat -d | grep MOLDBG`, proved the moves reach `target=CANVAS` after the fix and never arrive
  before it. **[reverted — the instrumentation is gone from the merged code]**
- **Reverting the fix and rebuilding to prove causality** (0 moves, 0 pixels). This is what produced the
  table above. **[reverted — the fix is back in place and merged]**
- **Pixel-diffing two `adb exec-out screencap -p` captures** over the viewport crop `(0,950)-(1080,1750)`
  with a per-channel-sum threshold of 12. Binary, no eyeballing.
- **Native macOS file dialog: type the path one character at a time.** See below — this is the only method
  that worked.

## What didn't work

- **The Chrome the session was attached to was the wrong browser.** Two browsers are connected: `Browser 1`
  (`ce25cb43-39d7-4290-b791-91f1c2c27fb7`, macOS, local) and `Browser 2`
  (`c060c9ce-1ce0-4e06-a928-c53a2284e94c`, Linux, remote). The session defaulted to the **Linux** one, so
  clicking Upload opened a file dialog that no local AppleScript could see and the Play Console tab never
  appeared in the local Chrome's tab list. `list_connected_browsers` → ask the user → `select_browser` with
  the macOS deviceId. **Check this first next time.**
- **`mcp__claude-in-chrome__file_upload` cannot be used for an AAB** — it caps the combined payload at 10 MB
  and the bundle is 55.1 MB. The native dialog is the only route.
- **Fast synthetic typing into the macOS open panel silently drops characters.** `keystroke "/Users/dongha…"`
  in one call produced `/e/Downloads/molapp-1.1.4-14.aab`. Type character-by-character with a `delay 0.08`
  between them and it lands perfectly.
- **`keystroke "a" using {command down}` then Delete does not clear that panel's field.** Press
  `key code 51` ~90 times instead.
- **`entire contents of sheet 1` exposes no settable text field for the Go-to-folder panel**, and
  `set value of` on it errors with *"Can't make item 1 … into type specifier"*. There are no AX `buttons`
  either. AX inspection is useful for *finding* things, not for driving this dialog.
- **Two Returns after typing the path overshoots** — it lands on `Macintosh HD`. Exactly **one** Return
  selects the file (Open lights up), then one more Return presses Open.
- **`System Events` clicks and type-ahead do not reach the open panel's file list.** `click at {x,y}` on a
  row, then typing the filename, selected nothing.
- **A `Bash` tool timeout killed the emulator.** The foreground `adb shell ping` hit the 2-minute limit and
  SIGTERM took the emulator with it. Launch it detached: `nohup … & disown`, not via `run_in_background`
  alongside long foreground commands.
- **Swiping near the right screen edge (x≈1000 of 1080) does nothing** — Android gesture navigation eats it
  as a back gesture. Drag through the middle of the screen.
- **The user's own emulator test failed at one point and it was my fault** — the last APK installed was the
  deliberately-reverted build. After any revert-to-prove experiment, **reinstall the fixed build before
  telling anyone to look.**

## Key files & commands

- `flutter_app/lib/src/molstar_web_view.dart` — `viewerWebViewSettings()` holds the platform split; its doc
  comment records why. `_bridgeUserScriptSource` is where instrumentation goes if this needs debugging again.
- `flutter_app/test/molstar_web_view_test.dart` — 2 tests pinning the flags per platform via
  `debugDefaultTargetPlatformOverride`. Revert the fix and they fail.
- `cd flutter_app && flutter analyze` → `No issues found!` · `flutter test` → 122 passing (run from
  `flutter_app/`, not the repo root).
- Emulator: SDK at `~/Library/Android/sdk` (**not on `PATH`**), AVD `test36` (API 36), package
  `com.donghan.molapp`, launch with `adb shell am start -W -n com.donghan.molapp/.MainActivity`.
  `adb shell monkey` silently fails.
- Release build: `cd flutter_app && flutter build appbundle --release` → 55.1 MB at
  `build/app/outputs/bundle/release/app-release.aab`. Version lives in `flutter_app/pubspec.yaml`
  (`version: 1.1.4+14`).
- Play Console credentials/account details are in the `molapp-play-store-status` memory, not in the repo.
  Account slot **u/0** was correct today (u/1 is kbsi.bionmr and hits a ToS gate).

## Next steps

1. **Confirm the review cleared.** Publishing overview for MolApp; it should move from "Changes in review"
   to available-to-testers. Quick checks were ~13 min out at 09:55 on 2026-08-04.
2. If a rebuild is ever needed, note the AAB was staged at `~/Desktop/molapp-1.1.4-14.aab` **and**
   `~/Downloads/molapp-1.1.4-14.aab` (the Downloads copy exists only because the file dialog was already
   there). Both are outside git; delete freely.
3. The 2026-07-27 backlog is untouched — see the quote at the top of this file.

## Open questions / risks

- **The review outcome is unverified.** Submission succeeded; approval had not happened when this was written.
- **iOS was not re-tested.** The change is a no-op there by construction (`!isAndroid` keeps the old values)
  and the widget test pins it, but no iOS device run was done today.
- **A second Claude Code session was running on this Mac** during the upload and repeatedly stole focus,
  which is part of why the keystroke work was so flaky. If GUI scripting misbehaves, check for that first.
- The emulator currently has the **fixed** debug APK installed (verified by the 18.79% rotation run).
