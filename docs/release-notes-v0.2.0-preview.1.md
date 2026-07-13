[English](release-notes-v0.2.0-preview.1.md) | [简体中文](release-notes-v0.2.0-preview.1.zh-CN.md)

# DisplayWeave `v0.2.0-preview.1` release notes

[GitHub prerelease](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.1)

## Highlights

- Mac adds Sparkle updates authenticated with an embedded EdDSA public key. No
  Apple Developer Program account is required, but the app remains ad-hoc
  signed and not notarized.
- Android adds a daily foreground check and a manual check in **Settings &
  Help**. Downloads are verified before Android opens its system installer.
- Update prompts, permissions, and cancelled installations no longer block the
  display receiver from resuming.
- The Apple receiver rendering path now keeps the Metal layer and drawable size
  synchronized, fixing the iPhone connection case that could show a black
  screen while video frames were arriving.
- The existing iOS/OpenDisplay receiver protocol remains compatible.

## One-time migration

- **Mac:** download `DisplayWeave-macOS.zip`, verify its checksum, and manually
  replace the old app in `/Applications`. Gatekeeper may require Control-click
  → **Open** or Privacy & Security → **Open Anyway**. Later releases can use the
  signed Sparkle channel.
- **Android:** install `DisplayWeave-Android.apk` over the existing
  `app.opendisplay.android` package once. Later updates can be found in-app, but
  Android still requires unknown-source permission and final system approval.
- **iOS/iPadOS:** this release still provides an unsigned re-signing input. It
  is not directly installable and is not part of the automatic-update channel.

## Security boundaries

- Sparkle rejects a Mac archive whose EdDSA signature does not match the public
  key embedded in the installed app. This verifies the update; it does not
  provide Developer ID signing or notarization.
- Android verifies byte count, SHA-256, package name, increasing version code,
  minimum SDK, and the pinned signing certificate before installation.
- Release assets are immutable. A correction must use a new, higher build rather
  than replacing an existing download.
- WiFi transport is still intended for a trusted local network and does not add
  encrypted pairing in this preview.

## iOS and OpenDisplay compatibility

The Mac keeps `_opensidecar._tcp` discovery, TCP port `9000`, four-byte
length-prefix framing, Annex B H.264 video, and the legacy hello defaults. The
iOS artifact is still `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa`,
so existing compatible OpenDisplay receivers can continue to connect.

## Assets and verification

| File | SHA-256 or role |
| --- | --- |
| `DisplayWeave-macOS.zip` | `35c828abc9200affe8a63602519f63e56ca7aff4ca6a88d6bbcb2f2bf009bec5` |
| `DisplayWeave-Android.apk` | `24588906ccde36958355d8e72bae54fa1e6f8244c3fca832b81c9a05bd7519d9` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `fee1b7d8c1b81bac33b91b11dfaeeb608ccc35050ccc4bcd796178227acdedfa` |
| `appcast.xml` | `efc966fd6f051417a6f06bf12fe31edca9d8728fa19ae730619e694a1df1d250` |
| `android-update.json` | `453c7e27ed3c261cfbca5f5bf1ba7c4d8861f7c0563cf8fc207254185176bf38` |
| `SHA256SUMS.txt` | Checksum manifest for the five files above |

- Mac feed: https://chenyuhao0628.github.io/displayweave/appcast.xml
- Android feed: https://chenyuhao0628.github.io/displayweave/android-update.json
- Android certificate SHA-256:
  `89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d`

Release verification covered 17 Swift tests, 6 Android self-tests, release
builds for Mac/iOS/Android, update metadata consistency, and tampered-download
rejection. GitHub Release, Pages deployment, and both live feeds were also
checked.

## Deferred evidence

This preview does not claim a completed two-Android-device run, a controlled
same-condition USB/WiFi matrix, or the planned 30-minute/2-hour endurance runs.
The OnePlus and iPhone observations in the Preview 2 stability report remain
prior evidence and were not rerun as part of this publication.
