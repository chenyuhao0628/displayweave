[English](release-notes-v0.3.0-preview.2.md) | [简体中文](release-notes-v0.3.0-preview.2.zh-CN.md)

# DisplayWeave v0.3.0-preview.2 — UI and OpenDisplay compatibility

Version **0.3.0-preview.2**, Mac build / Android version code **17**, built locally on 2026-10-16 from native source `4f6e096`. The release tag additionally records documentation, website/download information and exact feeds. No production Apple signing or notarization is required for this preview path.

## Changes

- UI standard revision 2: page structure, component tokens, states, accessibility, copy and acceptance criteria, in English and Simplified Chinese.
- Mac sender/receiver workspaces, clearer settings groups, complete error text, explicit permission labels and a main-window entry in the compact menu panel.
- Shared iOS waiting/onboarding guide, device/status card and pairing-first settings; Android setup panels, consistent buttons and grouped settings.
- Main-screen OpenDisplay connection choices on Mac, iOS and Android. The sender can connect paired DisplayWeave and legacy OpenDisplay peers from the same device list. Early OpenDisplay hello messages without an install ID are accepted only by an explicit anonymous legacy plan.
- Corrected stale sender guidance that described all LAN connections as unencrypted. Known identities, pairing/revocation history and TLS failure still cannot silently downgrade.
- Fixed an intermittent Android listener bind conflict when switching client modes. Initial retries have a 250 ms total delay cap and stop cancels them; a persistent occupied port still produces recovery guidance.

## Connecting old and new clients

DisplayWeave → OpenDisplay: select **Client compatibility → Both clients** on the sending Mac, then connect. OpenDisplay → DisplayWeave: select **OpenDisplay compatibility** on the receiver's main screen, then connect from OpenDisplay. Legacy mode needs no pairing invitation and is unencrypted. DisplayWeave encrypted connections retain invitation pairing. A receiver listens in one selected mode at a time; changing it disconnects the current session.

See the [compatibility guide](opendisplay-compatibility.md) for tested protocol generations and limits. Core connection compatibility does not imply every upstream-specific optional feature or all historical binaries have completed physical acceptance.

## Verification

Passed locally: 52 Swift suites; six Android Java groups; universal Mac Debug/Release; iOS Simulator and unsigned arm64 device Release; Android Debug/Release and Lint; actual Apple↔Java TLS, Keychain/Keystore, isolated iOS/Android runtime and main-screen compatibility-mode restoration; site, bilingual docs and release checks; 12 packaging tests and 36 brand exports. The old anonymous handshake test failed before the fix and passed after it. Upstream `b9eec1f` hello/config fields and real synthetic H.264 loopback were checked.

Mac dark UI and Command-comma, iOS production light/dark waiting/onboarding/settings and enlarged text, and Android light/dark waiting/security with UI navigation were inspected. [The audit](ui-audit-2026-10-16.md) separates automated, visual and physical evidence. No independent online display was established, so virtual-display/capture interaction was skipped. Actual upstream-binary/device interoperability, USB/LAN performance, mobile landscape, full assistive technology, Mac minimum/light layout, Intel runtime, Pencil hardware and endurance remain pending.

Packaging checks verified Mac DMG/ZIP consistency, universal slices, original Sparkle key with independent Ed25519 signature verification, Android's unchanged certificate/version, and unsigned iOS arm64. Hosted CI and live publication checks are recorded separately in the GitHub Release.

The Android bind-conflict regression failed before the fix and passed afterward, including permanent-conflict and stop-cancellation cases. Eight consecutive main-screen encrypted → OpenDisplay → encrypted cycles passed in a disposable AVD, followed by background listener shutdown.

## Downloads

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.3.0-preview.2). Eight files: four binaries, two feeds, `DisplayWeave-v0.3.0-preview.2-source.tar.gz` and `SHA256SUMS.txt`. The manifest covers all seven other files. Source includes GPL-3.0, upstream attribution and build scripts. Update metadata uses the project GitHub Pages; binaries/source use GitHub Releases only.

Mac is ad-hoc signed and not notarized; first install may need system approval. Android keeps its existing installation signature. iOS is an unsigned re-signing input, not directly installable. Existing installed applications were not replaced by this task's isolated development/runtime tests.

| Asset | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `ea46bc18891964c4be53d5875a74d88bb2555f04f6d9c59897572fe7153552b0` |
| `DisplayWeave-macOS.dmg` | `e98505756aa347b9c4bcb56f9bad1aa8c24ffac36719962e519f58e685ebb7d9` |
| `DisplayWeave-Android.apk` | `a3c4e1f2c98e55073d63b305aaca7e5bf31510be18069b9b7de3138a3ae332bb` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `43010892e883272dc647e81943ed147368ad781631bdab8f345c488dd84f9d06` |
| `appcast.xml` | `4a22c5b49e73540943bd086273edd6601b5f4df292dfd6234214a794a2f92fd1` |
| `android-update.json` | `771d82a681f02ebe7edc9b8de1afb7955405d55633fde037e48eb10ea8c246f4` |
