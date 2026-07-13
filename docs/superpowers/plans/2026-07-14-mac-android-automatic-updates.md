# Mac and Android Automatic Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a GitHub Releases-backed automatic update channel for the ad-hoc-signed Mac app and the signed Android APK without changing the protocol used by the existing OpenDisplay iOS receiver.

**Architecture:** Sparkle remains the sole Mac update engine and consumes an EdDSA-signed Pages appcast. Android gains isolated metadata, policy, download, verification, provider, installer, and coordinator units that consume a static Pages JSON feed and hand the verified APK to the system installer. A single release workflow injects monotonic versions, uploads immutable artifacts, validates them, and publishes both feeds only after every artifact is available.

**Tech Stack:** Swift 5.9, Sparkle 2.9.x, Java 17, Android SDK 36/minSdk 26, Gradle 8.11.1, Bash, GitHub Actions, GitHub Releases, GitHub Pages.

## Global Constraints

- No Apple Developer Program membership, Developer ID, notarization, or TestFlight credential may be required for Mac/Android publication.
- Mac update archives must be Sparkle EdDSA signed and ad-hoc code signed with `Mac/OpenSidecarMacAdHoc.entitlements`.
- Android update eligibility is `remoteVersionCode > installedVersionCode` and every update must use the existing JKS signer fingerprint `89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d`.
- Android installation always goes through the system confirmation UI; no silent-install claim is permitted.
- `_opensidecar._tcp`, TCP port `9000`, the four-byte big-endian framing, Annex B H.264, and legacy hello defaults remain unchanged.
- Secrets and private keys must never be committed or printed.
- Existing user changes in `Mac/TestPatternWindow.swift` and `MacTests/MetalRenderPassOrderingSelfTest.swift` are preserved and committed separately from update work.

---

## File Structure

### macOS and compatibility

- Modify `project.yml`: Sparkle public key, Pages feed, automatic-check/install keys.
- Modify `MacTests/ApplicationIdentityPolicySelfTest.swift`: generated-update configuration assertions remain independent from runtime identity migration.
- Modify `MacTests/DeviceCapabilitiesSelfTest.swift`: explicit legacy iOS hello compatibility fixture.
- Create `MacTests/UpdateConfigurationSelfTest.swift`: source-of-truth update setting validation.

### Android client

- Create `AndroidReceiver/app/src/main/java/app/opendisplay/android/update/UpdateManifest.java`: immutable metadata parser/validator.
- Create `AndroidReceiver/app/src/main/java/app/opendisplay/android/update/UpdatePolicy.java`: pure eligibility and throttle decisions.
- Create `AndroidReceiver/app/src/main/java/app/opendisplay/android/update/UpdateClient.java`: bounded HTTPS fetch/download.
- Create `AndroidReceiver/app/src/main/java/app/opendisplay/android/update/UpdateVerifier.java`: size/hash/package/version/certificate checks.
- Create `AndroidReceiver/app/src/main/java/app/opendisplay/android/update/UpdateFileProvider.java`: read-only verified APK content URI.
- Create `AndroidReceiver/app/src/main/java/app/opendisplay/android/update/UpdateInstaller.java`: unknown-source permission and package-installer launch.
- Create `AndroidReceiver/app/src/main/java/app/opendisplay/android/update/UpdateCoordinator.java`: activity-facing orchestration.
- Modify `AndroidReceiver/app/src/main/java/app/opendisplay/android/MainActivity.java`: lifecycle and update UI only.
- Modify `AndroidReceiver/app/src/main/AndroidManifest.xml`: install permission/provider.
- Modify `AndroidReceiver/app/build.gradle.kts`: injected versions and update self-tests.

### Tests and release automation

- Create `AndroidReceiver/tests/java/app/opendisplay/android/update/UpdatePolicySelfTest.java`.
- Create `AndroidReceiver/tests/java/app/opendisplay/android/update/UpdateVerifierSelfTest.java`.
- Create `tools/generate-android-update-manifest.sh`: deterministic metadata generation.
- Create `tools/verify-update-release.sh`: feed/artifact/version/hash/fingerprint validation.
- Modify `tools/package-preview-0.1.sh`: accept injected version/output inputs while keeping local defaults.
- Replace Mac/Android portions of `.github/workflows/release.yml`: credential-independent update publication.
- Create `docs/automatic-updates.md` and `docs/automatic-updates.zh-CN.md`: migration, permissions, key backup, and recovery.

---

### Task 1: Preserve the completed black-screen fix

**Files:**
- Modify: `Mac/TestPatternWindow.swift`
- Create: `MacTests/MetalRenderPassOrderingSelfTest.swift`

**Interfaces:**
- Consumes: existing Metal test-pattern renderer.
- Produces: a separately committed fix and source-order regression test, leaving the update commits scoped.

- [ ] **Step 1: Re-run the existing regression test**

Run:

```bash
swiftc -parse-as-library -module-cache-path /tmp/displayweave-metal-order-module-cache MacTests/MetalRenderPassOrderingSelfTest.swift -o /tmp/MetalRenderPassOrderingSelfTest
/tmp/MetalRenderPassOrderingSelfTest
```

Expected: `MetalRenderPassOrderingSelfTest PASS (2 encoders checked)`.

- [ ] **Step 2: Re-run the Mac build**

Run:

```bash
xcodebuild -project OpenSidecar.xcodeproj -scheme OpenSidecarMac -configuration Debug -derivedDataPath /tmp/displayweave-black-screen-plan-derived CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit only the black-screen files**

```bash
git add Mac/TestPatternWindow.swift MacTests/MetalRenderPassOrderingSelfTest.swift
git commit -m "fix: configure test pattern before encoding"
```

### Task 2: Lock Mac update configuration and legacy iOS compatibility

**Files:**
- Create: `MacTests/UpdateConfigurationSelfTest.swift`
- Modify: `MacTests/DeviceCapabilitiesSelfTest.swift`
- Modify: `project.yml`

**Interfaces:**
- Consumes: repository root as current directory and `PhoneInfo` legacy defaults.
- Produces: `SUPublicEDKey`, `SUFeedURL`, `SUEnableAutomaticChecks`, `SUAutomaticallyUpdate`; compatibility assertions for old iOS hello payloads.

- [ ] **Step 1: Write the failing Mac update configuration self-test**

Create a test that reads `project.yml` and requires these exact settings:

```swift
import Foundation

@main
enum UpdateConfigurationSelfTest {
    static func main() throws {
        let source = try String(contentsOfFile: "project.yml", encoding: .utf8)
        precondition(source.contains("SUFeedURL: https://chenyuhao0628.github.io/displayweave/appcast.xml"))
        precondition(source.contains("SUEnableAutomaticChecks: true"))
        precondition(source.contains("SUAutomaticallyUpdate: true"))
        let marker = "SUPublicEDKey: "
        guard let range = source.range(of: marker) else { preconditionFailure("missing SUPublicEDKey") }
        let key = source[range.upperBound...].prefix { !$0.isNewline }
        precondition(Data(base64Encoded: String(key))?.count == 32, "public key must be 32 bytes")
        precondition(String(key) != "rYxlIePmwzi2bRo/qIsuY2TqTnQ34li2gQhJpGBiumw=", "obsolete key remains")
        print("UpdateConfigurationSelfTest PASS")
    }
}
```

- [ ] **Step 2: Run it and verify RED**

```bash
swiftc -parse-as-library MacTests/UpdateConfigurationSelfTest.swift -o /tmp/UpdateConfigurationSelfTest
/tmp/UpdateConfigurationSelfTest
```

Expected: failure because the feed URL, automatic settings, and new key are absent.

- [ ] **Step 3: Add an explicit legacy iOS fixture before production changes**

Extend `DeviceCapabilitiesSelfTest` with:

```swift
let legacyIOSHello = try JSONDecoder().decode(PhoneInfo.self, from: Data("""
{"type":"hello","pixelsWide":1320,"pixelsHigh":2868,"scale":3.0,"device":"iPhone"}
""".utf8))
assertEqual("iPhone", legacyIOSHello.kind, "legacy iOS device kind is retained")
assertEqual(60, legacyIOSHello.negotiatedMaxFps, "legacy iOS defaults to 60 fps")
assertEqual(["h264"], legacyIOSHello.negotiatedSupportedCodecs, "legacy iOS remains H.264")
assertEqual("unknown", legacyIOSHello.negotiatedTransport, "legacy iOS needs no transport field")
```

- [ ] **Step 4: Generate a new Sparkle key without exposing its private half**

Run Sparkle `generate_keys` once, save its printed public key, export the private key directly to a mode-600 temporary file, set `SPARKLE_PRIVATE_KEY` with `gh secret set --body-file`, and delete the file. Never print the export.

```bash
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x /tmp/displayweave-sparkle-private
chmod 600 /tmp/displayweave-sparkle-private
gh secret set SPARKLE_PRIVATE_KEY --repo chenyuhao0628/displayweave --body-file /tmp/displayweave-sparkle-private
```

Then remove `/tmp/displayweave-sparkle-private` with approval because it contains secret material.

- [ ] **Step 5: Implement the exact project settings**

Set the three fixed values below, then set `SUPublicEDKey` to the exact single-line output of `generate_keys -p` captured immediately after Step 4:

```yaml
SUFeedURL: https://chenyuhao0628.github.io/displayweave/appcast.xml
SUEnableAutomaticChecks: true
SUAutomaticallyUpdate: true
```

- [ ] **Step 6: Verify GREEN and compatibility**

Compile/run both Swift self-tests and run `./generate.sh`. Expected: both print `PASS`, and generated plist contains the same four values.

- [ ] **Step 7: Commit**

```bash
git add project.yml MacTests/UpdateConfigurationSelfTest.swift MacTests/DeviceCapabilitiesSelfTest.swift
git commit -m "feat: enable signed mac update checks"
```

### Task 3: Implement Android metadata and update policy with TDD

**Files:**
- Create: `AndroidReceiver/tests/java/app/opendisplay/android/update/UpdatePolicySelfTest.java`
- Create: `AndroidReceiver/app/src/main/java/app/opendisplay/android/update/UpdateManifest.java`
- Create: `AndroidReceiver/app/src/main/java/app/opendisplay/android/update/UpdatePolicy.java`
- Modify: `AndroidReceiver/app/build.gradle.kts`

**Interfaces:**
- Produces: `UpdateManifest.parse(String)`, `UpdatePolicy.isNewer(long,long)`, `UpdatePolicy.shouldCheck(long,long,boolean)`, `UpdatePolicy.normalizeHex(String)`.
- Consumes: JSON schema version 1 and a 24-hour check interval.

- [ ] **Step 1: Write the failing pure Java test**

The test must assert:

```java
UpdateManifest manifest = UpdateManifest.parse(validJson);
expect(manifest.versionCode == 123, "version code parsed");
expect(UpdatePolicy.isNewer(123, 122), "greater version is newer");
expect(!UpdatePolicy.isNewer(123, 123), "equal version is not newer");
expect(UpdatePolicy.shouldCheck(86_400_001L, 1L, false), "daily boundary elapsed");
expect(!UpdatePolicy.shouldCheck(86_400_000L, 1L, false), "one millisecond remains");
expect(UpdatePolicy.shouldCheck(2L, 1L, true), "manual bypasses throttle");
expectThrows(() -> UpdateManifest.parse(httpUrlJson), "non-HTTPS APK URL rejected");
expectThrows(() -> UpdateManifest.parse(wrongPackageJson), "wrong package rejected");
expectThrows(() -> UpdateManifest.parse(badHashJson), "bad hash rejected");
```

- [ ] **Step 2: Register and run the test to verify RED**

Add `runUpdatePolicySelfTest` using the existing `registerSelfTest` helper and make `test` depend on it.

Run:

```bash
ANDROID_HOME=/Users/cyh/Library/Android/sdk ./gradlew runUpdatePolicySelfTest
```

Expected: compile failure because `UpdateManifest` and `UpdatePolicy` do not exist.

- [ ] **Step 3: Implement immutable manifest parsing**

`UpdateManifest.parse` must validate all schema fields, require `schemaVersion == 1`, exact package name, positive versions/size, `minimumSdk >= 26`, HTTPS GitHub artifact URL, HTTPS release notes URL, 64-character lowercase SHA-256 values, and ISO-8601 `publishedAt` text.

- [ ] **Step 4: Implement pure policy functions**

Use:

```java
public static final long CHECK_INTERVAL_MS = 24L * 60L * 60L * 1000L;
public static boolean isNewer(long remote, long installed) { return remote > installed; }
public static boolean shouldCheck(long now, long lastSuccess, boolean manual) {
    return manual || lastSuccess <= 0 || now - lastSuccess >= CHECK_INTERVAL_MS;
}
```

- [ ] **Step 5: Run GREEN and all Android tests**

Run `./gradlew runUpdatePolicySelfTest test`; expected all registered self-tests pass.

- [ ] **Step 6: Commit**

```bash
git add AndroidReceiver/app/src/main/java/app/opendisplay/android/update/UpdateManifest.java AndroidReceiver/app/src/main/java/app/opendisplay/android/update/UpdatePolicy.java AndroidReceiver/tests/java/app/opendisplay/android/update/UpdatePolicySelfTest.java AndroidReceiver/app/build.gradle.kts
git commit -m "feat(android): add update manifest policy"
```

### Task 4: Implement Android download and verification with TDD

**Files:**
- Create: `AndroidReceiver/tests/java/app/opendisplay/android/update/UpdateVerifierSelfTest.java`
- Create: `AndroidReceiver/app/src/main/java/app/opendisplay/android/update/UpdateClient.java`
- Create: `AndroidReceiver/app/src/main/java/app/opendisplay/android/update/UpdateVerifier.java`
- Modify: `AndroidReceiver/app/build.gradle.kts`

**Interfaces:**
- Produces: `UpdateClient.fetchManifest(URL)`, `UpdateClient.download(URL,File,long,Progress)`, `UpdateVerifier.sha256(File)`, `UpdateVerifier.verifyFile(File,UpdateManifest)`, and an Android `verifyPackage(Context,File,UpdateManifest)` layer.

- [ ] **Step 1: Write the failing verifier test**

Create a temporary file containing `DisplayWeave update fixture\n`, assert its exact computed SHA-256, exact-size success, wrong-size failure, wrong-hash failure, and deletion policy for failed files.

- [ ] **Step 2: Register/run RED**

Run `./gradlew runUpdateVerifierSelfTest`; expected compile failure because the verifier does not exist.

- [ ] **Step 3: Implement bounded HTTPS client**

Require HTTPS, `setConnectTimeout(10_000)`, `setReadTimeout(30_000)`, no redirects to non-HTTPS, a 1 MiB metadata cap, a download cap equal to `apkSize`, and fsync before returning. Download into `DisplayWeave-update.apk.part` only.

- [ ] **Step 4: Implement two-stage verifier**

Pure file checks compare exact byte count and constant-time normalized SHA-256. Android package checks use `PackageManager.getPackageArchiveInfo(..., GET_SIGNING_CERTIFICATES)`, require package `app.opendisplay.android`, exact remote version code, compatible minimum SDK, and signer certificate SHA-256 equal to the pinned manifest fingerprint.

- [ ] **Step 5: Run GREEN and full Android tests**

Run `./gradlew runUpdateVerifierSelfTest test`; expected all tests pass.

- [ ] **Step 6: Commit**

```bash
git add AndroidReceiver/app/src/main/java/app/opendisplay/android/update/UpdateClient.java AndroidReceiver/app/src/main/java/app/opendisplay/android/update/UpdateVerifier.java AndroidReceiver/tests/java/app/opendisplay/android/update/UpdateVerifierSelfTest.java AndroidReceiver/app/build.gradle.kts
git commit -m "feat(android): securely download and verify updates"
```

### Task 5: Integrate Android update UX and system installer

**Files:**
- Create: `AndroidReceiver/app/src/main/java/app/opendisplay/android/update/UpdateFileProvider.java`
- Create: `AndroidReceiver/app/src/main/java/app/opendisplay/android/update/UpdateInstaller.java`
- Create: `AndroidReceiver/app/src/main/java/app/opendisplay/android/update/UpdateCoordinator.java`
- Modify: `AndroidReceiver/app/src/main/java/app/opendisplay/android/MainActivity.java`
- Modify: `AndroidReceiver/app/src/main/AndroidManifest.xml`

**Interfaces:**
- `UpdateCoordinator.Listener`: `onCheckState(String)`, `onUpdateAvailable(UpdateManifest)`, `onDownloadProgress(int)`, `onVerifiedUpdateReady(UpdateManifest)`, `onUpdateError(String,boolean)`.
- `UpdateCoordinator.check(boolean manual)`, `download(UpdateManifest)`, `resumePendingInstall()`.
- Provider authority: `app.opendisplay.android.update-files`.

- [ ] **Step 1: Add a failing manifest/provider policy test**

Extend the update self-test to read the manifest and assert `REQUEST_INSTALL_PACKAGES`, non-exported provider, exact authority, and `grantUriPermissions=true`. Run and verify failure.

- [ ] **Step 2: Implement the read-only provider**

Accept only the exact `/DisplayWeave-update.apk` URI, return MIME `application/vnd.android.package-archive`, reject every write mode, canonicalize and confirm the file is inside `getExternalFilesDir(DIRECTORY_DOWNLOADS)/updates`, and implement only `query`, `getType`, and `openFile`.

- [ ] **Step 3: Implement installer routing**

On API 26+, check `canRequestPackageInstalls()`. If false, launch `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES` for `package:app.opendisplay.android`. Otherwise launch `ACTION_INSTALL_PACKAGE` with the provider URI and `FLAG_GRANT_READ_URI_PERMISSION`.

- [ ] **Step 4: Implement coordinator lifecycle**

Use one executor, persist last successful check in existing `SharedPreferences`, retain verified pending manifest/file across the unknown-sources settings round trip, and never start/stop `OpenDisplayServer`.

- [ ] **Step 5: Wire MainActivity**

Create coordinator after preferences, call automatic `check(false)` from `onResume`, shut it down from `onDestroy`, add installed-version/update-state text and “检查更新” to settings, show update/download confirmation dialogs, and require a user tap before installer launch.

- [ ] **Step 6: Run all Android tests and builds**

Run:

```bash
ANDROID_HOME=/Users/cyh/Library/Android/sdk ./gradlew --no-daemon clean test assembleDebug
```

Expected: all self-tests pass and `app-debug.apk` is produced.

- [ ] **Step 7: Commit**

```bash
git add AndroidReceiver/app/src/main AndroidReceiver/app/build.gradle.kts AndroidReceiver/tests/java/app/opendisplay/android/update
git commit -m "feat(android): add verified in-app updates"
```

### Task 6: Inject release versions and generate verified feeds

**Files:**
- Modify: `AndroidReceiver/app/build.gradle.kts`
- Modify: `tools/package-preview-0.1.sh`
- Create: `tools/generate-android-update-manifest.sh`
- Create: `tools/verify-update-release.sh`
- Create: `MacTests/UpdateReleasePolicySelfTest.swift`

**Interfaces:**
- Environment: `DISPLAYWEAVE_VERSION_NAME`, `DISPLAYWEAVE_BUILD_NUMBER`, `DISPLAYWEAVE_RELEASE_TAG`, `DISPLAYWEAVE_RELEASE_BASE_URL`, signing variables.
- Outputs: `DisplayWeave-macOS.zip`, `DisplayWeave-Android.apk`, `appcast.xml`, `android-update.json`, `SHA256SUMS.txt`.

- [ ] **Step 1: Write failing version-policy and feed-verifier tests**

Assert a build number of `123` appears as Mac `CFBundleVersion` and Android `versionCode`, display version appears on both, and fixture feeds with wrong size/hash/fingerprint/HTTP URL fail.

- [ ] **Step 2: Run RED**

Run the Swift policy self-test and shell verifier fixture; expect failures because injected versions and verifier do not exist.

- [ ] **Step 3: Implement Gradle version injection**

Use providers with local fallbacks:

```kotlin
versionCode = providers.environmentVariable("DISPLAYWEAVE_BUILD_NUMBER").orElse("1").get().toInt()
versionName = providers.environmentVariable("DISPLAYWEAVE_VERSION_NAME").orElse("0.1.0").get()
```

- [ ] **Step 4: Generalize packaging inputs**

Use the injected version/build values for Xcode and Gradle; keep current Preview 0.1 defaults for local callers; use stable update artifact names in the update-release output directory.

- [ ] **Step 5: Implement deterministic Android JSON generation**

Read APK size/hash and verified `apksigner` certificate digest, reject any fingerprint other than the pinned digest, and write schema version 1 JSON atomically.

- [ ] **Step 6: Implement release verifier**

Validate both archives, versions, HTTPS URLs, local artifact sizes/hashes, Android certificate, appcast EdDSA presence, and feed-to-artifact filename agreement. Exit nonzero with a specific diagnostic per mismatch.

- [ ] **Step 7: Run GREEN and package locally**

Run policy tests, full package script, feed generator with a local fixture URL, and verifier. Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add AndroidReceiver/app/build.gradle.kts tools/package-preview-0.1.sh tools/generate-android-update-manifest.sh tools/verify-update-release.sh MacTests/UpdateReleasePolicySelfTest.swift
git commit -m "build: produce verifiable update artifacts"
```

### Task 7: Replace credential-bound release jobs with unified publication

**Files:**
- Modify: `.github/workflows/release.yml`
- Modify: `.github/workflows/pages.yml` only if its path filters omit feed files.
- Modify: `tools/check-release-links.sh`

**Interfaces:**
- Consumes: five Actions secrets listed in the design and release-please `tag_name`.
- Produces: uploaded immutable assets plus committed Pages feeds.

- [ ] **Step 1: Add a failing workflow contract check**

Extend the release check to require all five secret names, ad-hoc Mac entitlement, Android signer verification, both asset uploads, both feed filenames, cleanup under `always()`, and explicit Pages dispatch. Require that `MATCH_*`, Developer ID notarization, and TestFlight are not dependencies of the Mac/Android publication job.

- [ ] **Step 2: Run RED**

Run `tools/check-release-links.sh`; expect failure against the existing workflow.

- [ ] **Step 3: Implement the unified update job**

Decode the base64 JKS to `$RUNNER_TEMP`, export signing environment variables, build/test Mac+iOS+Android, create artifacts, generate feeds with Sparkle's official tools, verify, upload, then commit feeds and dispatch Pages. Use `set -euo pipefail`, least-privilege permissions, and an `if: always()` cleanup step.

- [ ] **Step 4: Keep iOS compatibility gate independent**

Build `OpenSidecariOS` with `CODE_SIGNING_ALLOWED=NO`; do not invoke match, App Store Connect, or TestFlight in the update job.

- [ ] **Step 5: Run workflow/static checks**

Run release-link check, bilingual-doc check, and YAML parse through Ruby/Python available in the workspace. Expected: zero failures.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/release.yml .github/workflows/pages.yml tools/check-release-links.sh
git commit -m "ci: publish mac and android update feeds"
```

### Task 8: Configure secrets and document migration/recovery

**Files:**
- Create: `docs/automatic-updates.md`
- Create: `docs/automatic-updates.zh-CN.md`
- Modify: `docs/README.md`
- Modify: `docs/README.zh-CN.md`
- Modify: `docs/release-checklist.md`
- Modify: `docs/release-checklist.zh-CN.md`

**Interfaces:**
- Produces: operator runbook and configured secret names without exposing values.

- [ ] **Step 1: Configure Android secrets without printing values**

Base64 the existing JKS into a mode-600 temporary file, retrieve the existing password directly from Keychain into a shell variable, call `gh secret set` using stdin/body-file, and delete/unset all temporary material. Set alias to `displayweave-preview`.

- [ ] **Step 2: Verify secret names only**

Run `gh secret list --repo chenyuhao0628/displayweave`; expected all five names and no values.

- [ ] **Step 3: Write bilingual operations documentation**

Document the one-time Mac key migration, Gatekeeper steps, `/Applications`, Sparkle behavior, Android unknown-sources permission, system confirmation, key backup, feed rollback, immutable artifact rule, and exact release workflow invocation.

- [ ] **Step 4: Run bilingual and release checks**

Run `tools/check-bilingual-docs.sh` and `tools/check-release-links.sh`; expected pass.

- [ ] **Step 5: Commit**

```bash
git add docs/automatic-updates.md docs/automatic-updates.zh-CN.md docs/README.md docs/README.zh-CN.md docs/release-checklist.md docs/release-checklist.zh-CN.md
git commit -m "docs: explain automatic update operations"
```

### Task 9: Full verification and controlled publication dry run

**Files:**
- Verify all files above; do not add unrelated changes.

**Interfaces:**
- Produces: evidence for all seven acceptance criteria.

- [ ] **Step 1: Run every pure/self-test**

Compile/run all `MacTests/*SelfTest.swift` with their production dependencies and run Android `./gradlew test`. Expected: every test prints/pass with zero failures.

- [ ] **Step 2: Build all platforms**

Build Mac Release ad-hoc, iOS device Release unsigned, and Android signed Release. Expected: Xcode/Gradle success and correct arm64 iOS architecture.

- [ ] **Step 3: Validate security rejection paths**

Copy and alter one byte in a Mac update archive and Android APK fixture. Expected: Sparkle verification/feed validation rejects the Mac archive, and Android verifier rejects the APK before Package Installer is launched.

- [ ] **Step 4: Validate update artifacts and feeds**

Run recursive code-sign, `apksigner`, ZIP tests, SHA-256 manifest checks, and `tools/verify-update-release.sh`. Expected: all pass for unmodified artifacts.

- [ ] **Step 5: Validate legacy iOS compatibility**

Run `DeviceCapabilitiesSelfTest`, protocol self-tests, build the iOS target, and compare the update diff to confirm no `iOS/`, Bonjour, framing, or stream-protocol source changed.

- [ ] **Step 6: Execute a prerelease publication only with explicit external-release authorization**

Create or select a prerelease tag, run the workflow, confirm both Release assets and Pages feeds, install the migration Mac build then detect a higher build, and use `adb install -r`/Package Installer to confirm Android replacement retains app data.

- [ ] **Step 7: Final audit and commit any verification-only corrections**

Run `git status --short`, `git diff --check`, and requirement-by-requirement acceptance audit. Do not mark complete if published end-to-end evidence is missing.
