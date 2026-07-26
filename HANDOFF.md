# HANDOFF: safe-area fixes and chrome design tokens are merged; the visual-QA backlog is not

**Written:** 2026-07-26 · **Working dir:** `/Users/donghanlee/work/projects/molapp` · **Branch:** `master` — last code commit `894cc74`, with this file landing on top of it

> This replaces the previous HANDOFF (the Flutter port + 1.1.0 store submissions), still readable at
> `git show a52c114:HANDOFF.md`. **Its store-submission state was not re-checked today** — if you
> need it, treat it as of 2026-07-26 morning. Two of its open questions are now answered, under "CI".

## Goal

Nothing is in flight. Both of today's PRs are merged and `master` is green locally. The remaining
work is the visual-QA backlog under "Next steps" — none of it is started.

Acceptance for anything you pick up: `cd flutter_app && flutter analyze` clean and `flutter test`
→ 113 passing, plus device evidence for anything that changes layout or colour.

## Status

**Working tree clean.** No debugging leftovers anywhere in `flutter_app/`; every edit made today is
committed and merged.

Merged today:

| PR | Commit | What |
| --- | --- | --- |
| #23 | `5a82f3b` | `SafeArea` for the chrome + `_menuBarTop()` for iPadOS window controls; PDF export crash, unvalidated hex colours, stale command bar, enums drop their `raw` field |
| #24 | `894cc74` | `ChromeTokens` — the chrome's palette and type sizes in one file, then the drift collapsed |

Verified on `894cc74`: `flutter analyze` → `No issues found!`, `flutter test` → 113 passing. CI's
`analyze` job (which also runs the tests), `apple` and `android` are green on both PRs.

## What worked

- **`gh pr merge <n> --squash --delete-branch --admin`.** `--admin` was required on both PRs and
  will be required again — see CI. Record the reason in the merge body, as #23 and #24 do.
- **Golden-image diffing as the instrument for colour work.** `flutter test` renders text as boxes,
  but every colour, alpha, border and layout is exact — which is exactly what a palette change
  needs. The token extraction was proven byte-identical this way *before* the consolidation was
  allowed to change anything. Harness archived, see risks.
- **Choosing alpha values by computing WCAG contrast over all five `backgroundPresets`** instead of
  by eye. That produced scrim 0.85 and text 1.0 / 0.65 / 0.45, and it is why #24's body can state
  worst-case ratios rather than adjectives.
- **Reverting a fix to prove its test actually fails.** The banner regression test passed even with
  the fix reverted until the assertion was corrected — see "What didn't work".
- **`git apply --cached` with a hand-split patch** to put one hunk of a file in one commit and the
  rest in another; `git add -p` is interactive and blocked in this harness. Note the repo
  squash-merges, so per-branch atomic splits are discarded on merge anyway.
- **Android verification.** SDK is at `~/Library/Android/sdk` and is **not on `PATH`** — export
  `ANDROID_HOME` and add `platform-tools`/`emulator`. AVD `test36` is API 36, 1080x2400 @ density
  420. Android package id is `com.donghan.molapp` (lowercase); the iOS bundle id is
  `com.donghan.MolApp` (different casing). `adb shell monkey -p ... -c
  android.intent.category.LAUNCHER 1` silently fails — use
  `adb shell am start -W -n com.donghan.molapp/.MainActivity`.

## What didn't work

- **`SafeArea` alone does not fix iPadOS 26 windowed mode.** The system window-control pill is drawn
  *inside* the app's content at the top-leading corner and is **not** reported as an inset —
  measured on the simulator, `padding.left` stays 0 and `padding.top` is only ~9pt. Flutter surfaces
  no inset for it (`MediaQueryData` has only `viewInsets`, `padding`, `viewPadding`,
  `systemGestureInsets`). Hence `_menuBarTop()` in `flutter_app/lib/src/viewer_page.dart`, which
  returns 56 on an iOS *display* ≥600pt shortest side and 8 elsewhere. **Do not "simplify" it to
  `MediaQuery.sizeOf`** — in windowed mode that reports a window that can be phone-sized.
  **[still applied, on master]**
- **Synthetic input does not reach the Flutter macOS app.** `osascript` System Events `click at` +
  `keystroke` was accepted (window resize via System Events works, so accessibility is granted) but
  text never landed in the command bar — confirmed by a probe screenshot showing the untouched
  placeholder. Don't retry; use the iOS Simulator or the Android emulator for interaction testing.
  **[nothing applied]**
- **Sending Cmd+K to the Simulator went to the wrong app.** It landed in an unrelated foregrounded
  app and opened a dialog there. No damage, but **the software-keyboard state is still unverified on
  every platform**. **[reverted by relaunching MolApp]**
- **The Mac session locked partway through.** After that, `screencapture` returns
  `could not create image from rect`, `osascript ... activate` cannot foreground anything, and
  System Events reports 0 windows for a running app. macOS therefore has **no post-fix screenshot**.
  Those symptoms mean a locked display, not an app bug.
- **`ui_describe_all` returns `DockFolderViewService`, not the app**, when an iPad simulator is in
  iPadOS 26 windowed mode. Accessibility frames are unavailable there; fall back to pixel
  measurement and direct taps in **screen-space** (not window-relative) coordinates.
- **A regression test that asserted the wrong relation.** The first version used
  `banner.top >= menuBar.top` and passed even with the fix reverted. The shipped version is
  `banner.top >= file.bottom`, which fails at `Expected: >= 110.0 / Actual: 66.0` when reverted.
  If you touch it, re-verify by reverting the fix. **[corrected version on master]**
- **`dart format` must not be run.** There is no formatter config, so its default width is 80 while
  the codebase wraps at 102 — it would reformat every file. Wrap long lines by hand.
- **`flutter test` from the repo root** fails with `Test directory "test" not found.` Run it from
  `flutter_app/`.

## CI — read before merging anything

`analyze`, `apple` and `android` pass. **`linux` and `windows` have never passed** — not on any of
today's branches, not on `master`, not on any run of `flutter-multiplatform-port`. Neither reaches
app code:

- **linux** dies in `apt-get`: `E: Unable to locate package libwpewebkit-1.1-dev` (also
  `libwpebackend-fdo-1.0-dev`, `libwpe-1.0-dev`), exit code 100, before anything compiles. The
  package names in `.github/workflows/flutter.yml` are stale for the current `ubuntu-latest` image,
  and that file's own comment ("which is what Ubuntu actually ships") is out of date.
- **windows** dies inside the plugin: `flutter_inappwebview_windows_plugin.vcxproj` includes
  `<experimental/coroutine>` and MSVC 14.51 hard-errors with
  `error C2338: static assertion failed: 'error STL1011: ...'`.

This answers the previous HANDOFF's open question: the "5 platforms" claim remains **unverified for
Windows and Linux**, and the cause is toolchain rot rather than the app. Every PR will be red until
someone fixes the workflow's package list and pins or patches the Windows plugin.

## Key files & commands

- `flutter_app/lib/src/tokens.dart` — `ChromeTokens`, the single home for the viewport chrome's
  palette and type sizes. **Read its doc comment before changing a value**; it records what was
  consolidated, what was not, and why.
- `flutter_app/lib/src/viewer_page.dart` — the whole UI (menu bar, info card, objects panel, command
  bar, measure banner, hover tooltip, colour picker). Holds `_menuBarTop()` and the `SafeArea` that
  wraps the five chrome overlays. The viewport and the hover tooltip are deliberately **outside**
  that `SafeArea` — the tooltip's coordinates come from the webview and are in un-inset space.
- `MolApp/Resources/viewer.html` — the Mol\* viewport, single source of truth for all shells. The
  copies under `flutter_app/assets/web/` and `android/app/src/main/assets/` are generated; run
  `cd flutter_app && dart run tool/sync_web_assets.dart` after editing it.
- `cd flutter_app && flutter analyze` → `No issues found!`
- `cd flutter_app && flutter test` → `All tests passed!`, 113 tests.

## Next steps

None of these are started. Ordered by value:

1. **Objects panel accessibility.** Zero `Semantics` wrappers, so the eye, colour swatch and
   Rib/Sur/Stk/B+S/Sph chips are exposed as `StaticText` and **VoiceOver cannot operate the panel at
   all**. Touch targets there are 15x15, 14x14 and ~27x20 pt against a 44pt minimum. Biggest real
   user harm left.
2. **Help is effectively undiscoverable on iPhone.** Reachable only by an undiscoverable horizontal
   swipe of the menu row, and it reports a `{{0,0},{0,0}}` accessibility frame. It is the only route
   to the Manual (`viewer_page.dart` holds the sole `ManualPage` reference; there is no `help`
   command). Six labels total ~455pt against 402pt of screen, so this needs shrinking the labels or
   adding a scroll affordance — neither preserves the current look, which is why it was left.
3. **Mol\* chrome leaking through.** `MolApp/Resources/viewer.html:2291-2305` sets seven viewport
   flags false but not `ShowReset`, `ShowToggleFullscreen`, `ShowIllumination` or `ShowXR`, so a
   4-button strip renders at the right edge on every platform. Its axis gizmo also sits behind the
   command bar on windows narrower than ~660pt, and the `.msp-logo` molstar.org link shows while the
   scene is empty — which is the launch state.
4. **Fix the Linux and Windows CI jobs** so the two unverified platforms stop being unverified, and
   PRs stop needing `--admin`.
5. **The measure banner's contrast.** 4.1:1 on the default background, 2.6:1 on white. White on
   Material blue is 3.1:1 even at full opacity, so this needs a hue change, not an alpha change.
   Same for the run button's accent, which is stock `Colors.blue` while the `ColorScheme` is seeded
   from Okabe-Ito `#0072B2` — two unrelated blues on screen at once.

## Open questions / risks

- **The token consolidation changes pixels on purpose and has NOT been looked at on a real device.**
  Verified only by golden renders in `flutter test`. On the default `#0B0F14` the panels move
  ≤6/255 (imperceptible), but the text scale visibly changes: the command-bar placeholder and the
  "No objects"/type lines get brighter (white 0.4/0.45 → 0.65), and the hidden-eye and disabled-run
  icons get brighter (0.35/0.3 → 0.45). **If the user dislikes it, the whole change is three numbers
  in `tokens.dart`.**
- **Landscape on a notched iPhone leaves a 59pt gutter** at the left of the menu bar's background
  strip — a consequence of the `SafeArea` fix, measured by widget probe
  (`Rect.fromLTRB(59.0, 8.0, 874.0, 68.0)` at 874x402 with a 59pt left inset). Labels are positioned
  correctly; only the strip's fill is inset. **Unverified on a real device** — the Mac locked before
  the simulator could be rotated.
- **The soft-keyboard state is unverified on every platform.**
- **Evidence from today lives only in a session scratchpad and will disappear**:
  `/private/tmp/claude-501/-Users-donghanlee-work-projects-molapp/0e03801c-cc55-469d-9374-fdd862001630/scratchpad/`
  — `vqa/VISUAL-QA.md` (the full audit: 36 findings that survived adversarial verification, 17
  refuted), `vqa/FIX-REPORT.md`, ~25 before/after device captures, `g-orig/` vs `g-final/` golden
  pairs, and `zz_golden_test.dart.archived` (the golden harness — drop it into `flutter_app/test/`
  and run with `--dart-define=GOLDEN_DIR=<dir> --update-goldens` to regenerate). **Nothing in the
  repo depends on any of it.** Copy what you want to keep before the directory is reclaimed.
- **The 1.1.0 store submissions were not touched or checked today.** See
  `git show a52c114:HANDOFF.md` for their last known state (2026-07-26 morning) and for the
  App Store Connect / Play Console procedure. Credentials live in the `appstore-connect-creds` and
  `molapp-play-store-status` memories, not in the repo.
