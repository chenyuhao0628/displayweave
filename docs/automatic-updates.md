[English](automatic-updates.md) | [简体中文](automatic-updates.zh-CN.md)

# Automatic updates without an Apple developer account

DisplayWeave publishes immutable Mac and Android artifacts in GitHub Releases and small update feeds on GitHub Pages:

- Mac feed: `https://chenyuhao0628.github.io/displayweave/appcast.xml`
- Android feed: `https://chenyuhao0628.github.io/displayweave/android-update.json`
- Mac first-install artifact: `DisplayWeave-macOS.dmg` (guided releases)
- Mac update artifact: `DisplayWeave-macOS.zip`
- Android artifact: `DisplayWeave-Android.apk`

The current development release is
[`v0.2.1-p8`](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.1-p8).
Android p5 cannot trust the new Cloudflare hostname, so install p6 or newer manually once.
p6 and later can use the dual-source channel automatically.
This release includes both the guided DMG and the Sparkle ZIP payload.

The Mac build is ad-hoc signed and not notarized. Sparkle authenticates its ZIP with the embedded EdDSA public key, so subsequent updates can be verified without Apple Developer Program credentials. This does not make the first download Gatekeeper-trusted or equivalent to a notarized release.

2026-10-16: GitHub Actions is unavailable, so this release is built locally. Public GitHub access and Pages feeds still return 404; use the [Cloudflare download page](https://downloads.urlget.cyou/displayweave/). Mac/Android update checks still depend on the original Pages URLs; install manually until they recover. Mirrored feed copies do not change client URLs.

See [local releases](local-release.md) for reproducible commands and validation requirements.

## One-time user migration

### Mac

1. Prefer `DisplayWeave-macOS.dmg` when the release provides it: open the DMG and drag DisplayWeave to Applications. Installing from the ZIP is equivalent after `DisplayWeave.app` is placed in `/Applications`; do not keep running the app from the DMG, ZIP, or Downloads folder.
2. Because the app is not notarized, Control-click the app and choose **Open**. If macOS still blocks it, use **System Settings → Privacy & Security → Open Anyway**, then confirm only if the download came from the official release. Do not enable **Anywhere** globally.
3. Launch it once and retain the existing Screen Recording, Accessibility, and Local Network permissions. Moving or renaming the app later can cause macOS to ask for permissions again.

After this migration, Sparkle checks the signed appcast automatically and may install newer builds. Sparkle lives inside `DisplayWeave.app`, not in the DMG or ZIP container, so either installation method receives the same later updates. The app also retains Sparkle's manual **Check for Updates** command. A release with an invalid EdDSA signature is rejected.

### Android

1. Manually install the first update-capable APK over the current `app.opendisplay.android` app. It must be signed with the existing DisplayWeave certificate; otherwise Android refuses replacement.
2. The app checks at most once per 24 hours when it resumes. **设置与帮助 → 检查更新** bypasses that throttle.
3. The p6 and newer clients try `downloads.urlget.cyou` first and fall back to the exact matching GitHub Release only for connection, HTTP availability, or transport failures.
4. When an update is found, the app downloads it and verifies its byte count, SHA-256, package name, version code, minimum SDK, and signing certificate through one shared verification path. Integrity or identity failures never trigger another mirror.
5. On the first update, Android may ask to allow this app to install unknown apps. Return to DisplayWeave after granting it. The Android Package Installer always presents the final confirmation; silent installation is not supported.

Declining the permission or installation leaves the receiver usable and does not affect Mac/iPhone connections.

## Release operation

GitHub Actions requires exactly these repository secrets:

- `SPARKLE_PRIVATE_KEY`
- `DISPLAYWEAVE_ANDROID_KEYSTORE_BASE64`
- `DISPLAYWEAVE_ANDROID_STORE_PASSWORD`
- `DISPLAYWEAVE_ANDROID_KEY_ALIAS`
- `DISPLAYWEAVE_ANDROID_KEY_PASSWORD`

For an explicit release, create its tag and draft GitHub Release, then run **Release** with `release_tag` and a `build_number` higher than every public Mac/Android build. Without an explicit tag, release-please may first create a version PR; merge it before rerunning. The tag determines the display version. If `build_number` is omitted, the workflow uses `github.run_number`; confirm that this is still monotonic.

For a new mirror snapshot, set `deploy_feeds=false` (the default is `true`). The workflow:

1. builds and tests the ad-hoc Mac app, unsigned iOS compatibility target, and signed Android APK;
2. generates an appcast with an EdDSA-signed ZIP enclosure and a pinned-certificate Android JSON feed;
3. verifies versions, hashes, archive structure and Android signing; and
4. uploads the seven immutable assets to the draft release while leaving the live feeds unchanged.

Download and independently verify those assets. Deploy a complete Cloudflare snapshot containing the new files and every historical release that must remain accessible. Verify the live mirror bytes before publishing the GitHub Release. Copy the exact generated `appcast.xml` and `android-update.json` into `public/`, update the release links and checksums, and merge the reviewed publication PR after CI passes. The main-branch Pages deployment then publishes the website and feeds together. Persisting the generated feeds prevents a later site deployment from rolling the update channel back.

With `deploy_feeds=true`, the workflow sends the feeds directly to the protected Pages job. Use this only when all referenced downloads are already accessible, and still persist those exact feeds in `public/`.

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
