# HANDOFF: MolApp 1.0.2 shipped + submitted for App Store review

**Written:** 2026-07-16 · **Working dir:** `/Users/donghanlee/work/projects/molapp` · **Branch:** `master`

## Goal

Ship MolApp 1.0.2 (build 8) to the App Store and submit for review. **DONE.**
Acceptance: build uploaded + `processingState` VALID, version submitted, state
`WAITING_FOR_REVIEW`. All met. Nothing left on our side — Apple review runs on
their end now.

## Status

**Complete.** 1.0.2 / build 8 is `WAITING_FOR_REVIEW` (submitted 2026-07-16
08:48 UTC). Working tree clean except this untracked `HANDOFF.md`.

- appStoreVersion id `bde70b62-e5ba-46fe-b8b5-71e1ecfc1686`
- build id `12c0189f-ea4c-4808-b89f-3037800ab7fd` (build 8)
- reviewSubmission id `1ed1a77a-01cb-4692-9807-a829964dbf72`
- Live before this: 1.0.1 (build 7), READY_FOR_SALE, train closed.

## What shipped

- **PR #7 `606fb6e`** — selection parsing + viewer state synchronization fix
  (merged before this ship run).
- **PR #8 `ced1ea7`** — version bump 1.0.2 / build 8 + **new AppIcon artwork**.
  The 17 icon PNGs were the prior session's open question (flat green
  protein-ribbon vs old teal ball-and-stick). **User explicitly chose the green
  icons** — that decision is now resolved and committed. **[still applied]**

## What worked

- Full pipeline: `xcodebuild archive` → `-exportArchive` (ExportOptions.plist,
  manual signing, "MolViewApp AppStore" profile) → `xcrun altool --upload-app`.
  Upload UUID `12c0189f-...`, VALID ~2 min after upload. **[n/a — process]**
- **Submit via API** (scratchpad `submit.mjs` + `asc2.mjs`): create
  appStoreVersion(1.0.2) → PATCH `relationships/build` → set `whatsNew` on en-US
  localization → POST reviewSubmissions{platform:IOS} → POST
  reviewSubmissionItems → PATCH submitted=true. Worked first try. Export
  compliance auto (Info.plist `ITSAppUsesNonExemptEncryption=false`).
- Scratchpad helpers:
  `/private/tmp/claude-501/-Users-donghanlee-work-projects-molapp/5096044b-7fe2-43f8-adc7-256b1ac67132/scratchpad/`
  — `asc2.mjs` (multi-method ES256 JWT client), `submit.mjs`, `poll.mjs` (build
  processing poll), `asc.mjs` (GET-only version query).

## What didn't work

- **`xcrun agvtool new-marketing-version 1.0.2` does NOT apply** in this repo —
  left `MARKETING_VERSION` at 1.0.1. Fix: `sed -i '' 's/MARKETING_VERSION =
  1.0.1;/MARKETING_VERSION = 1.0.2;/g' MolApp.xcodeproj/project.pbxproj`.
  `agvtool new-version -all 8` (build number) DOES work. **[n/a]**
- Archive build-phase logs "Apple **Development**" signing — that's the build
  step; export re-signs with the distribution cert per ExportOptions.plist.
  Not an error, don't chase it. **[n/a]**

## Key files & commands

- `MolApp.xcodeproj/project.pbxproj` — `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`. Edit via sed, not agvtool.
- `ExportOptions.plist` — manual signing, team `6536ULS8SC`, profile "MolViewApp AppStore". Ready to reuse.
- ASC creds: key `~/.appstoreconnect/private_keys/AuthKey_CGV9U72GU7.p8`, issuer `9c0e6248-43c6-405d-8c0b-943a8e02ec61`, app id `6786979305`. Env vars `ASC_*` are UNSET — scripts hardcode the ids.
- `node scratchpad/submit.mjs` — full submit flow (idempotent-ish; reuses open reviewSubmission).

## Next steps

Nothing required. If continuing later:
1. Watch review outcome: `GET /v1/reviewSubmissions/1ed1a77a-01cb-4692-9807-a829964dbf72` → state.
2. **Next release = 1.0.3 / build 9+** (build 8 and version 1.0.2 are burned).
3. Decide whether to keep or delete this `HANDOFF.md` (untracked).

## Open questions / risks

- **App icon is now the green protein-ribbon render** by user choice. If it
  looks wrong on a home screen after review, that's a design revisit for a
  future version, not a bug in this ship.
- Review outcome unverified (just submitted).
