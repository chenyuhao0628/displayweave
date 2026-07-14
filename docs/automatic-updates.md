[English](automatic-updates.md) | [简体中文](automatic-updates.zh-CN.md)

# Automatic updates without an Apple developer account

DisplayWeave publishes immutable Mac and Android artifacts in GitHub Releases and small update feeds on GitHub Pages:

- Mac feed: `https://chenyuhao0628.github.io/displayweave/appcast.xml`
- Android feed: `https://chenyuhao0628.github.io/displayweave/android-update.json`
- Mac first-install artifact: `DisplayWeave-macOS.dmg` (guided releases)
- Mac update artifact: `DisplayWeave-macOS.zip`
- Android artifact: `DisplayWeave-Android.apk`

The current migration release is
[`v0.2.1`](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.1).
Older builds cannot discover this channel by themselves: install this release
manually once, then use automatic updates for later versions.
This release includes both the guided DMG and the Sparkle ZIP payload.

The Mac build is ad-hoc signed and not notarized. Sparkle authenticates its ZIP with the embedded EdDSA public key, so subsequent updates can be verified without Apple Developer Program credentials. This does not make the first download Gatekeeper-trusted or equivalent to a notarized release.

## One-time user migration

### Mac

1. Prefer `DisplayWeave-macOS.dmg` when the release provides it: open the DMG and drag DisplayWeave to Applications. Installing from the ZIP is equivalent after `DisplayWeave.app` is placed in `/Applications`; do not keep running the app from the DMG, ZIP, or Downloads folder.
2. Because the app is not notarized, Control-click the app and choose **Open**. If macOS still blocks it, use **System Settings → Privacy & Security → Open Anyway**, then confirm only if the download came from the official release. Do not enable **Anywhere** globally.
3. Launch it once and retain the existing Screen Recording, Accessibility, and Local Network permissions. Moving or renaming the app later can cause macOS to ask for permissions again.

After this migration, Sparkle checks the signed appcast automatically and may install newer builds. Sparkle lives inside `DisplayWeave.app`, not in the DMG or ZIP container, so either installation method receives the same later updates. The app also retains Sparkle's manual **Check for Updates** command. A release with an invalid EdDSA signature is rejected.

### Android

1. Manually install the first update-capable APK over the current `app.opendisplay.android` app. It must be signed with the existing DisplayWeave certificate; otherwise Android refuses replacement.
2. The app checks at most once per 24 hours when it resumes. **设置与帮助 → 检查更新** bypasses that throttle.
3. When an update is found, the app downloads it and verifies its byte count, SHA-256, package name, version code, minimum SDK, and signing certificate.
4. On the first update, Android may ask to allow this app to install unknown apps. Return to DisplayWeave after granting it. The Android Package Installer always presents the final confirmation; silent installation is not supported.

Declining the permission or installation leaves the receiver usable and does not affect Mac/iPhone connections.

## Release operation

GitHub Actions requires exactly these repository secrets:

- `SPARKLE_PRIVATE_KEY`
- `DISPLAYWEAVE_ANDROID_KEYSTORE_BASE64`
- `DISPLAYWEAVE_ANDROID_STORE_PASSWORD`
- `DISPLAYWEAVE_ANDROID_KEY_ALIAS`
- `DISPLAYWEAVE_ANDROID_KEY_PASSWORD`

Run the **Release** workflow. The first run may create or update the release-please PR; merge that PR and run **Release** again. For a created release, the workflow uses the tag as the display version and `github.run_number` as the monotonic build/version code. It then:

1. builds and tests the ad-hoc Mac app, unsigned iOS compatibility target, and signed Android APK;
2. generates an EdDSA-signed appcast and a pinned-certificate Android JSON feed;
3. verifies versions, hashes, archive structure, and Android signing;
4. uploads immutable assets; and
5. passes both signed feeds to a protected Pages deployment job without a bot
   commit to `main`.

Do not replace or use `--clobber` on a published update asset. Publish a new, higher build number for every correction.

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
