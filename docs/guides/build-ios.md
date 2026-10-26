[English](build-ios.md) | [简体中文](build-ios.zh-CN.md)

# Build and install the iOS receiver

v0.3.1 publishes `DisplayWeave-iOS-unsigned-resigning-input.ipa` for device re-signing. It is an unsigned arm64 device build, not a Simulator package or a directly installable app. Most source developers can build with Xcode and their own valid signing identity. See [current artifacts](../releases/current.md).

## Build from source

1. Install Xcode and the required iOS SDK; sign in with your Apple account in Xcode.
2. From the repository root, run `./generate.sh` (requires XcodeGen), then open `OpenSidecar.xcodeproj`.
3. Select `OpenSidecariOS`, then **Signing & Capabilities**. Choose your own team and a provisioning configuration that matches your device.
4. Keep the repository's bundle identifiers unchanged. If your personal team requires a unique identifier, use a local development override; do not commit it or treat it as compatible with the published app's identity/keychain.
5. Connect your device, choose it as the run destination and run the app. Follow the device's developer/trust prompts as needed.
6. Keep the receiver foregrounded, then use the [pairing workflow](secure-transport.md).

Personal development provisioning can expire; use the validity shown by Xcode and rebuild/reinstall when needed. Regenerating the Xcode project can replace local project edits. Keep signing material outside Git. The [unsigned Simulator compile command](../development/workflow.md) tests compatibility without producing a device installation.

## Re-signing the published IPA

Provide your own valid certificate and matching provisioning profile. Re-signing must retain valid application/keychain entitlements for that identity. A changed signing or access-group identity can make earlier pairing data inaccessible; pair again when required. DisplayWeave provides no signing credentials and does not endorse signing services. [Production archive/export tooling](../releases/apple-distribution.md) documents distribution prerequisites separately.
