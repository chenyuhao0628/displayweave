[English](release-notes-v0.3.0-preview.2.md) | [简体中文](release-notes-v0.3.0-preview.2.zh-CN.md)

# DisplayWeave v0.3.0-preview.2 — UI and OpenDisplay compatibility

Version **0.3.0-preview.2**, Mac build / Android version code **17**, built locally on 2026-10-16 from native source `f8a2e67`. The release tag additionally records documentation, website/download information and exact feeds. No production Apple signing or notarization is required for this preview path.

## Changes

- UI standard revision 2: page structure, component tokens, states, accessibility, copy and acceptance criteria, in English and Simplified Chinese.
- Mac sender/receiver workspaces, clearer settings groups, complete error text, explicit permission labels and a main-window entry in the compact menu panel.
- Shared iOS waiting/onboarding guide, device/status card and pairing-first settings; Android setup panels, consistent buttons and grouped settings.
- Main-screen OpenDisplay connection choices on Mac, iOS and Android. The sender can connect paired DisplayWeave and legacy OpenDisplay peers from the same device list. Early OpenDisplay hello messages without an install ID are accepted only by an explicit anonymous legacy plan.
- Corrected stale sender guidance that described all LAN connections as unencrypted. Known identities, pairing/revocation history and TLS failure still cannot silently downgrade.

## Connecting old and new clients

DisplayWeave → OpenDisplay: select **Client compatibility → Both clients** on the sending Mac, then connect. OpenDisplay → DisplayWeave: select **OpenDisplay compatibility** on the receiver's main screen, then connect from OpenDisplay. Legacy mode needs no pairing invitation and is unencrypted. DisplayWeave encrypted connections retain invitation pairing. A receiver listens in one selected mode at a time; changing it disconnects the current session.

See the [compatibility guide](opendisplay-compatibility.md) for tested protocol generations and limits. Core connection compatibility does not imply every upstream-specific optional feature or all historical binaries have completed physical acceptance.

## Verification

Passed locally: 52 Swift suites; six Android Java groups; universal Mac Debug/Release; iOS Simulator and unsigned arm64 device Release; Android Debug/Release and Lint; actual Apple↔Java TLS, Keychain/Keystore, isolated iOS/Android runtime and main-screen compatibility-mode restoration; site, bilingual docs and release checks; 12 packaging tests and 36 brand exports. The old anonymous handshake test failed before the fix and passed after it. Upstream `b9eec1f` hello/config fields and real synthetic H.264 loopback were checked.

Mac dark UI and Command-comma, iOS production light/dark waiting/onboarding/settings and enlarged text, and Android light/dark waiting/security with UI navigation were inspected. [The audit](ui-audit-2026-10-16.md) separates automated, visual and physical evidence. No independent online display was established, so virtual-display/capture interaction was skipped. Actual upstream-binary/device interoperability, USB/LAN performance, mobile landscape, full assistive technology, Mac minimum/light layout, Intel runtime, Pencil hardware and endurance remain pending.

Packaging checks verified Mac DMG/ZIP consistency, universal slices, original Sparkle key with independent Ed25519 signature verification, Android's unchanged certificate/version, and unsigned iOS arm64. Hosted CI and live publication checks are recorded separately in the GitHub Release.

## Downloads

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.3.0-preview.2). Eight files: four binaries, two feeds, `DisplayWeave-v0.3.0-preview.2-source.tar.gz` and `SHA256SUMS.txt`. The manifest covers all seven other files. Source includes GPL-3.0, upstream attribution and build scripts. Update metadata uses the project GitHub Pages; binaries/source use GitHub Releases only.

Mac is ad-hoc signed and not notarized; first install may need system approval. Android keeps its existing installation signature. iOS is an unsigned re-signing input, not directly installable. Existing installed applications were not replaced by this task's isolated development/runtime tests.

| Asset | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `8a1368123ed65cd4e4fea6912e62db5d40f6da7dc239bdf18b8312ff8216b8d1` |
| `DisplayWeave-macOS.dmg` | `2354ed9f43723b32c74999efffe11ba950f49699a45a8b17a8c64b71ad7f7305` |
| `DisplayWeave-Android.apk` | `cd00fd37422ff16c9d9b8860abb062dd98b0519dadb0c3fd3047532ecf41fab0` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `50d0c7a7cadc49fc64bf79dc71afd3f6c755d59ac968307135e58f445d68a582` |
| `appcast.xml` | `af7c687f8a7c7646824345d6b0ff64ed04e16757a2898bad7e6cc99f9eba21ca` |
| `android-update.json` | `75bb67fdd2075770d2da72728099fe968ec7c4c53d590ef924b5c1f341dcc371` |
