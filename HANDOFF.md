# HANDOFF: Store release 1.1.7 (17)

Updated 2026-09-20. Flutter ships to both stores; SwiftUI remains the reference shell.
Release 1.1.6 history is preserved at commit `3b3f72b`; the earlier renderer-crash investigation
is preserved at `05d3e60`.

## Release state

- App Store: **1.1.7 (17), WAITING_FOR_REVIEW**, submitted on 2026-09-20.
  Build **VALID**; automatic release **AFTER_APPROVAL**. App `6786979305` (MolViewApp),
  bundle `com.donghan.MolApp`. Build ID `55f5debc-bf47-48ee-8f8b-d1e806f8f6c8`;
  version ID `d128e39e-cd85-453a-a934-26386a044b4e`;
  review ID `4991ad44-6eb4-4c5c-898e-0ea03c1721dd`.
- Google Play: **1.1.7 (17), production, Changes in review**, submitted on 2026-09-20.
  Quick checks run before review; publishing remains automatic (managed publishing off).
  Full rollout to all 177 currently targeted countries.
  Account `lee.donghan@gmail.com`, developer `5578432782521884610`, app `4972032364118467410`,
  package `com.donghan.molapp`. Never use the kbsi.bionmr account.
- At the start of this release, version 1.1.6 was live on both stores; this was verified from
  App Store Connect (`READY_FOR_SALE`) and Play (`Available on Google Play`, full rollout).

## Release contents and validation

Protein superposition now excludes calcium ions named CA from the C-alpha fit by requiring
carbon elements. Node and real Mol* WebView regression tests cover the incorrect core/RMSD.
Flutter 3.47.5 fixes Xcode 27 universal-framework architecture verification. The macOS project
and CocoaPods dependencies use a 12.0 minimum; Flutter's iOS migration raises its minimum to 15.0.

Validation: 36 Node tests, 142 Flutter unit/widget tests, 20 real macOS WebView integration tests,
3 native macOS export tests, 50 Linux logic tests, and 50 SwiftUI tests passed. Flutter analysis
is clean. Normal universal macOS debug/release builds work without xcconfig overrides. Both
signed mobile packages contain the exact shared viewer SHA-256:
`cf63d3ed9aa04a3b5e0e0d7bed57f0408b7d51e6ffb5eb85503f644493fa0cc8`.

- Android: `flutter_app/build/app/outputs/bundle/release/app-release.aab` (55,628,905 bytes).
  SHA-256 `b70e89b8192dbdc3c6358b33ba0af29ab4b6159b69318e86c1c44b786f8ea1a5`.
  Package/version verified from bundle manifest: 1.1.7 (17), target SDK 36, minimum SDK 26,
  non-debuggable. JAR signature verified and certificate matches the configured upload key.
- iOS: `flutter_app/build/ios/ipa/molapp.ipa` (25,386,975 bytes).
  SHA-256 `1723734f8dbec01c70dd5cc6c6a5acd1899800a5f461076c15cfa1510f9ecbcc`.
  Version 1.1.7 (17), minimum iOS 15.0, Apple Distribution signature, App Store provisioning,
  Flutter framework and matching viewer verified inside the exported IPA.
- Local evidence: `/tmp/molapp-android-release-artifact-20260920.json`,
  `/tmp/molapp-ios-release-artifact-20260920.json`, `/tmp/molapp-ios-submission-20260920.json`,
  `/tmp/molapp-play-submission-20260920.txt`.

Release notes (en-US):

> Fixed protein superposition for structures containing calcium ions. Improved app reliability
> and compatibility with current operating systems.

## Remaining observations

- Review approval and public availability are separate from successful submission; check the
  stores for the latest status before declaring the update live. Do not reuse uploaded build 17.
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

Original `.kkirikkiri/`, `.serena/`, and `promo/` remain untracked and untouched. Pre-existing
bridge edits were already present in upstream PR #44; their exact originals remain in the
`molapp-debug-20260920 preserved pre-existing async bridge changes` stash and a temporary backup.
Previous local iOS archive/IPA and Android bundle directories were archived with a
`-before-1.1.7-20260920` suffix before packaging. Never destructively delete release artifacts.
