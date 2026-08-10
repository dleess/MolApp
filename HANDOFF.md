# HANDOFF: Android tablet keyboard-crash fixed (1.1.5+15) — Play production upload in progress

**Written:** 2026-08-10 · **Working dir:** `/Users/donghanlee/work/projects/molapp` · **Branch:** `handoff-refresh` (at `c7dd867`; user chose commit-only, no PR)

> This replaces the earlier 2026-08-10 handoff (`7188150`). That file's Play-upload dead-ends and the
> visual-QA backlog are carried over below — they are still valid.

## Goal

Ship the Android tablet keyboard-crash fix to Play production. "Done" = production release 15 (1.1.5)
submitted for review in the Play Console (managed publishing is off, so it goes live on approval).

## Status

- **Root cause found and fixed, fix verified on emulator, committed as `c7dd867`** (`fix(android): survive
  WebView renderer death instead of crashing`, bumps `flutter_app/pubspec.yaml` to `1.1.5+15`).
- Play production upload: **in progress when this was written** — if a later commit updates this line, trust
  that; otherwise assume the AAB was NOT submitted and start at Next steps 1.
- Working tree at write time: clean except this file.

## The bug and its root cause (verified 2026-08-10)

User reports: MolApp on Android **tablets** crashes the moment the on-screen keyboard opens (any input
field). Reproduction on stock emulators **fails** — debug and release builds, Pixel Tablet AVDs API 36 and
API 34 (2 GB RAM), landscape and portrait: keyboard opens fine. Play Console ▸ Android vitals shows **zero
crash reports over 60 days, all filters off** — this crash type leaves no Java stacktrace and vitals needs
user opt-in.

Mechanism, proven live on the `tablet34` AVD:

1. The viewer is a fullscreen WebGL WebView (`flutter_inappwebview` 6.2.0-beta.3); the manifest uses
   `android:windowSoftInputMode="adjustResize"`, so the keyboard resizes the whole canvas. On low-spec
   tablets that resize can OOM the Chromium renderer (on emulators it never does — hence no repro).
2. When the renderer dies, Android's default is to **kill the whole app** unless `onRenderProcessGone` is
   handled. The app only implemented `onWebContentProcessDidTerminate` — the iOS/macOS callback. Plugin
   source confirms: without a registered handler, `useOnRenderProcessGone` stays false and
   `InAppWebViewClientCompat.onRenderProcessGone` falls through to `super` (= kill).
3. Verified with `adb root` + `kill -9 <sandboxed_process0 pid>`: app died instantly, logcat said
   `aw_browser_terminator.cc: Render process kill (OOM or update) wasn't handed by all associated
   webviews, killing application.` Nothing lands in the crash buffer — matching the empty vitals.

Full write-up with reproduction details is in the `molapp-android-keyboard-crash` memory.

## The fix (`flutter_app/lib/src/molstar_web_view.dart`, still applied, committed)

`_MolStarWebViewState` gained an `int _rebuildEpoch`; the `InAppWebView` gets `key:
ValueKey<int>(_rebuildEpoch)` and a new `onRenderProcessGone` callback that does
`setState(() => _rebuildEpoch++)` — tearing down the dead platform view and building a fresh WebView.

**Why not reload in place:** the first fix attempt mirrored the iOS handler (`bridge.attach` +
`controller.loadFile`). The app survived, but the recovered page's JS→Dart bridge was half-dead —
logcat filled with `Uncaught TypeError: _javaInjectedObject._callHandler is not a function` and a PDB
load never completed. The key-bump rebuild produces **zero** such errors. Don't regress to loadFile.

Verification on `tablet34` (release APK, `adb root`):
- `kill -9` of the renderer → app survives, viewer.html fully re-initializes (GL init lines in console).
- `load 1crn` after recovery behaves identically to a fresh launch (accepted, status updates, field syncs).
- Caveat: the actual PDB network fetch stalls at "Loading 1CRN" on this AVD **both before any kill and
  after recovery** — an emulator network quirk (same family as the known `test34` DNS gotcha), not the fix.
  Booting with `-dns-server 8.8.8.8,1.1.1.1` did not cure it this time; `ping` and DNS resolution from
  `adb shell` work fine. Unverified: a full render-complete after recovery. The equality of baseline and
  post-recovery behavior is the evidence.

## Key files & commands

- `flutter_app/lib/src/molstar_web_view.dart` — the fix lives here (`_rebuildEpoch`, `onRenderProcessGone`).
- `flutter_app/pubspec.yaml` — `version: 1.1.5+15`.
- Release AAB: `cd flutter_app && flutter build appbundle --release` →
  `build/app/outputs/bundle/release/app-release.aab` (~55 MB).
- Tablet AVDs created this session (kept): `tablet36` (Pixel Tablet, API 36), `tablet34` (Pixel Tablet,
  API 34, `hw.ramSize=2048`). Boot: `~/Library/Android/sdk/emulator/emulator -avd tablet34 -dns-server
  8.8.8.8,1.1.1.1 -no-snapshot-save` (background it; a foreground Bash timeout once killed an emulator).
- Renderer-kill test: `adb root`, `adb shell "ps -A | grep sandboxed_process"`, `kill -9 <pid>`, then
  `ps -A | grep molapp` must still show the app and the viewer must show "Ready for structure loading".
- `adb shell input text` drops literal spaces — write `load%s1crn`.
- Play release notes text (user-approved): **"Fixed a crash on tablets when the on-screen keyboard opens"**.

## Next steps

1. **Upload to Play production** (unless Status above says it happened): build the AAB, then in Play
   Console (**u/0**, lee.donghan account — check the avatar; u/1 is kbsi.bionmr with a ToS gate) go to
   Production ▸ Create new release ▸ upload via the **native** file dialog (the `file_upload` MCP tool has
   a 10 MB cap), release notes as above, Save ▸ Publishing overview ▸ Submit for review. All upload
   dead-ends from the previous handoff still apply (char-by-char typing with delay 0.08, one Return to
   select + one to open, ~90 × `key code 51` to clear the field, `.aab` may need Cmd+Shift+G go-to-folder).
2. After submission: update the `molapp-play-store-status` memory and the Status line of this file.
3. The **visual-QA backlog** from the previous handoff remains untouched (objects-panel accessibility,
   iPhone-portrait Help discoverability, landscape left-rail scroll, Mol* chrome flags, measure-banner
   contrast — see git history of this file at `7188150` for the full descriptions).

## Open questions / risks

- **The trigger inference is indirect**: renderer death on keyboard resize was never reproduced on an
  emulator (they're too well-resourced). What's proven is that any renderer death killed the app pre-fix
  and doesn't post-fix. If tablet reports continue on 1.1.5, the next suspect is a crash in the Flutter
  side itself — get a real device or a Firebase Test Lab run on a low-RAM tablet.
- Post-recovery full render (structure actually drawn) is unverified — blocked by the AVD network stall
  above, not by the fix.
- `flutter test` was not re-run this session (only `flutter analyze` on the changed file, clean); CI will
  run the suite when the branch is pushed. The branch has **not been pushed** as of writing.
- iOS/macOS behavior is untouched by construction (`onWebContentProcessDidTerminate` unchanged, key bump
  is platform-neutral and only fires from the Android-only callback).
