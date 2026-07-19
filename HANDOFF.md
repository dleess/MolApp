# HANDOFF: App icon → ubiquitin ribbon on white (done, needs push/PR/merge)

**Written:** 2026-07-19 · **Working dir:** `/Users/donghanlee/work/projects/molapp` · **Branch:** `chore/icon-ubiquitin-white`

## Goal
App icon = ubiquitin (1UBQ) ribbon on a **white** background, on **both** iOS and Android.
"Done" = both platforms show the green ubiquitin ribbon on white; landed on `master`.

## Status
**Icon work is complete, committed, and verified on both platforms. Working tree clean.**
- Branch `chore/icon-ubiquitin-white`, **1 commit ahead of `master`, not pushed** (no upstream).
  - `8777219 feat: app icon — ubiquitin (1UBQ) ribbon on white, both platforms`
- Verified: iPhone 17 sim home screen + Android emulator app drawer both show the ribbon on white,
  correctly masked (rounded square / circle).
- **Remaining: push + PR + merge** — the user typically says "push PR merge" explicitly (they did for
  the prior branch). Not yet requested for this branch, so it was not pushed.

## What worked
- **Rendered the icon with the app's own Mol* engine** (authentic, matches the app):
  1. Android emulator (already running), app installed: loaded 1UBQ, set background White (Display ▸
     Background ▸ White).
  2. WebView remote debugging is ON in DEBUG builds. Drove Mol* via CDP to render a **square 2000×2000**
     screenshot: `plugin.helpers.viewportScreenshot.behaviors.values.next({...resolution:{name:'custom',
     params:{width:2000,height:2000}}})` then `getImageDataUri()`. (Setting `vs.values = ...` directly
     does NOT work — `values` is a read-only getter backed by `behaviors.values`.)
  3. Post-processed with PIL: autocrop the ribbon off white, recenter on a white square, resize.
- **All icon PNGs regenerated from two square masters** (RGB, no alpha — App Store safe). **[still applied]**
- **Android adaptive launcher icon added** (there was none before — Android showed the default icon).

## What didn't work / cautions
- Emulator Export ▸ PNG gives only **411×841** (canvas size) — too low for a crisp 1024 icon. Use the
  CDP custom-resolution screenshot instead (above). **[dead end, don't reuse for icons]**
- CDP call **timed out at the default 10s socket timeout** rendering 2000² on the software (swiftshader)
  emulator GPU. Fix already applied to the helper: `s.settimeout(90)` after connect. **[still applied]**
- The square screenshot keeps the **portrait camera framing**, so the molecule renders small/off-center
  in the square (bbox was ~736×786 inside 2000²). That's why the PIL autocrop+recenter step is needed —
  don't use the raw screenshot as the icon.

## Key files & commands
- `MolApp/Assets.xcassets/AppIcon.appiconset/` — 17 iOS PNGs (filenames unchanged; `Contents.json`
  untouched). Regenerated from a 1024 master at 0.82 content.
- `android/app/src/main/res/mipmap-*/` — `ic_launcher.png`, `ic_launcher_round.png`,
  `ic_launcher_foreground.png` at 5 densities; `mipmap-anydpi-v26/ic_launcher.xml` +
  `ic_launcher_round.xml` (adaptive: `@android:color/white` bg + `@mipmap/ic_launcher_foreground` fg).
- `android/app/src/main/AndroidManifest.xml` — added `android:icon="@mipmap/ic_launcher"` +
  `android:roundIcon="@mipmap/ic_launcher_round"` on `<application>`. **[still applied]**
- Scratchpad (outside repo; regenerate if gone) at
  `/private/tmp/claude-501/-Users-donghanlee-work-projects-molapp/37ee0721-d689-4c32-9167-d7422de746c6/scratchpad/`:
  `cdp.py` (raw-socket CDP client, patched: 90s timeout + optional 3rd arg = outfile for full result),
  `shot.js` (2000² screenshot JS), `make_icon.py` (autocrop/recenter), `gen_all.py` (all sizes),
  `icon-1024.png` / `icon-fg-1024.png` (the two masters), `ubq_2000.png` (raw render).
- Regenerate all icons: `python3 gen_all.py` (paths are hardcoded to this repo).
- Builds: Android `cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew assembleDebug -q`;
  iOS `xcodebuild -project MolApp.xcodeproj -scheme MolApp -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/molapp_dd build`.
- iOS sim UDID for verification: `AA2D8B99-7BC2-4947-B585-16B1D90DDD70` (also in `/tmp/molapp_sim_id.txt`).
  Icon cache is sticky — `xcrun simctl uninstall` then `install` to force a refresh.

## Next steps
1. If the user says push/PR/merge (like last time), from this branch:
   - `git push -u origin chore/icon-ubiquitin-white`
   - `gh pr create --base master --head chore/icon-ubiquitin-white --title "App icon: ubiquitin ribbon on white" --body "..."`
   - `gh pr merge --squash --delete-branch` (repo history is squash-merged; `gh` is authed as `deepnmr`,
     remote `origin` = `https://github.com/deepnmr/MolApp.git`).
2. This `HANDOFF.md` will be modified again by this write — decide whether to commit it (it's a scratch
   doc, not product code; `HANDOFF.md` is tracked and was committed on the prior branch).

## Open questions / risks
- **Not pushed/merged** — do that only when the user asks.
- **App Store / Play Store icon submission is a separate step** (not done). If they want to ship: bump to
  the NEXT available App Store version (memory `molapp-appstore-status.md`); Play uses the adaptive icon
  automatically. Default Play account is `lee.donghan@gmail.com` (memory), never kbsi.bionmr.
- Real-device icon rendering unverified (only sim + emulator). Low risk — standard icon assets.
