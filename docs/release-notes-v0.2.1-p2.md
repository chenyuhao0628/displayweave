[English](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p2.md) | [简体中文](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p2.zh-CN.md)

# DisplayWeave `v0.2.1-p2` release notes

DisplayWeave 0.2.1-p2 corrects Android automatic-update freshness and adds visible download progress.

## Changes

- Disables `HttpURLConnection` caches for the Android update manifest, sends explicit no-cache headers, and adds a per-request cache-busting query so a recently published version does not resolve to a cached older feed.
- Fetches the latest manifest again immediately before installation and after returning from unknown-source permission settings.
- Rejects a downloaded APK when its version, URL, size, or SHA-256 no longer matches the current manifest, while continuing to verify package identity, minimum SDK, version code, and pinned signing certificate.
- Coalesces duplicate download and install actions.
- Shows a horizontal percentage progress bar while the Android APK downloads.
- Removes interrupted partial downloads, invalid or superseded APKs, and an installed APK on the next application start. A verified APK awaiting user confirmation remains in the app-specific download directory.

## Validation

- All six Android standalone self-test groups pass.
- Android clean tests and Debug assembly pass with 61 Gradle tasks executed.
- The Android Release source set compiles as part of the test build.
- `git diff --check` passes.

The update flow has automated code/build validation. End-to-end installation of this build through the newly published feed remains a post-publication physical-device check.
