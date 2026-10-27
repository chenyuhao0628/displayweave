[English](automatic-updates.md) | [简体中文](automatic-updates.zh-CN.md)

# Automatic update authenticity and signing

DisplayWeave publishes immutable Mac and Android artifacts in GitHub Releases and small update feeds on GitHub Pages:

- Mac feed: `https://chenyuhao0628.github.io/displayweave/appcast.xml`
- Android feed: `https://chenyuhao0628.github.io/displayweave/android-update.json`
- Mac first-install artifact: `DisplayWeave-macOS.dmg` (guided releases)
- Mac update artifact: `DisplayWeave-macOS.zip`
- Android artifact: `DisplayWeave-Android.apk`

The current stable release is
[`v0.3.3`](https://github.com/chenyuhao0628/displayweave/releases).
Install a current APK manually once; later builds use the in-app channel automatically.
This release includes both the guided DMG and the Sparkle ZIP payload.

The v0.3.3 Mac build uses a pinned Apple Development identity and is not notarized. Sparkle authenticates the ZIP with the unchanged embedded EdDSA key. Update authenticity and permission continuity are separate: packaging checks the Mac signing identity, while Sparkle verifies the update signature. Neither makes this a Developer ID notarized release.

2026-10-27: build 22 adds automatic Mac desktop matching while preserving existing selections. Downloads use GitHub Releases only; Mac and Android update metadata uses the project GitHub Pages site. See the [release notes](v0.3.3.md) for changes, permission continuity and verification limits.

The source workflow requires a pinned Apple signing identity and an upgrade comparison; see [permission continuity](../guides/mac-permissions.md). Previous release assets remain immutable; v0.3.3 was compared against the exact downloaded build 21 and retains its signing identity. See [local releases](local-release.md) for reproducible commands and validation requirements.

## One-time user migration

### Mac

1. Prefer `DisplayWeave-macOS.dmg` when the release provides it: open the DMG and drag DisplayWeave to Applications. Installing from the ZIP is equivalent after `DisplayWeave.app` is placed in `/Applications`; do not keep running the app from the DMG, ZIP, or Downloads folder.
2. Because the app is not notarized, Control-click the app and choose **Open**. If macOS still blocks it, use **System Settings → Privacy & Security → Open Anyway**, then confirm only if the download came from the official release. Do not enable **Anywhere** globally.
3. Launch it and check Screen Recording, Accessibility, and Local Network permissions. Ad-hoc upgrades and the initial transition to a stable signature may require reauthorization; later builds must retain the same signing identity.

After this migration, Sparkle checks the signed appcast automatically and may install newer builds. Sparkle lives inside `DisplayWeave.app`, not in the DMG or ZIP container, so either installation method receives the same later updates. The app also retains Sparkle's manual **Check for Updates** command. A release with an invalid EdDSA signature is rejected.

### Android

1. Manually install the first update-capable APK over the current `app.opendisplay.android` app. It must be signed with the existing DisplayWeave certificate; otherwise Android refuses replacement.
2. The app checks at most once per 24 hours when it resumes. **设置与帮助 → 检查更新** bypasses that throttle.
3. The client downloads from the exact matching GitHub Release path.
4. When an update is found, the app downloads it and verifies its byte count, SHA-256, package name, version code, minimum SDK, and signing certificate through one shared verification path. An integrity or identity failure always stops the update.
5. On the first update, Android may ask to allow this app to install unknown apps. Return to DisplayWeave after granting it. The Android Package Installer always presents the final confirmation; silent installation is not supported.

Declining the permission or installation leaves the receiver usable and does not affect Mac/iPhone connections.

## Release operation

Use [local publication](local-release.md) for the current stable release. It uses the pinned Mac Keychain identity, the existing Sparkle Keychain key and Android keystore without exporting private keys. Set a new version/build and compare the Mac app with the previous published app using `DISPLAYWEAVE_MAC_BASELINE_APP`. Only the first ad-hoc → fixed-signature migration uses `DISPLAYWEAVE_ALLOW_ADHOC_MIGRATION=1`.

1. Build the Mac DMG/ZIP, signed Android APK and unsigned iOS re-signing input; generate the two update feeds.
2. Verify versions, hashes, archive contents, all Mac architectures and signing continuity, the Sparkle Ed25519 signature and the pinned Android certificate.
3. Commit the reviewed documentation and exact feeds in `public/`; require full CI before integration. Tag the verified commit and create its tracked-source archive.
4. Upload eight explicit files to a draft GitHub Release: four binaries, two feeds, source archive and checksums. Verify remote bytes before publishing.
5. Publish the Release before merging the publication PR. The main-branch Pages deployment then publishes the website and feeds; compare both live feeds byte-for-byte with the Release assets.

The hosted **Release** workflow has no maintainer Mac identity or previous-release baseline and deliberately stops at preflight. It also does not generate the required source archive. Do not use it as a complete publication path until these prerequisites are provisioned and that missing source step is implemented. Its Sparkle/Android secret names remain in the workflow for future setup; no new credentials are uploaded by this release.

Never replace a published asset or use `--clobber`. Every correction receives a new higher build number.

## Key backup and recovery

Keep two encrypted offline backups of the Sparkle private key and of the Android JKS plus its alias/password. The repository contains only the Sparkle public key and the Android certificate fingerprint.

- Losing the Sparkle private key means installed Mac builds cannot trust a newly generated update key. Recovery requires another manual migration build.
- Losing the Android JKS or password means Android cannot install a newly signed APK over existing installations. Recovery requires uninstalling the app, which may remove app data.
- If a secret may be exposed, stop publication, preserve evidence, rotate the GitHub secret, and follow the relevant migration limitation above. Never commit a private key.

## Feed rollback and incident handling

Release assets are immutable. To stop a bad offer, restore `public/appcast.xml` and `public/android-update.json` to the last known-good feed and redeploy Pages. A feed rollback prevents new downloads but does not downgrade devices that already installed the higher build. Publish a corrected release with a higher build number to recover those devices.

Before making feeds public, run:

```bash
DISPLAYWEAVE_VERSION_NAME=x.y.z DISPLAYWEAVE_BUILD_NUMBER=N \
  ./tools/verify-update-release.sh build/update-release
./tools/check-release-links.sh
./tools/check-bilingual-docs.sh
```

The iOS receiver is not updated by this channel. Its `_opensidecar._tcp` service, port `9000`, length-prefix framing, H.264 compatibility, and legacy hello defaults remain independent of Mac and Android update publication.
