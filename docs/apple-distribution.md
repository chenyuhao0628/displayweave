[English](apple-distribution.md) | [简体中文](apple-distribution.zh-CN.md)

# Production Apple distribution

The source now includes `tools/apple-distribution.py` for local signed archives and exports. It does not upload, create tags, edit feeds or install an app. All eventual public artifacts must go to this project's GitHub Releases; see [the distribution policy](release-downloads.md).

## Readiness and limits

On 2026-10-16 this Mac had zero **Developer ID Application** identities and zero **Apple Distribution** identities; an Apple Development identity is insufficient for these exports. Production signing and notarization are therefore **blocked by external credentials**. Offline tests prove validation and workflow failure behavior, not a notarized artifact. Published p8 remains the ad-hoc Mac / unsigned iOS preview; see [preview distribution](development-preview.md).

The existing preview script remains available. The new workflow never substitutes its relaxed library-validation entitlement for production signing. Production Mac uses the empty `Mac/OpenSidecarMac.entitlements` and hardened runtime. No key generation, key export, automatic provisioning or developer-portal upload occurs.

## Prerequisites and preflight

Use Xcode, XcodeGen, an existing distribution identity including its private key, and a clean committed source tree. Choose a new numeric `x.y.z` and a positive build number higher than **all** published builds. Check that number on GitHub before building; the tool cannot know about unpublished or externally staged releases.

For Mac, install a Developer ID Application identity and an existing `notarytool` Keychain profile for the same team. Keep the original Sparkle key in Keychain account `ed25519`. Locate Sparkle's resolved `bin` directory (containing `generate_keys` and `sign_update`); `generate_keys --account ed25519 -p` only reads the public key. Its value must match the key in `project.yml`.

```bash
python3 tools/apple-distribution.py preflight mac \
  --team TEAM_ID --identity CERTIFICATE_SHA1 \
  --notary-profile EXISTING_KEYCHAIN_PROFILE \
  --sparkle-bin build-verify-mac/SourcePackages/artifacts/sparkle/Sparkle/bin
```

Replace placeholders with existing local identities, never passwords. Preflight reads Keychain and runs `notarytool history` to verify access; it submits no artifact. A nonzero exit means prerequisites remain blocked.

For iOS, use Apple Distribution and install a matching profile through Xcode. The profile must be in `~/Library/MobileDevice/Provisioning Profiles/` or `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`. Pass its full path:

```bash
python3 tools/apple-distribution.py preflight ios \
  --team TEAM_ID --identity CERTIFICATE_SHA1 \
  --profile /absolute/path/to/installed.mobileprovision --method release-testing
```

`release-testing` requires registered devices; `app-store-connect` requires a store profile without a device list. Both use local `destination=export`; uploading to App Store Connect is a separate action. Profile team, expiry, exact bundle ID, certificate membership, UUID and debug entitlement are checked. Legacy application-identifier prefixes are respected rather than assumed equal to the team ID.

## Build and evidence

Replace `preflight` with `build`, keeping all other arguments, and add:

```text
--version 0.3.0 --build-number 16 --output build/apple-production-candidate-001
```

These are example numbers, not a reserved or released version. The output must be new and below `build/`. It is created with private directory permissions and an `INCOMPLETE` marker. Existing output is never overwritten or removed. Failed candidates retain logs and archives; choose a new directory for a new build. Logs and profiles can contain local identifiers; keep the whole directory out of Git and public uploads.

The workflow generates the Xcode project from `project.yml`, manually signs a Release archive, and locally exports it without automatic provisioning or managed version changes. It verifies the **actual export**: bundle/version/build, architectures, strict/deep code signatures, signing leaf/team and entitlements. Mac also checks the pinned feed and Sparkle key; iOS checks the embedded provisioning profile and application/team entitlements.

Mac archives contain arm64 and x86_64. A submission ZIP goes to Apple's notarization service with a 30-minute server wait and a bounded local timeout. Only `Accepted` can proceed to stapling, staple validation and Gatekeeper assessment. The final ZIP is created from the stapled app, signed using the existing Sparkle account and verified. iOS exports arm64 and verifies the extracted IPA. Only successful completion removes `INCOMPLETE` and writes `receipt.json` and `SHA256SUMS.txt`.

A timeout may leave an active Apple submission. Inspect the retained submission output and query its status before resubmitting; a timeout never means acceptance. A successful local receipt does not prove physical performance or publication. The production script emits a ZIP for Mac; the guided DMG remains in the preview workflow and is not claimed to be a notarized production DMG.

## Automated evidence

Run `python3 tools/test-apple-distribution.py`. Tests cover wrong certificate/team, expired or mismatched profiles, legacy prefixes, debug entitlements, bundle/feed/key substitution, immutable output and symlink escape, manual export settings, and notary/stapler failure gates. A synthetic workflow checks that no receipt/signature is produced before the required gates. Local preflight currently fails on the missing distribution identities as expected. A real signed/exported/notarized run is still required once those prerequisites are supplied.
