# HANDOFF: five CI jobs green, and the token change verified on real Windows

**Written:** 2026-07-27 · **Working dir:** `/Users/donghanlee/work/projects/molapp` · **Branch:** `master` — last code commit `ccb9391`, with this file landing on top of it

> Replaces the previous HANDOFF (`git show 9decf0f:HANDOFF.md`), which in turn replaced the Flutter
> port / 1.1.0 submission one (`git show a52c114:HANDOFF.md`). **The store-submission state has not
> been re-checked since 2026-07-26 morning** — treat that older file as of then.

## Goal

Nothing is in flight. The visual-QA backlog under "Next steps" is what remains, and none of it is
started.

Acceptance for anything picked up: `cd flutter_app && flutter analyze` clean and `flutter test`
→ 113 passing, plus device evidence for anything that changes layout or colour.

## Status

**Working tree clean apart from this file.** No debugging leftovers in `flutter_app/`.

Merged, in order:

| PR | Commit | What |
| --- | --- | --- |
| #23 | `5a82f3b` | `SafeArea` for the chrome + `_menuBarTop()` for iPadOS window controls; PDF export crash, unvalidated hex colours, stale command bar, enums drop their `raw` field |
| #24 | `894cc74` | `ChromeTokens` — the chrome's palette and type sizes in one file, then the drift collapsed |
| #25 | `9decf0f` | previous HANDOFF |
| #26 | `c0397ac` | the windows CI job compiles for the first time |
| #27 | `ccb9391` | linux diagnosed as unbuildable and made non-blocking |

**All five CI jobs now pass, and PRs no longer need `--admin`.** That was true for the first time on
#27. Note the repo has **no branch protection at all** (private repo, free plan — the API returns
403 for the feature), so `--admin` was only ever bypassing `gh`'s own refusal to merge on failing
checks.

## Verified on real Windows (2026-07-27)

This closes the previous handoff's largest open risk — "the token consolidation changes pixels on
purpose and has NOT been looked at on a real device".

The `molapp-windows-x64` artifact from CI run `30212788301` was run on the local Windows 11 VM.
Sampling the screenshot's pixels against the values computed when the tokens were chosen:

| element | measured | expected |
| --- | --- | --- |
| panel scrim (all four panels) | (2, 2, 3) | (2, 2, 3) |
| `structure` type line | (167,167,167) | textSecondary 0.65 → (166,166,167) |
| unselected chip `Sur` | (167,167,167) | textSecondary 0.65 |
| object name `1CRN` | (255,255,255) | textPrimary 1.0 |
| selected chip fill | (65, 65, 66) | chipSelectedFill 0.25 → (65,65,66) |
| colour swatch | (78, 78, 79) | swatchFallback 0.3 → (78,78,79) |

So the golden renders predicted the real device exactly, and the five-scrim drift really is gone.

Also confirmed on Windows, none of it previously exercised on that platform:

- **WebView2 → WebGL → Mol\* renders.** 1CRN draws. This was the biggest unknown, since
  `flutter_inappwebview_windows` is `0.7.0-beta.3`.
- **PDF export works end to end** — `Saved molecule.pdf`. That is #23's fix (the PDF branch used to
  cast `document.save()` to `List<int>` and throw). The save dialog appearing already proves the
  encode succeeded, because `bytes: await encodeExport(...)` is evaluated before `deliverFile` opens
  the dialog.
- The command bar clears after a run (#23's `notifyListeners()`), and Load PDB enables once the
  field has content.
- `SafeArea` is a no-op on desktop, as designed.
- Mol\*'s own control strip leaks at the right edge here too — no platform is exempt.

**Not exercised on Windows:** measure mode, state save/open, Print, export formats other than PDF.

## What worked

- **`gh pr merge <n> --squash --delete-branch`** — no `--admin` needed since #27.
- **Running two candidate CI fixes as a matrix in one round** instead of guessing across two blind
  round-trips. That is how the windows fix was chosen, and it settled an unverified hypothesis
  (cl.exe honours the `CL` environment variable even when msbuild drives the build). Collapse the
  matrix before merging.
- **Golden-image diffing for colour work.** `flutter test` renders text as boxes, but every colour,
  alpha and border is exact. The token extraction was proven byte-identical this way before the
  consolidation was allowed to change anything — and the Windows measurements above then confirmed
  the goldens were faithful.
- **Choosing alpha values by computing WCAG contrast over all five `backgroundPresets`** rather than
  by eye.
- **Reverting a fix to prove its test fails without it.**
- **Reading the artifact instead of rebuilding.** CI uploads `molapp-windows-x64`, so the Windows
  binary can be run on the VM with no toolchain installed in the guest. A copy is at
  `~/Downloads/molapp-windows-x64/` (41 MB, 26 files) — outside git, delete freely.
- **Android**: SDK at `~/Library/Android/sdk`, **not on `PATH`**. AVD `test36` is API 36. Package id
  is `com.donghan.molapp` (lowercase; the iOS bundle id is `com.donghan.MolApp`). `adb shell monkey`
  silently fails — use `adb shell am start -W -n com.donghan.molapp/.MainActivity`.

## What didn't work

- **The Linux target cannot be built at all, anywhere.** `flutter_inappwebview_linux 0.1.0-beta.1`
  (the only version ever published) compiles against WPE WebKit 2.40+ API
  (`WebKitScriptMessageReply`, `WebKitNetworkSession`, `webkit_network_session_get_default`) and
  libsoup3. **No Ubuntu release has ever shipped WPE WebKit 2.40 or newer**: jammy is the only one
  carrying WPE at all, at 2.36, and every release after it dropped the packages entirely — 24.04 has
  none. Waiting for `ubuntu-latest` to advance makes it worse. The job is `continue-on-error` on its
  build step and documented in the workflow. **[applied, on master]**
- **`prlctl` cannot control the VM** — `resume` returns *"available only in Parallels Desktop for Mac
  Pro or Business Edition"*. The installed edition is Standard, so no headless resume and no
  `prlctl exec` into the guest.
- **System Events synthetic clicks do not reach the Parallels guest.** Two attempts, correct
  coordinates, no effect — not even a change of desktop selection. Same failure mode as the Flutter
  macOS app (below). Driving the guest needs a human, or a CGEvent-based tool such as `cliclick`
  (not installed; would need consent).
- **Synthetic input does not reach the Flutter macOS app either.** System Events `click at` +
  `keystroke` was accepted (window resize via System Events works) but text never landed. Use the
  iOS Simulator or Android emulator for interaction testing.
- **A locked Mac** makes `screencapture` return `could not create image from rect`, `osascript ...
  activate` unable to foreground anything, and System Events report 0 windows for a running app.
  That is the display, not a bug. It blocked all macOS and VM work for a stretch on 2026-07-26.
- **`ui_describe_all` returns `DockFolderViewService`** instead of the app when an iPad simulator is
  in iPadOS 26 windowed mode. Fall back to pixel measurement and screen-space taps.
- **Job-level `continue-on-error` does not unblock merges** — the check still reports failure and the
  PR stays `UNSTABLE`. It has to sit on the step.
- **`dart format` must not be run** — no config, so its default 80 columns would reformat every file;
  the codebase wraps at 102. Wrap long lines by hand.
- **`flutter test` from the repo root** fails with `Test directory "test" not found.` Run it from
  `flutter_app/`.
- **A regression test that asserted the wrong relation.** `banner.top >= menuBar.top` passed even
  with its fix reverted; the shipped version is `banner.top >= file.bottom`, which fails at
  `Expected: >= 110.0 / Actual: 66.0`. Re-verify by reverting if you touch it.

## Key files & commands

- `flutter_app/lib/src/tokens.dart` — `ChromeTokens`. **Read its doc comment before changing a
  value**; it records what was consolidated, what was not, and why.
- `flutter_app/lib/src/viewer_page.dart` — the whole UI. Holds `_menuBarTop()` and the `SafeArea`
  around the five chrome overlays. The viewport and hover tooltip are deliberately **outside** it —
  the tooltip's coordinates come from the webview and are in un-inset space.
- `MolApp/Resources/viewer.html` — the Mol\* viewport, single source of truth for all shells. Run
  `cd flutter_app && dart run tool/sync_web_assets.dart` after editing; the copies under
  `flutter_app/assets/web/` and `android/app/src/main/assets/` are generated.
- `.github/workflows/flutter.yml` — the windows job carries
  `CL: /D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` (drop it when the plugin moves to
  C++20 `<coroutine>`); the linux job carries the jammy pin, `CXXFLAGS`, a pkg-config listing step
  and the step-level `continue-on-error`, all of which are load-bearing for the diagnosis.
- `cd flutter_app && flutter analyze` → `No issues found!`
- `cd flutter_app && flutter test` → `All tests passed!`, 113 tests.
- `gh run download <run-id> -n molapp-windows-x64 -D <dir>` — the Windows binary without a Windows
  toolchain. In the VM it is reachable at `\\Mac\Home\Downloads\...` via the `Mac Files` shortcut.

## Next steps

None started. Ordered by user harm:

1. **Objects panel accessibility.** Zero `Semantics` wrappers, so the eye, colour swatch and
   Rib/Sur/Stk/B+S/Sph chips are exposed as `StaticText` and **VoiceOver cannot operate the panel**.
   Touch targets there are 15x15, 14x14 and ~27x20 pt against a 44pt minimum.
2. **Help is undiscoverable on iPhone.** Reachable only by an undiscoverable horizontal swipe of the
   menu row, with a `{{0,0},{0,0}}` accessibility frame, and it is the only route to the Manual.
   Six labels total ~455pt against 402pt of screen, so fixing it means shrinking the labels or
   adding a scroll affordance — neither preserves the current look, which is why it was left.
3. **Mol\* chrome leaking.** `MolApp/Resources/viewer.html:2291-2305` sets seven viewport flags false
   but not `ShowReset`, `ShowToggleFullscreen`, `ShowIllumination` or `ShowXR`. Confirmed on every
   platform including Windows. The axis gizmo also sits behind the command bar below ~660pt, and the
   `.msp-logo` molstar.org link shows while the scene is empty — the launch state.
4. **The measure banner's contrast.** 4.1:1 on the default background, 2.6:1 on white. White on
   Material blue is 3.1:1 at full opacity, so this needs a hue change, not an alpha change. Same for
   the run button's accent, which is stock `Colors.blue` while the `ColorScheme` is seeded from
   Okabe-Ito `#0072B2` — two unrelated blues on screen at once.

## Open questions / risks

- **macOS has no post-token-change screenshot.** Every other platform now does. The Mac was locked
  when it was attempted on 2026-07-26; it was unlocked again on 2026-07-27 but the check was not
  re-run. Cheapest remaining gap to close: `cd flutter_app && flutter build macos --debug` and open
  `build/macos/Build/Products/Debug/MolApp.app`.
- **The soft-keyboard state is unverified on every platform.** The simulator's hardware keyboard
  suppresses it, and an attempt to toggle it with Cmd+K went to the wrong app.
- **Landscape on a notched iPhone leaves a 59pt gutter** at the left of the menu bar's background
  strip — a consequence of the `SafeArea` fix, measured by widget probe
  (`Rect.fromLTRB(59.0, 8.0, 874.0, 68.0)` at 874x402 with a 59pt left inset). Labels are positioned
  correctly; only the strip's fill is inset. **Unverified on a real device.**
- **Windows is verified for launch, rendering, tokens and PDF export only.** Measure mode, state
  save/open, Print and the other export formats were not exercised.
- **Evidence from these two days lives only in a session scratchpad and will disappear**:
  `/private/tmp/claude-501/-Users-donghanlee-work-projects-molapp/0e03801c-cc55-469d-9374-fdd862001630/scratchpad/`
  — `vqa/VISUAL-QA.md` (the full audit: 36 findings that survived adversarial verification, 17
  refuted), `vqa/FIX-REPORT.md`, ~30 before/after device captures including the Windows ones,
  `g-orig/` vs `g-final/` golden pairs, and `zz_golden_test.dart.archived` (drop it into
  `flutter_app/test/` and run with `--dart-define=GOLDEN_DIR=<dir> --update-goldens`). **Nothing in
  the repo depends on any of it.** Copy what you want to keep.
- **The 1.1.0 store submissions were not touched or checked on either day.** See
  `git show a52c114:HANDOFF.md` for their last known state and the submission procedure.
  Credentials live in the `appstore-connect-creds` and `molapp-play-store-status` memories, not in
  the repo.
