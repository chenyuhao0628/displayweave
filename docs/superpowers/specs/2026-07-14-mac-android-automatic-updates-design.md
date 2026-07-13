# DisplayWeave Mac and Android Automatic Updates Design

**Date:** 2026-07-14

## Objective

Add a maintainable update channel for the macOS sender and Android receiver while preserving wire-level compatibility with the current OpenDisplay iOS receiver. The macOS channel must work without an Apple Developer Program membership. Android updates must replace the installed APK without requiring an uninstall and must preserve application data.

## Confirmed Constraints

- The repository has no GitHub Actions secrets configured.
- The current Mac has no Sparkle EdDSA private key in its login Keychain.
- The public key currently embedded as `SUPublicEDKey` therefore cannot be used for future releases.
- The first release containing the new Sparkle public key is a one-time manual migration. Every later Mac release can update through Sparkle.
- macOS artifacts cannot be Developer ID signed or notarized. They remain ad-hoc signed and may require explicit Gatekeeper approval on first installation.
- Android cannot silently install an APK in an ordinary, unmanaged application. The app can check, download, and verify automatically, but Android presents the final system installation confirmation.
- The current Android signing JKS and alias remain the permanent update identity. Losing or changing this key breaks APK replacement upgrades.
- iOS has no update work in this scope. Its existing Bonjour discovery and stream protocol must remain compatible.

## Chosen Architecture

GitHub Releases stores immutable Mac ZIP and Android APK artifacts. GitHub Pages hosts two small mutable feeds:

- `https://chenyuhao0628.github.io/displayweave/appcast.xml` for Sparkle.
- `https://chenyuhao0628.github.io/displayweave/android-update.json` for Android.

One release workflow builds both update artifacts from the same Git tag, uploads them to that tag's GitHub Release, produces signed/verifiable feed metadata, commits the feeds under `public/`, and explicitly dispatches the Pages workflow.

This keeps artifact bandwidth on GitHub Releases, avoids unauthenticated GitHub API rate limits in clients, and reuses the repository's existing static site deployment.

## Version Model

Every published update has two version values:

- Display version: the release tag without its `v` prefix, for example `0.2.0-preview.3`.
- Monotonic build version: `github.run_number`.

The Mac build receives the display version as `MARKETING_VERSION` and the monotonic build version as `CURRENT_PROJECT_VERSION`. Sparkle compares `CFBundleVersion`, so each workflow run intended for publication must have a greater run number than the previous published update.

Android receives the display version as `versionName` and the monotonic build version as `versionCode`. Update eligibility is strictly `remoteVersionCode > installedVersionCode`; display-version parsing is never used to decide whether an update is newer.

## macOS Update Channel

### Application behavior

The existing `SPUStandardUpdaterController` remains the only updater instance. Project configuration changes are limited to the update behavior:

- Replace the unusable `SUPublicEDKey` with the newly generated public key.
- Point `SUFeedURL` at the GitHub Pages appcast.
- Set `SUEnableAutomaticChecks` to `true`.
- Set `SUAutomaticallyUpdate` to `true` so Sparkle may stage an update and install it at a safe application-termination point after the user has accepted update checks.
- Keep the existing manual “检查更新…” control.

Sparkle owns feed polling, version comparison, archive download, EdDSA verification, bundle replacement, and relaunch. The sender does not implement a second networking or installer layer.

### Signing and migration

Sparkle's `generate_keys` creates a new EdDSA key pair. The public key is committed through `project.yml`. The private key is exported directly into the `SPARKLE_PRIVATE_KEY` Actions secret without printing it in logs and remains backed up outside the repository.

The Mac ZIP is ad-hoc signed with `Mac/OpenSidecarMacAdHoc.entitlements`. The release workflow verifies the bundle recursively with `codesign --verify --deep --strict` before packaging. The archive is then signed with Sparkle EdDSA and referenced from the generated appcast.

Existing users must manually replace their application with the first build containing the new public key. This migration requirement is documented in the release notes. The obsolete key is not retained because its private half is unavailable.

### User experience and failure behavior

- Feed unavailable, offline, or malformed: keep running the installed version; Sparkle retries on its normal schedule.
- Invalid EdDSA signature: reject the update and leave the installed app unchanged.
- App is on a read-only volume: manual check surfaces Sparkle's installation failure; documentation instructs the user to move DisplayWeave to `/Applications`.
- Active stream: no custom forced termination occurs. Sparkle uses its normal user-driver flow and safe installation timing.
- Gatekeeper: documentation states that the initial migrated build is ad-hoc signed and may require right-click Open or approval in Privacy & Security.

## Android Update Channel

### Metadata schema

`public/android-update.json` is UTF-8 JSON with this exact shape:

```json
{
  "schemaVersion": 1,
  "packageName": "app.opendisplay.android",
  "versionCode": 123,
  "versionName": "0.2.0-preview.3",
  "minimumSdk": 26,
  "apkUrl": "https://github.com/chenyuhao0628/displayweave/releases/download/v0.2.0-preview.3/DisplayWeave-Android.apk",
  "apkSize": 168421,
  "sha256": "lowercase-64-character-hex",
  "signingCertificateSha256": "89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d",
  "publishedAt": "2026-07-14T00:00:00Z",
  "releaseNotesUrl": "https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.3"
}
```

The certificate fingerprint is pinned to the existing DisplayWeave Preview JKS signer. Publication fails if the built APK does not match it.

### Components

Android update logic is isolated from `OpenDisplayServer` and the video lifecycle:

- `UpdateManifest`: immutable parsed metadata and schema validation.
- `UpdatePolicy`: pure decisions for version eligibility, daily automatic-check throttling, and user-facing failure classification.
- `UpdateClient`: HTTPS metadata fetch and APK download on a dedicated executor with bounded connect/read timeouts.
- `UpdateVerifier`: streaming SHA-256, byte-count, package-name, version-code, minimum-SDK, and signing-certificate verification using `PackageManager` archive inspection.
- `UpdateInstaller`: `FileProvider` URI creation, unknown-sources permission routing, and `ACTION_INSTALL_PACKAGE` launch.
- `UpdateCoordinator`: lifecycle orchestration and callbacks consumed by `MainActivity`.

No third-party Android dependency is added. JSON uses `org.json`, networking uses `HttpURLConnection`, downloads use an application-private external downloads directory, and the system package installer performs replacement.

### Check and install flow

1. On app resume, `UpdateCoordinator` checks only if the last successful automatic metadata check is at least 24 hours old. A manual check bypasses this throttle.
2. Fetch metadata over HTTPS and validate schema, package name, SDK floor, URL scheme, version fields, hashes, and fingerprint format.
3. If `remoteVersionCode <= installedVersionCode`, record a successful check and report up to date only for a manual request.
4. If newer, show a non-blocking update prompt containing version name and a release-notes link.
5. On user acceptance, download to a temporary `.apk.part` file while the receiver remains usable.
6. Verify the completed file. Only after every check succeeds is `.apk.part` atomically renamed to `.apk`.
7. If unknown-app installation is not allowed, open the per-application system permission page and retain the verified APK path.
8. Launch the Android package installer through `FileProvider`. Android asks the user to confirm replacement.
9. Cancellation or failure leaves the installed application and receiver service untouched. Invalid files are deleted.

### Android UI

The settings dialog gains an “应用更新” row with installed version, last-check state, and a “检查更新” action. Automatic checks show a dialog only when a newer version exists or a security validation fails. Routine offline failures remain in the settings status and do not interrupt streaming.

During an active stream, the app may notify that an update is ready but never launches the installer without a user tap. The user can defer installation.

### Android permissions and provider

The manifest adds:

- `android.permission.REQUEST_INSTALL_PACKAGES`.
- AndroidX `FileProvider` is not used because the project has no AndroidX dependency. A project-owned, non-exported `UpdateFileProvider` with authority `app.opendisplay.android.update-files` exposes only `DisplayWeave-update.apk` under the app's external `Download/updates` directory with read-only URI grants.

The provider rejects path traversal, write modes, unknown filenames, and files outside the verified-update directory. It reports the APK MIME type and supports only the query/open operations required by Package Installer.

## Release Automation and Secrets

The update publication job requires these Actions secrets:

- `SPARKLE_PRIVATE_KEY`: exported Sparkle EdDSA private key.
- `DISPLAYWEAVE_ANDROID_KEYSTORE_BASE64`: base64 of the existing JKS.
- `DISPLAYWEAVE_ANDROID_STORE_PASSWORD`.
- `DISPLAYWEAVE_ANDROID_KEY_ALIAS`: `displayweave-preview`.
- `DISPLAYWEAVE_ANDROID_KEY_PASSWORD`.

The workflow decodes secrets into runner-temporary files, restricts file permissions, builds, and deletes temporary key material in an `always()` cleanup step. Secret values are never echoed.

The existing Developer ID, notarization, match, and TestFlight assumptions are removed from the Mac/Android update publication path. iOS release automation may remain a separately guarded job, but missing Apple credentials cannot block Mac or Android update publication.

Publication order is deliberately fail-safe:

1. Build and test Mac, Android, and the unchanged iOS target.
2. Verify Mac nested code signatures and Android signing fingerprint.
3. Upload immutable Mac ZIP and Android APK to the existing tag release.
4. Generate and validate appcast and Android JSON against those uploaded artifact URLs.
5. Commit both feeds to `public/`.
6. Dispatch Pages.

A failure before step 5 cannot advertise an unavailable or unverified update.

## iOS and Legacy OpenDisplay Compatibility

The update work must not change any of the following:

- Bonjour service type `_opensidecar._tcp`.
- Receiver TCP port `9000`.
- Four-byte big-endian length framing.
- H.264 Annex B payload representation.
- Existing hello/control fields or their meanings.
- Default behavior when capability fields are absent.
- OpenSidecariOS bundle source, receiver, renderer, or signing instructions.

Mac capability parsing continues treating an older iOS hello as H.264-only, 60 FPS, and transport unknown. Existing tests are extended with an explicit legacy hello fixture, and the release gate builds the iOS target with signing disabled. No updater metadata is sent across the display protocol.

## Testing Strategy

### Mac

- A self-test inspects generated build settings and asserts the Pages feed URL, new public key, automatic checks, automatic staging, and monotonically injected build number.
- A fixture archive and temporary appcast exercise Sparkle's signing/generation tools during release-script validation without exposing the production private key.
- Release build, recursive `codesign` verification, ZIP integrity, and SHA-256 validation remain mandatory.

### Android

- Pure Java self-tests cover valid/invalid metadata, version eligibility, 24-hour throttling, URL restrictions, hash/fingerprint normalization, and failure classification.
- Verifier tests use fixture files for SHA-256 and size checks; Android package/signature inspection is covered by an instrumentation-light integration seam around `PackageManager`.
- Existing protocol, lifecycle, connection, and video policy self-tests remain mandatory.
- Gradle assembles both debug and signed release APKs; `apksigner verify --print-certs` must match the pinned fingerprint.

### Compatibility and publication

- Mac `DeviceCapabilitiesSelfTest` gains a legacy OpenDisplay iOS hello case.
- Both macOS and iOS Xcode schemes build with signing disabled as a compatibility gate.
- A repository script validates `appcast.xml`, `android-update.json`, referenced versions, artifact names, hashes, sizes, HTTPS URLs, and Android certificate fingerprint before feeds are published.
- A controlled end-to-end release dry run uses a prerelease tag and confirms: old migrated Mac detects the new Mac build; installed Android accepts the newer APK as a replacement; current OpenDisplay iOS still connects and renders without protocol changes.

## Documentation and Operational Recovery

English and Chinese release/update documentation explains:

- The one-time Mac manual migration to the new EdDSA key.
- Gatekeeper approval for ad-hoc Mac builds.
- Moving the Mac app to `/Applications`.
- Android's one-time “install unknown apps” permission and per-update confirmation.
- Backing up both private signing keys.
- Recovery when a feed is bad: revert the feed commit; immutable artifacts remain available but undiscoverable.
- Recovery when an artifact is bad: publish a higher build version; never mutate a released asset behind an existing signed feed entry.

## Acceptance Criteria

The feature is complete only when all of the following are demonstrated:

1. A manually migrated Mac build finds, EdDSA-verifies, downloads, and installs a later ad-hoc build from the published appcast.
2. Android automatically discovers a greater `versionCode`, downloads it, verifies hash/package/version/certificate, and reaches the system replacement confirmation without uninstalling the current app.
3. A tampered Mac archive and a tampered or differently signed Android APK are rejected.
4. Offline or malformed feeds do not interrupt display streaming.
5. Missing Apple Developer credentials do not block Mac or Android publication.
6. Existing OpenDisplay iOS connects using the unchanged discovery and video protocol.
7. Repository tests, Mac and iOS builds, Android tests/build, signing checks, feed validation, and artifact checksum checks all pass from a clean release run.
