[English](development-preview.md) | [简体中文](development-preview.zh-CN.md)

# DisplayWeave `v0.1.0-preview.2` Development Distribution

- `DisplayWeave-Preview-0.1-macOS.zip`: ad-hoc signed and not notarized. Verify the source and SHA-256 before following documented Gatekeeper steps.
- `DisplayWeave-Preview-0.1-Android.apk`: v2 release-signed with an independent keystore outside the repository; side-loadable without Google Play. Verify the certificate fingerprint before first install.
- `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa`: unsigned re-signing input, not directly installable. The user must provide a valid signing identity.
- `SHA256SUMS.txt`: SHA-256 for all three packages.

Build the complete set with:

```bash
./tools/package-preview-0.1.sh
```

The Android keystore lives under `~/Library/Application Support/DisplayWeave/Signing/`; its password is stored in Keychain. Neither belongs in Git. A free Apple Personal Team is suitable only for maintainer testing on registered devices, not general public distribution. DisplayWeave does not endorse third-party signing services.

This release is a development preview. It has verified Android ADB-forward USB, but it does not provide Developer ID notarization, App Store/TestFlight distribution, Google Play distribution, encrypted WiFi pairing, or iOS/iPadOS 120Hz.
