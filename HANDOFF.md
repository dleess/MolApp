# HANDOFF: Store release 1.1.6 (16)

Updated 2026-09-12. The Flutter app ships to both Google Play and the App Store;
SwiftUI remains the reference shell. Previous release history and the full Android renderer-crash
investigation are preserved in this file at commit `05d3e60`.

## Release state

- Refactor and fixes: [PR #44](https://github.com/dleess/MolApp/pull/44) merged as
  `05d3e60c80118da40ada17806a51f88c0e7cd31b`; all eight CI checks passed.
- Google Play: **1.1.6 (16), production, submitted for review** at 09:49 UTC on 2026-09-12.
  Publishing overview confirmed **Changes in review** and **1 change sent for review**.
  Full rollout to existing targeted countries; managed publishing remains off.
  Account: `lee.donghan@gmail.com`, developer `5578432782521884610`, app `4972032364118467410`,
  package `com.donghan.molapp`. Never use the kbsi.bionmr account.
- App Store: **1.1.6 (16), submitted for review** at 09:51 UTC on 2026-09-12.
  Independent API reads verified version and review submission **WAITING_FOR_REVIEW**,
  with build 16 **VALID**. Review ID `a256f5c0-306b-4cdd-adde-004eb799149f`.
  App `6786979305` (MolViewApp), bundle `com.donghan.MolApp`.
  Build ID `924b308a-9d8f-45d3-85e1-1190c0f2ae0b`; version ID
  `8278fdb0-8d7a-4696-92da-5aee5a599773`. Existing release policy is `AFTER_APPROVAL`.
- The previous published versions were Play 1.1.5 (15) and App Store 1.1.3 (13).
  Build 13's matching local archive contains Flutter.framework; do not switch the store back to
  the native SwiftUI shell based on the older documentation.

## Release contents and validation

PR #44 repairs multi-structure ligand ownership, selection and object-state persistence, colors
and size themes, morph/superposition restoration, measurement sequencing, bridge lifecycle and
error recovery, expression parsing, full object-name commands, and atomic desktop file export.
It also improves narrow-screen controls and disables Android WebView debugging in release builds.

Before packaging: Flutter analyze clean; 142 Flutter unit/widget tests, 35 shared viewer Node tests,
50 Linux logic tests plus one packaging test, 50 SwiftUI tests, and three native macOS export tests
passed. Real macOS WebView integration passed 2 viewer and 17 measurement tests. CI additionally
verified Android, Windows, Apple and the Linux package; all eight checks passed on PR #44.

Release artifacts are signed, version 1.1.6 (16), and contain the final tested viewer core:
`aa953ff1501474cc0f481cd2d5d97b1c996b7b12c9ac25debcc7d175f7c28c38` (SHA-256).

- Android: `/tmp/molapp-full-refactor-20260912/flutter_app/build/app/outputs/bundle/release/app-release.aab`
  (55,065,245 bytes), SHA-256 `6b5ce61a53d1664735cd95a8811dcf04f17b64a50743808380bde6a0ca092708`.
  Package/version manifest checked, target SDK 36, minimum 26, non-debuggable;
  signed JAR verified and certificate matches the configured upload keystore.
- iOS: `/tmp/molapp-ios-release-20260912/flutter_app/build/ios/ipa/molapp.ipa`
  (25,173,615 bytes), SHA-256 `e4297e7a266bbbf3100006f87345f78b92ee363039f6e3189269e666e77cfdc7`.
  Distribution signing verified, iPhone/iPad, minimum iOS 13.0, Flutter framework present.
- Nonsecret local evidence: `/tmp/molapp-android-release-artifact-20260912.json`,
  `/tmp/molapp-ios-release-artifact-20260912.json`, `/tmp/molapp-play-submission-20260912.json`,
  `/tmp/molapp-asc-build16-processed.json`, `/tmp/molapp-ios-submission-20260912.json`.

Release notes (en-US):

> Improved reliability when loading and editing multiple structures. Fixed selections,
> measurements, saved sessions, and file export. Updated viewer controls and error recovery.

## Remaining observations

- Review approval and public availability are separate from successful submission; check the
  stores for the latest status before declaring the update live. Do not rebuild or reuse build 16.
- Apple upload warning 90068 is nonblocking for this release: minimum iOS must be 15.0 by spring 2027.
- Physical iPad Pencil hover, Samsung Flip behavior, and full Windows gesture/file-dialog behavior
  still need hardware QA; CI packaging/startup checks do not prove those interactions.
- The earlier Android keyboard-crash investigation proved renderer-death recovery, while keyboard
  resize as the original trigger was an inference. Full network structure rendering after forced
  renderer death was limited by an AVD network stall. Keep the keyed WebView rebuild; reloading the
  old Android WebView left its JavaScript bridge broken.
- Prior visual QA items not explicitly covered by this release remain in the previous handoff:
  iPhone portrait Help discoverability, landscape left-rail scrolling, Mol* chrome flags, and
  measurement-banner contrast. GIF export remains single-frame.

## Workspace safety

Source changes were isolated in `/tmp/molapp-full-refactor-20260912` and iOS packaging in
`/tmp/molapp-ios-release-20260912`. The original checkout's pre-existing bridge edits and
`.kkirikkiri/`, `.serena/`, and `promo/` were preserved. Never destructively delete release artifacts.
