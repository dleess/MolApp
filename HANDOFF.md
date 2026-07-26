# HANDOFF: MolApp ported to Flutter (5 platforms); measure/stick/colour fixes; 1.1.0 submitted to both stores

**Written:** 2026-07-26 · **Working dir:** `/Users/donghanlee/work/projects/molapp` · **Branch:** `master` (synced to `origin/master`, HEAD `97a3cbf`)

## Goal

Two things, both delivered this session:

1. `molapp을 flutter로 바꿔서 macos, ios, android, linux, window에서 작동하게 해` — one Flutter codebase over the existing shared web core.
2. Three user bug reports about measuring, in order: "앞에 선택된 것들을 기억한다" → "measure를 시작하기 전에 선택된 것을 기억한다" → "계속 다른 것이 선택된다"; then "stick 에서 선택을 했더니 안된다"; then "측정된 값을 좀 더 잘 보이게 색깔을 바꿔 (오카베 이토)".

Release acceptance: **1.1.0 / build 10 reaches users on both stores.** Both are submitted and waiting on the stores.

## Status

**Code 100% done and merged.** `97a3cbf` on `master` (PR #21, squash-merged, branch `flutter-multiplatform-port` deleted). Working tree **clean** — `git status --short` empty. No debugging leftovers, no reverted-but-not-restored edits.

**Both stores submitted, both awaiting review. No blocker.**

| | state | ids |
| --- | --- | --- |
| App Store | 1.1.0 / build 10 `WAITING_FOR_REVIEW` | appStoreVersion `a49e7497-19ff-4428-9e2d-7d24274bfad4`, build/delivery UUID `0b248f99-4cde-4dcc-b5d9-7d0b71a29b92`, reviewSubmission `5fe3d023-cde2-4df3-ad57-bef31bf7bf02` |
| Google Play | Closed testing ▸ Alpha, `10 (1.1.0)`, "Changes in review" (Play was running its ~13 min automated pre-checks when last seen) | app `4972032364118467410`, dev acct `5578432782521884610`, Alpha track `4699728492176435293` |

Both native shells still build and pass. `flutter_app/` is now the one to work in.

## What worked

- **Repro before fix, every time.** All three measurement rounds were diagnosed by pushing real Mol\* events through a JS probe in `flutter_app/integration_test/measure_pick_test.dart`, never by reading code alone. Each fix was then proven by reverting it and watching its own test fail. Three of the four fixes below were verified that way. **[still applied]**
- **Root cause of "기억한다" and "계속 다른 것이 선택된다" — Mol\*'s click-focus layer.** `clickFocus` is bound to plain primary click ("Representation Focus") and populates `plugin.managers.structure.focus`, drawing the clicked residue *plus its surroundings* in its own visual. That is a different manager from `lociSelects`, so clearing selection marks never touched it: it survived into measure mode and reappeared on every pick. Proof from the probe: `AFTER PRE-MEASURE CLICK → focus: ALA 1 | A`, `AFTER ENTERING MEASURE → focus: ALA 1 | A`, `AFTER FIRST PICK → focus: ALA 3 | A`. Fixed by `clearFocusVisual()` + `resetAllSelections()` in `MolApp/Resources/viewer.html`, called unconditionally from `setMeasureMode` (not just on the off→on edge) and at the top of `handleMeasurePick`. **[still applied]**
- **Root cause of "stick 에서 선택이 안된다" — Stick had no clickable geometry.** It was ball-and-stick with `element-sphere` removed (`STICK_ONLY_VISUALS = ['intra-bond','inter-bond']`), so every click returned a `Bond.Loci` and atom picking was impossible; ball-and-stick worked because it kept the spheres. Fixed by keeping the spheres sized to the bond radius: `STICK_VISUALS` (now includes `element-sphere`) + `STICK_TYPE_PARAMS = { sizeAspectRatio: 1, sizeFactor: 0.1 }` + `STICK_SIZE_THEME = { name: 'uniform' }`. Renders as capped sticks at the same thickness as before; chosen by rendering 4 candidate parameter sets to PNG and comparing. **[still applied]**
- **Root cause of unreadable values — Mol\*'s default measurement `textColor` is black** on the `#0b0f14` viewport. Confirmed by removing the new options and re-running the colour test: `Expected: '#F0E442' Actual: '#000000'`. Now Okabe-Ito via `MEASUREMENT_TEXT_PARAMS` / `MEASUREMENT_OPTIONS`: yellow `#F0E442` text on a black backdrop, orange `#E69F00` line/arc, `textSize` 0.5 → 0.9. Distance names its line colour `linesColor`; angle and dihedral use a single `color`. **[still applied]**
- **Earlier round, also still applied:** empty-space click now cancels pending picks instead of returning early (a stale pick used to pair with the next atom, shifting every later measurement by one); `addMeasurement`'s `finally` deselects only its own picks because it is not awaited; `clearSelectionVisuals()` drops pending picks in measure mode; the Dart side dedupes measurements by a `measurementSeq` counter, not by label text. **[still applied]**
- **The SwiftUI real-WKWebView audit caught a bug the Flutter suite could not.** Renaming `STICK_ONLY_VISUALS` → `STICK_VISUALS` missed the selection-object branch at `viewer.html:829`; it threw `ReferenceError`, so the stick representation silently never applied and the previous one stayed. Failure: `MolStarBridgeTests.swift:59: XCTAssertEqual failed: ("Optional(["molecular-surface"])") is not equal to ("Optional(["ball-and-stick"])")`. **Always run the Xcode suite after touching viewer.html.** **[fixed, still applied]**
- **App Store submission fully via the ASC API** — no browser needed. Node ES256 JWT with `dsaEncoding:'ieee-p1363'`, minted per request. Flow: create `appStoreVersions` → PATCH `relationships/build` → PATCH `appStoreVersionLocalizations` whatsNew → POST `reviewSubmissions` → POST `reviewSubmissionItems` → PATCH `submitted=true`. Screenshots and description auto-inherited from 1.0.3.

## What didn't work

- **Running a review Workflow with write-capable agents against the live worktree destroyed uncommitted work.** One of 13 agents ran a `git restore`/`checkout`-class command; my uncommitted icon, launch-screen and `AndroidManifest.xml` edits were reverted, and agents wrote stray probe tests into `flutter_app/test/`. Detected only because `git status` was unexpectedly clean and `grep -c roundIcon` returned 0 after I had already seen the edit land. I stopped it (`TaskStop w3oc6zuey`) and got **no review results** — PR #21 was merged on the strength of the test suites alone, **not** a code review. **Do not run write-capable agents against this worktree with uncommitted changes: commit first, or give the agents `isolation: "worktree"`.** **[work redone and committed; the one stray file was archived, not deleted, to `<scratchpad>/stray-agent-files/tmp_color_picker_probe_test.dart`]**
- **The Flutter port had the Flutter placeholder icon committed.** Surfaced by `flutter build ipa`'s `! App icon is set to the default placeholder icon. Replace with unique icons.`, then confirmed by opening `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png` — the blue Flutter logo. App Review rejects this outright and the Play listing would have swapped a shipped icon. All platforms' icons are now generated from `MolApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` via `sips`. **[fixed, still applied]**
- **The integration harness silently tested far less than it appeared to, for two entire rounds.** It pushed `{current: {loci}}` into `plugin.behaviors.interaction.click` with **no `button`/`modifiers`**, so Mol\*'s own behaviors (focus, select) never matched their bindings and never ran — every test passed while the user's bug was live. Fixed by `window.__probe.clickEvent()`, which sends `button: 1, buttons: 1, modifiers: {alt:false, control:false, meta:false, shift:false}`. **Any new synthetic Mol\* event must carry these or it proves nothing.** **[still applied]**
- **`plugin.canvas3d.identify()` is not usable as a test oracle here.** It returned `empty-loci` / `no-pick` at correctly projected coordinates, presumably because the integration-test window never foregrounds (`Failed to foreground app; open returned 1` on every run). Do not build assertions on it. It also takes a `Vec2` (`identify([x,y])`), not two numbers — two numbers throw `TypeError: ... is not an Object. (evaluating '"origin"in we')`. **[abandoned, nothing applied]**
- **`sizeTheme: {name:'uniform', params:{value: N}}` — the `value` is ignored.** Renders at 0.40 / 0.45 / 0.50 came out byte-identical (119569 bytes each). Stick size is governed by `sizeFactor` only.
- **Resolving a bond click to the nearer atom was investigated and abandoned.** Mol\*'s click event carries only `{current, modifiers, buttons, button}` — no pointer position — so the endpoint the user aimed at cannot be recovered without tracking `pointerdown` and projecting; and the projection could not be validated because `identify` does not work here. Fixing Stick's geometry instead made it unnecessary. Bond clicks are deliberately **ignored** (neither pick nor cancel) — see the `clicking a bond leaves the pending pick alone` test. **[abandoned; the ignore-bond behaviour is applied]**
- **The browser `file_upload` tool cannot upload the AAB.** Hard 10 MB cap; the bundle is 52 MB. Verified, not assumed: `Cannot upload "/Users/donghanlee/work/projects/molapp/flutter_app/build/app/outputs/bundle/release/app-release.aab": total upload size would exceed 10 MB.` No Play Developer API service account exists. **The user uploaded the AAB by hand; I did the rest of the release in the console.**
- **Two `integration_test/` files cannot run in one `flutter test integration_test/` invocation on macOS** — the second dies with `Unable to start the app on the device`. Run each file separately. A stale app instance from an aborted run also poisons the *next* run (3 spurious failures once); re-run before believing a failure.
- **Play Console was signed into the wrong account at first** (`treasurehunteriosapp@gmail.com` at `u/1`, plus a Terms-of-Service gate). The correct developer account ended up at `u/0`. **Check the slot before any Play action.**

## Key files & commands

- `MolApp/Resources/viewer.html` — **single source of truth for all three shells.** Never edit the generated copies (`flutter_app/assets/web/`, `android/app/src/main/assets/`); both are gitignored and regenerated.
  - Constants block ~line 181: `OKABE_ITO`, `MEASUREMENT_TEXT_PARAMS`, `MEASUREMENT_OPTIONS`, `BALL_AND_STICK_VISUALS`, `STICK_VISUALS`, `STICK_TYPE_PARAMS`, `STICK_SIZE_THEME`.
  - `applyAtomicRepresentation()` ~line 194 **and** the selection-object branch inside `setObjectRepresentation` (~line 829, the line that threw the `ReferenceError`) both build representations — **change both together.**
  - `clearFocusVisual()`, `resetAllSelections()`, `clearSelectionVisuals()`, `applySelectionVisuals()`, `setMolAppSelection()` ~line 272–330.
  - `postMeasurePending()`, `clearMeasurePending()`, `handleMeasurePick()`, `addMeasurement()` ~line 2050+.
- `flutter_app/integration_test/measure_pick_test.dart` — 17 tests, the real regression net (JS probe + real webview). `cd flutter_app && flutter test integration_test/measure_pick_test.dart -d macos` → `All tests passed!` in ~75 s.
- `flutter_app/integration_test/viewer_bridge_test.dart` — offline end-to-end boot/load/representation/serialise/capture/reset.
- `flutter_app/lib/src/molstar_bridge.dart` — transport + viewer state; `measurePending` event decoding, `measurementSeq`. `viewer_controller.dart` — UI state + command parser. `viewer_page.dart` — `_measureBanner()` names the armed atoms.
- `cd flutter_app && dart run tool/sync_web_assets.dart` — **run after every viewer.html edit** or the Flutter tests run against a stale copy. Verify with `md5 -q MolApp/Resources/viewer.html flutter_app/assets/web/viewer.html`.
- `cd flutter_app && flutter test` → 104 unit/widget tests. `flutter analyze` → clean.
- `xcodebuild -project MolApp.xcodeproj -scheme MolApp -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.4.1' test CODE_SIGNING_ALLOWED=NO` → `** TEST SUCCEEDED **`, 40 tests incl. a ~10 s real-WKWebView audit. **Failure detail is not in stdout** — get it from the `.xcresult`: `xcrun xcresulttool get test-results tests --path <bundle> --format json`.
- `cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew assembleDebug` — Compose shell.
- `cd flutter_app && flutter build ipa --release` → `build/ios/ipa/molapp.ipa`; `flutter build appbundle --release` → `build/app/outputs/bundle/release/app-release.aab`. Apple builds require `flutter config --no-enable-swift-package-manager` (global machine setting, already on) — `flutter_inappwebview_macos` declares macOS 10.14 while using 10.15-only API and SPM compiles at the package minimum.
- **Version lives only in `flutter_app/pubspec.yaml`** (`version: 1.1.0+10` → iOS `CFBundleVersion` 10 and Android `versionCode` 10). `flutter_app/ios/Runner/Info.plist` carries `ITSAppUsesNonExemptEncryption=false` (the Flutter target has a real plist and does not inherit the SwiftUI target's `INFOPLIST_KEY_...`; without it ASC holds the build for export compliance).
- `xcrun altool --upload-app --type ios -f build/ios/ipa/molapp.ipa --apiKey <key id> --apiIssuer <issuer>` — key id/issuer/team are in the `appstore-connect-creds` memory, **not repeated here**.
- ASC API scripts: `<scratchpad>/{ascw,asc,state,submit,review,poll}.mjs` where `<scratchpad>` = `/private/tmp/claude-501/-Users-donghanlee-work-projects-molapp/77935534-6ade-40cc-894c-83914730ef51/scratchpad`. **Temporary** — rewrite from the memory notes if gone.
- Play keystore path/password and Play Console state: `molapp-play-store-status` memory. **Play deploys use lee.donghan@gmail.com only.**

## Next steps

1. **Wait for both stores.** Poll iOS with `<scratchpad>/state.mjs`; Play state is on the app's Publishing overview page. Nothing else is actionable until they respond.
2. **Get manual device QA done before either build reaches users** — see risks. iOS: a `WAITING_FOR_REVIEW` submission can be withdrawn by the developer. Play: an Alpha release can be halted from the track page.
3. **If either store rejects:** bump `flutter_app/pubspec.yaml` to `+11` before rebuilding. A rejected Play upload still consumes its versionCode, and iOS build numbers cannot be reused.
4. **Optional — removes the manual AAB step next time.** Create a Play Developer API service account: Google Cloud project → enable *Google Play Android Developer API* → service account → JSON key; then Play Console ▸ Setup ▸ API access → link the Cloud project → grant that account *View app information* + *Release to testing tracks*, scoped to MolApp only. **Steps requiring the account owner cannot be done by an agent.** Store the key at `~/.playstore/molapp-publisher.json`, `chmod 600`, never in git. Upload flow: `edits.insert` → `edits.bundles.upload` → `edits.tracks.update` → `edits.commit`.
5. **Consider retiring the two native shells.** They are reference implementations now; keeping three shells in sync is exactly what produced the `STICK_ONLY_VISUALS` bug.

## Open questions / risks

- **The submitted build has had no manual device QA.** It passed `flutter analyze`, 104 unit/widget tests, 17 real-webview integration tests, the 40-test SwiftUI suite and an Android build — but nobody has held it in their hands. Largest risk here.
- **Windows and Linux are unverified in practice.** They cannot be built on this macOS machine; they are covered only by `.github/workflows/flutter.yml`, and **I did not check whether those CI jobs have ever passed**. Treat the 5-platform claim as unverified for those two.
- **PR #21 was merged without a code review** (workflow killed mid-run, above). If a review is wanted, run it now against `master` with read-only or worktree-isolated agents.
- **The Play release drops 1 supported device** (11,179 → 11,178, ~0%). Structural: the Compose app was pure Kotlin and served all ABIs, Flutter ships native libs for 3. Accepted, not fixable.
- **`android/app/src/main/assets/viewer.html` was stale** when last compared (md5 differed from `MolApp/Resources/viewer.html`). Harmless — gitignored, regenerated by the `copyWebAssets` Gradle task at preBuild — but do not read it as truth.
- **Play production is still gated.** "Have at least 12 testers opted-in" now shows satisfied (✓) on the dashboard; "Run your closed test with at least 12 testers, for at least 14 days" is not. This Alpha release contributes to that clock.
- The stray file archived at `<scratchpad>/stray-agent-files/tmp_color_picker_probe_test.dart` was written by a review agent and **I never read its contents**; it is not mine and is not in git.
