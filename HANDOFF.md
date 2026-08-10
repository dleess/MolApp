# HANDOFF: Play production 1.1.4 approved and LIVE worldwide — nothing in flight

**Written:** 2026-08-10 · **Working dir:** `/Users/donghanlee/work/projects/molapp` · **Branch:** `handoff-refresh` (clean, at `d46aeca` = master `727bffe` + the previous handoff refresh)

> The session that wrote this file made **zero repo edits** — its only work was in the Play Console
> (browser automation) plus updating the `molapp-play-store-status` memory. The working tree is clean.
> This replaces the 2026-08-04 handoff (committed as `d46aeca`).

## Goal

There is no active task. "Done" for whoever picks this up is one of the items under **Next steps** — the
single open verification, or one entry from the visual-QA backlog, which has now been carried unstarted
across three handoffs (since 2026-07-27).

## Status

- `master` = `727bffe`, working tree clean. No uncommitted edits, no debugging leftovers, no branch in flight.
- **All CI green on master.** `flutter` workflow run `30908803643`: `analyze`, `android`, `apple`, `linux`,
  `windows` all success. `linux` workflow run `30905054149`: `test`, `package` both success.
- Five shells over one shared web core (`viewer.html`), all currently building:

  | target | shell | distributable | state |
  | --- | --- | --- | --- |
  | iOS | SwiftUI + `WKWebView` (`MolApp/`) | App Store | 0.3 live; 0.4+ to ship (see `molapp-appstore-status` memory) |
  | Android | Flutter + `flutter_inappwebview` (`flutter_app/`) | Play — **production LIVE worldwide since 2026-08-10** | 14 (1.1.4) promoted from Alpha, approved same day; store page returns 200 anonymously |
  | Linux | GTK 3 + WebKitGTK 4.1, pure Python (`linux/`) | `.deb` via `linux/packaging/build-deb.sh` | merged #38/#39, verified on Ubuntu 24.04 |
  | macOS | Flutter (`flutter_app/`) | DMG via `flutter_app/macos/packaging/build-dmg.sh` | merged #40, 1.1.4 DMG mounts and runs |
  | Windows | Flutter (`flutter_app/`) | zip via `flutter_app/windows/packaging/build-zip.ps1` | merged #40; CI unpacks and launches `molapp.exe`, nothing drives the UI there |

## Next steps

1. ~~Confirm the production review cleared~~ **Done 2026-08-10:** Alpha's `14 (1.1.4)` was promoted to
   Production (track id `4698130211706379643`, all 176 countries + rest of world), passed review the same
   day, and `https://play.google.com/store/apps/details?id=com.donghan.molapp` now serves the full listing
   to an anonymous curl (200). Play Console account slot is **u/0** (u/1 is kbsi.bionmr, ToS gate);
   credentials live in the `molapp-play-store-status` memory, not in the repo.
2. **The visual-QA backlog**, still none of it started, ordered by user harm. Acceptance for any of it:
   `cd flutter_app && flutter analyze` clean, `flutter test` passing, plus device evidence for anything
   that changes layout or colour.
   1. **Objects panel accessibility.** Zero `Semantics` wrappers, so the eye, colour swatch and
      Rib/Sur/Stk/B+S/Sph chips are exposed as `StaticText` and **VoiceOver cannot operate the panel**.
      Touch targets there are 15x15, 14x14 and ~27x20 pt against a 44 pt minimum. Largest known
      user-facing problem.
   2. **Help is undiscoverable on iPhone portrait.** Reachable only by an undiscoverable horizontal swipe
      of the menu row, with a `{{0,0},{0,0}}` accessibility frame, and it is the only route to the Manual.
      Portrait-only: in landscape `isCompact` is false (874 >= 700) so all six menus lay out, Help at
      `{{478.17,14},{64,48}}`.
   3. **The left rail needs a scroll in landscape.** With the 21 pt bottom inset the rail is 161 pt against
      a 191 pt info card, so on a rotated phone the card's last row (PDB ID / Load PDB) is cut off and there
      is no scroll affordance. There is genuinely not room for both at natural size (161–182 pt of rail vs
      249 pt of content), so something must give; reducing the rail's `bottom: 120` buys ~24 pt but shifts
      the objects panel on every device — a look change, and therefore a maintainer's call.
   4. **Mol\* chrome leaking.** `MolApp/Resources/viewer.html:2291-2305` sets seven viewport flags false but
      not `ShowReset`, `ShowToggleFullscreen`, `ShowIllumination` or `ShowXR`. Confirmed on every platform
      including Windows. The axis gizmo also sits behind the command bar below ~660 pt, and the `.msp-logo`
      molstar.org link shows while the scene is empty — i.e. in the launch state.
   5. **Measure-banner contrast.** 4.1:1 on the default background, 2.6:1 on white. White on Material blue
      is 3.1:1 at full opacity, so this needs a hue change, not an alpha change. Same for the run button's
      accent: stock `Colors.blue` while the `ColorScheme` is seeded from Okabe-Ito `#0072B2` — two unrelated
      blues on screen at once.

## Key files & commands

- `flutter_app/` — Android/macOS/Windows shell. `cd flutter_app && flutter analyze` → `No issues found!`;
  `flutter test` (run from `flutter_app/`, **not** the repo root) → 122 passing as of `851555e`; not re-run
  since, though CI's `analyze` job is green on `727bffe`.
- `flutter_app/lib/src/molstar_web_view.dart` — `viewerWebViewSettings()` (`@visibleForTesting`) holds the
  Android/iOS split for the scroll flags; its doc comment records why. `_bridgeUserScriptSource` is where
  JS-bridge instrumentation goes if the touch path needs debugging again.
- `flutter_app/pubspec.yaml` — `version: 1.1.4+14`. Both packaging scripts read the version from here.
- `MolApp/Resources/viewer.html` — the shared web core, used unchanged by all five shells. iOS registers
  `window.webkit.messageHandlers.molapp` on `WKWebView`; WebKitGTK exposes the same channel, which is why
  the Linux shell needed no bridge changes.
- `linux/` — GTK shell (Python, no build step). Tests: `linux/tests/test_logic.py` (43 logic tests) and
  `linux/tests/test_smoke.py` (8 end-to-end, boot the real WebKitGTK view and real Mol\* bundle, headless
  under Xvfb in CI). Both prefer an already-importable `molapp` so they can run against an installed package.
- `linux/packaging/build-deb.sh` → `linux/dist/molapp_<version>_all.deb`. Code lands in `/usr/lib/molapp`,
  web core in `/usr/share/molapp/web` (already the third path `viewer_html_path()` checks).
- `flutter_app/macos/packaging/build-dmg.sh`, `flutter_app/windows/packaging/build-zip.ps1` → gitignored
  `flutter_app/dist/`.
- Release AAB: `cd flutter_app && flutter build appbundle --release` → 55.1 MB at
  `build/app/outputs/bundle/release/app-release.aab`.
- Android emulator: SDK at `~/Library/Android/sdk` (**not on `PATH`**), AVD `test36` (API 36), package
  `com.donghan.molapp`, launch with `adb shell am start -W -n com.donghan.molapp/.MainActivity`.
  `adb shell monkey` silently fails.
- iOS release/versioning procedure lives in the `ship` skill. App Store Connect API key details are in the
  `appstore-connect-creds` memory.

## What worked (keep doing)

All of this is merged; the tree state note applies to the working tree, which is clean.

- **Pixel-diffing two `adb exec-out screencap -p` captures** over the viewport crop `(0,950)-(1080,1750)`
  with a per-channel-sum threshold of 12. Binary evidence, no eyeballing. **[nothing left applied]**
- **Reverting a fix and rebuilding to prove causality.** For the Android touch bug this produced
  108 `touchmove` / 19.8% pixels changed with the fix vs **0 / 0.00%** with it reverted. **[reverted]**
- **Temporary JS-bridge instrumentation** — a listener in `_bridgeUserScriptSource` logging
  `console.log('MOLDBG ' + t)` for touch/pointer events, read back with `adb logcat -d | grep MOLDBG`.
  **[reverted — not in the merged code]**
- **Proving a package by unpacking it elsewhere and launching *that* copy**, which is what the CI packaging
  jobs do. An archive that unpacks but cannot find its Mol\* assets passes a plain build and fails on the
  first user's machine. **[still applied — in `.github/workflows/`]**
- **Native macOS file dialog: type the path one character at a time** (see below). Only method that worked
  for the Play upload. **[nothing left applied]**
- **Promoting a test release to Production needs no re-upload** — on the Alpha track page (2026-08-10),
  release row ▸ "Promote release" ▸ Production carried the bundle, release name and notes over verbatim.
  The only blocker was the production track having **0 countries** ("No countries or regions have been
  selected for this track"); the error's own "Add countries / regions" link ▸ header select-all checkbox ▸
  Save fixed it, then Save the release, then Publishing overview ▸ "Submit 3 changes for review" (the
  release + 2 country entries). **[still applied — it's Play Console state, not repo state]**

## What didn't work (don't repeat)

- **The Chrome the session attaches to may be the wrong browser.** Two have been seen connected: `Browser 1`
  (`ce25cb43-39d7-4290-b791-91f1c2c27fb7`, macOS, local) and `Browser 2`
  (`c060c9ce-1ce0-4e06-a928-c53a2284e94c`, Linux, remote). A session defaulted to the **Linux** one, so
  clicking Upload opened a file dialog no local AppleScript could see, and the Play Console tab never
  appeared in the local Chrome's tab list. `list_connected_browsers` → `select_browser` with the macOS
  deviceId. **Check this first.** (On 2026-08-10, after `open -a "Google Chrome" <url>`, only the local
  macOS browser was listed — the local one appears only while Chrome is actually running.)
- **`mcp__claude-in-chrome__file_upload` cannot carry an AAB** — 10 MB payload cap, bundle is 55.1 MB. The
  native dialog is the only route.
- **Fast synthetic typing into the macOS open panel silently drops characters.** `keystroke "/Users/dongha…"`
  in one call produced `/e/Downloads/molapp-1.1.4-14.aab`. Type character-by-character with `delay 0.08`.
- **`keystroke "a" using {command down}` then Delete does not clear that panel's field.** Press
  `key code 51` ~90 times instead.
- **`entire contents of sheet 1` exposes no settable text field for the Go-to-folder panel**; `set value of`
  errors with *"Can't make item 1 … into type specifier"*, and there are no AX `buttons`. AX inspection
  finds things there; it cannot drive them.
- **Two Returns after typing the path overshoots** — lands on `Macintosh HD`. Exactly **one** Return selects
  the file (Open lights up), then one more presses Open.
- **`System Events` clicks and type-ahead do not reach the open panel's file list.**
- **A `Bash` tool timeout killed the emulator** — a foreground `adb shell ping` hit the 2-minute limit and
  SIGTERM took the emulator with it. Launch detached (`nohup … & disown`), not via `run_in_background`
  alongside long foreground commands.
- **Swiping near the right screen edge (x≈1000 of 1080) does nothing** — Android gesture nav eats it as a
  back gesture. Drag through the middle.
- **After any revert-to-prove experiment, reinstall the fixed build before asking anyone to look.** A user
  test failed once purely because the last APK installed was the deliberately-reverted one.
- **Flutter on Linux was a dead end and should not be retried.** `flutter_inappwebview_linux` renders through
  WPE WebKit 2.40+, which no current Ubuntu ships (jammy was last, at 2.36), and Flutter's Linux embedder has
  no platform views — a GTK webview must float *above* the Flutter surface in a `GtkOverlay`, putting every
  menu and panel behind the full-bleed viewport. Hence the separate GTK shell in `linux/`.
- **A directory-wide integration-test run on macOS dies on the second file** — it cannot relaunch the app.
  CI runs one file per step.
- **`timeout … molapp; test $? -eq 124` under `set -e`** aborts before the test; the expected non-zero exit
  kills the step first (fixed in #39, noted here because it will bite again).

## Open questions / risks

- ~~Production review outcome~~ **Resolved 2026-08-10** — approved and live worldwide the same day it was
  submitted; store page confirmed publicly reachable. No Play item remains open; the visual-QA backlog is
  now the only outstanding work.
- **iOS has not been re-tested since the Android touch fix.** The change is a no-op there by construction
  (`disableVerticalScroll: !isAndroid` keeps the old values) and a widget test pins it, but no iOS device run
  was done.
- **Nothing drives the Windows UI in CI** — the package is unpacked and `molapp.exe` is launched, and that is
  all. Windows UI regressions would not be caught.
- **`flutter test` has not been run locally since `851555e`** (122 passing there). CI's `analyze` job is green
  on `727bffe`; treat the count as unverified at head.
- **A second Claude Code session running on this Mac steals focus** and made the GUI keystroke work flaky
  during the Play upload. If AppleScript misbehaves, check for that first.
- The `test36` emulator was last left with the **fixed** debug APK installed (verified 2026-08-04 by an
  18.79% rotation run). Unverified since.
- `plan.md` and `tasks/prd-ipados-molstar-molecule-viewer.md` describe the original iPadOS scope. They are
  historical — the app has since grown four more shells — and neither has been updated to match.
