# DisplayWeave v0.2.0 Preview 1 Bilingual Documentation Refresh Design

## Status

Approved direction: update every current user-facing entry point to the live
`v0.2.0-preview.1` prerelease, add a dedicated bilingual release-note pair,
and preserve older Preview 2 reports and design records as historical evidence.

## Goal

Make the English and Simplified Chinese documentation describe the release
that users can download today, including its automatic-update migration,
security boundaries, exact assets, compatibility guarantees, and remaining
experimental limitations. A user following either language must reach the
same release and receive the same operational warnings.

## Authoritative Release Facts

- Release: `v0.2.0-preview.1` (`0.2.0-preview.1`, build/version code `2`).
- Release URL:
  `https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.1`.
- It is a prerelease targeting source commit `bb50d91`.
- Published assets:
  - `DisplayWeave-macOS.zip`
  - `DisplayWeave-Android.apk`
  - `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa`
  - `appcast.xml`
  - `android-update.json`
  - `SHA256SUMS.txt`
- SHA-256:
  - Mac ZIP: `35c828abc9200affe8a63602519f63e56ca7aff4ca6a88d6bbcb2f2bf009bec5`
  - Android APK: `24588906ccde36958355d8e72bae54fa1e6f8244c3fca832b81c9a05bd7519d9`
  - iOS input: `fee1b7d8c1b81bac33b91b11dfaeeb608ccc35050ccc4bcd796178227acdedfa`
- Android certificate SHA-256:
  `89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d`.
- Live feeds:
  - `https://chenyuhao0628.github.io/displayweave/appcast.xml`
  - `https://chenyuhao0628.github.io/displayweave/android-update.json`

## Information Architecture

### Current entry points

The following English/Chinese surfaces become current-release documentation:

- root `README.md` and `README.zh-CN.md`;
- `AndroidReceiver/README.md` and `AndroidReceiver/README.zh-CN.md`;
- `docs/development-preview.md` and its Chinese peer;
- `docs/release-checklist.md` and its Chinese peer;
- `docs/automatic-updates.md` and its Chinese peer;
- `docs/README.md` and `docs/README.zh-CN.md`;
- website content in `src/content.ts` and release metadata in `index.html`.

These surfaces use the new tag and stable Mac/Android filenames. They must not
offer the old `v0.1.0-preview.2` assets as the current download.

### New current release notes

Create:

- `docs/release-notes-v0.2.0-preview.1.md`
- `docs/release-notes-v0.2.0-preview.1.zh-CN.md`

Both documents cover the same sections: highlights, automatic-update behavior,
one-time migration, security/signing limitations, iOS compatibility, exact
assets and checksums, verified evidence, deferred tests, and links to the live
Release and feeds.

### Historical material

Keep `docs/release-notes-preview-0.1*`, stability reports, performance audits,
old implementation plans, and design specifications intact. The documentation
index labels the old release notes as historical instead of silently rewriting
their past claims. Historical references to Preview 2 are therefore valid and
excluded from the active-download stale-reference gate.

## Platform Copy Contract

### macOS

- The first update-capable build must be installed manually in `/Applications`.
- The app is ad-hoc signed and not notarized; Control-click/Open or Privacy &
  Security/Open Anyway may be required.
- Later builds are checked and authenticated by Sparkle using the embedded
  EdDSA public key. This does not turn the app into a notarized package.

### Android

- The new APK must first be installed over the existing package with the same
  pinned signing certificate.
- Automatic checks occur at most daily; manual checks bypass the throttle.
- Downloads are verified by size, SHA-256, package, version, minimum SDK, and
  the pinned certificate before Android's system installer is opened.
- Unknown-source permission and final installation always require system/user
  confirmation; no silent-install claim is allowed.

### iOS/iPadOS

- The asset remains an unsigned re-signing input, not a directly installable
  IPA.
- Existing `_opensidecar._tcp`, port `9000`, four-byte length framing, Annex B
  H.264, and legacy hello defaults remain compatible and outside the new
  Mac/Android update channel.

## Evidence and Limitations

Current pages may claim successful automated tests, Mac/iOS/Android Release
builds, signed artifact verification, and one-byte tamper rejection because
those were exercised for this release. They must continue to identify two
simultaneous Android devices, the controlled same-condition USB/WiFi benchmark,
and 30-minute/2-hour endurance runs as deferred. Existing single-device
Preview 2 hardware evidence may be cited as prior evidence, not relabeled as a
new v0.2.0 physical-device rerun.

## Consistency Gates

- Add the new release-note pair to `tools/check-bilingual-docs.sh`.
- Update `tools/check-release-links.sh` so active sources require the new tag,
  exact six asset names, and reject old Preview 2 download filenames in active
  entry points while ignoring explicitly historical documents.
- `pnpm build`, `pnpm run check:docs`, and `pnpm run check:release` must pass.
- Rendered English and Chinese pages must contain the new tag and direct asset
  URLs.
- Public feed URLs and the GitHub Release must remain reachable and agree with
  the documented version, hashes, and certificate.
- English and Chinese pages must match in facts and limitations; stylistic
  translation need not be word-for-word.

## Non-Goals

- Do not rewrite historical measurement results or old design/plan records.
- Do not claim Apple notarization, App Store/TestFlight, Google Play, silent
  Android installation, completed multi-device/endurance validation, or iOS
  automatic updates.
- Do not change application code, protocols, signing keys, Release assets, or
  the already-published feeds as part of this documentation refresh.
