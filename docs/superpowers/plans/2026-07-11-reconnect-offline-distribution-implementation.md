# DisplayWeave Reconnect and Offline Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate duplicate ADB sessions for one physical Android, restore Android streaming automatically after foreground/lifecycle changes, and produce honestly labeled offline-signed Android, ad-hoc Mac, and user-resignable iOS Preview artifacts.

**Architecture:** Classify `adb devices -l` rows by connection kind and allow only physical USB rows into `AdbUsbTransport`; keep App WiFi discovery independent. Add a pure Java lifecycle coordinator so Activity resume/surface events start exactly one Receiver server. Package Android with a repository-external keystore, keep Mac ad-hoc, and create an unsigned `iphoneos` payload explicitly intended for user re-signing.

**Tech Stack:** Swift 5.9 standalone self-tests, SwiftUI, Network.framework, Java 17 plain self-tests, Android Gradle Plugin, ADB, keytool, macOS Keychain CLI, Xcode/xcodebuild, codesign, apksigner.

---

## File map

- `Mac/AndroidAdb.swift`: parse ADB connection metadata and expose USB-only selection policy.
- `MacTests/AndroidAdbSelfTest.swift`: parser, USB filtering, wireless-debugging presentation regressions.
- `Mac/OpenSidecarMacApp.swift`: consume USB-only devices and prevent wireless ADB from creating sessions.
- `AndroidReceiver/app/src/main/java/app/opendisplay/android/ReceiverLifecycleCoordinator.java`: pure lifecycle state and callbacks.
- `AndroidReceiver/app/src/main/java/app/opendisplay/android/MainActivity.java`: delegate resume/surface/destroy events to the coordinator.
- `AndroidReceiver/tests/java/app/opendisplay/android/ReceiverLifecycleSelfTest.java`: event-order and idempotency tests.
- `AndroidReceiver/app/build.gradle.kts`: register the lifecycle self-test and retain environment-based release signing.
- `tools/create-android-preview-keystore.sh`: create the repository-external signing identity and store its password in Keychain.
- `tools/package-preview-0.1.sh`: load signing secrets, build verified APK, package Mac and unsigned iOS device input.
- `.gitignore`: exclude any local release environment files and generated Preview products.
- `docs/release-checklist.md`: record actual signature, install, reconnect, concurrency, and remaining manual gates.
- `docs/release-notes-preview-0.1.md`: state exact Android/Mac/iOS distribution limits.
- `docs/stability-test-report.md`: record foreground, app restart, cable, authorization, ADB restart, and concurrency evidence.
- `docs/usb-vs-wifi-benchmark.md`: align future measurement sequence and scenarios with the uploaded optimization plan.

### Task 1: Classify ADB USB and wireless-debugging endpoints

**Files:**
- Modify: `Mac/AndroidAdb.swift:1-85`
- Modify: `MacTests/AndroidAdbSelfTest.swift:15-145`

- [ ] **Step 1: Write the failing parser and selection tests**

Add a fixture containing the same Android over USB and wireless debugging:

```swift
let dualEndpointOutput = """
List of devices attached
HA2AE8R5 device usb:1-2 product:OPD2413 model:OPD2413 device:OP615EL1 transport_id:639
adb-HA2AE8R5-C1o9Bn._adb-tls-connect._tcp device product:OPD2413 model:OPD2413 device:OP615EL1 transport_id:2
"""
let dualEndpoints = AndroidAdbDeviceList.parse(dualEndpointOutput)
expect(dualEndpoints.map(\.connectionKind) == [.usb, .wirelessDebugging],
       "ADB rows must preserve their physical connection kind")
expect(AndroidAdbDeviceSelection.usbDevices(from: dualEndpoints).map(\.serial) == ["HA2AE8R5"],
       "wireless debugging must never create a second AdbUsbTransport session")
```

Also assert that two rows containing different `usb:` fields both remain connectable, and that unauthorized USB rows remain visible for guidance.

- [ ] **Step 2: Run the self-test and verify RED**

Run:

```bash
swiftc -module-cache-path /private/tmp/displayweave-swift-module-cache \
  Mac/AndroidAdb.swift MacTests/AndroidAdbSelfTest.swift \
  -o /private/tmp/AndroidAdbSelfTest && /private/tmp/AndroidAdbSelfTest
```

Expected: compile failure because `connectionKind` and `AndroidAdbDeviceSelection` do not exist.

- [ ] **Step 3: Implement connection metadata and USB selection**

Add:

```swift
enum AndroidAdbConnectionKind: Equatable, Sendable {
    case usb
    case wirelessDebugging
    case unknown
}

struct AndroidAdbDevice: Equatable, Identifiable, Sendable {
    let serial: String
    let state: AndroidAdbState
    let model: String?
    let connectionKind: AndroidAdbConnectionKind
    let product: String?
    let device: String?
    var id: String { serial }
}

enum AndroidAdbDeviceSelection {
    static func usbDevices(from devices: [AndroidAdbDevice]) -> [AndroidAdbDevice] {
        devices.filter { $0.connectionKind == .usb }
    }
}
```

Classify a row as `.usb` when metadata contains `usb`; classify serials containing `._adb-tls-connect._tcp` as `.wirelessDebugging`; otherwise `.unknown`. Preserve `product`, `model`, and `device` fields.

- [ ] **Step 4: Run the self-test and verify GREEN**

Run the Step 2 command. Expected: `AndroidAdbSelfTest PASS`.

- [ ] **Step 5: Commit**

```bash
git add Mac/AndroidAdb.swift MacTests/AndroidAdbSelfTest.swift
git commit -m "fix: distinguish wired and wireless adb devices"
```

### Task 2: Restrict AdbUsbTransport to wired devices

**Files:**
- Modify: `Mac/OpenSidecarMacApp.swift:260-430,730-825`
- Modify: `MacTests/AndroidAdbSelfTest.swift`

- [ ] **Step 1: Add failing presentation-policy tests**

Add tests proving a wireless-only ADB endpoint is non-connectable and clearly labeled, while an unauthorized wired endpoint still yields the authorization message:

```swift
let wirelessOnly = AndroidAdbPresentation.make(
    executableFound: true,
    devices: [AndroidAdbDevice(serial: "adb-X._adb-tls-connect._tcp",
                               state: .device, model: "Tablet",
                               connectionKind: .wirelessDebugging,
                               product: nil, device: nil)])
expect(wirelessOnly.connectableSerials.isEmpty,
       "wireless debugging is not DisplayWeave USB transport")
expect(wirelessOnly.message.contains("无线调试"),
       "wireless-only discovery must explain why USB is unavailable")
```

- [ ] **Step 2: Run test and verify RED**

Run the Task 1 self-test command. Expected: assertion failure because presentation still treats every ready ADB row as USB.

- [ ] **Step 3: Apply USB-only policy at both boundaries**

In `AndroidAdbPresentation.make`, derive ready and error states from wired rows. If there are no wired rows but wireless rows exist, return `已检测到 Android 无线调试；请连接 USB 数据线以使用 USB 传输`.

In `SenderController.scanAndroidAdb`, store parsed rows for diagnostics but derive an `androidUsbDevices` computed property using `AndroidAdbDeviceSelection.usbDevices`. Use that property in:

- automatic connection loops;
- `deviceEntries` USB rows;
- `connectAndroidAdb` target lookup;
- recovery readiness checks;
- connectability booleans.

Do not create `ConnectionTarget.androidAdbDevice` for `.wirelessDebugging` or `.unknown` rows.

- [ ] **Step 4: Run self-test and macOS build**

Run:

```bash
/private/tmp/AndroidAdbSelfTest
./generate.sh
xcodebuild -quiet -project OpenSidecar.xcodeproj -scheme OpenSidecarMac \
  -configuration Debug -derivedDataPath build-run \
  -clonedSourcePackagesDirPath build-run/SourcePackages build
```

Expected: self-test PASS and xcodebuild exit 0.

- [ ] **Step 5: Commit**

```bash
git add Mac/OpenSidecarMacApp.swift Mac/AndroidAdb.swift MacTests/AndroidAdbSelfTest.swift
git commit -m "fix: prevent duplicate wireless adb sessions"
```

### Task 3: Make Android Receiver lifecycle restart idempotent

**Files:**
- Create: `AndroidReceiver/app/src/main/java/app/opendisplay/android/ReceiverLifecycleCoordinator.java`
- Create: `AndroidReceiver/tests/java/app/opendisplay/android/ReceiverLifecycleSelfTest.java`
- Modify: `AndroidReceiver/app/src/main/java/app/opendisplay/android/MainActivity.java:45-95,185-215,365-390`
- Modify: `AndroidReceiver/app/build.gradle.kts:65-90`

- [ ] **Step 1: Write the failing lifecycle self-test**

Create a fake action recorder and assert these sequences:

```java
ReceiverLifecycleCoordinator coordinator = new ReceiverLifecycleCoordinator(actions);
coordinator.onResume();
coordinator.onSurfaceCreated();
coordinator.onResume();
require(actions.starts == 1, "resume and surface events start exactly one server");
coordinator.onSurfaceDestroyed();
require(actions.stops == 1, "surface loss stops the current server exactly once");
coordinator.onSurfaceCreated();
require(actions.starts == 2, "a recreated foreground surface restarts the server");
coordinator.onDestroy();
coordinator.onDestroy();
require(actions.stops == 2, "destroy cleanup is idempotent");
```

Also verify `onPause` does not stop an otherwise valid server.

- [ ] **Step 2: Register and run the new self-test to verify RED**

Register `runReceiverLifecycleSelfTest` using the existing `registerSelfTest` helper and make `test` depend on it.

Run:

```bash
cd AndroidReceiver
./gradlew runReceiverLifecycleSelfTest
```

Expected: Java compilation failure because the coordinator is missing.

- [ ] **Step 3: Implement the pure coordinator**

Use this interface and state boundary:

```java
final class ReceiverLifecycleCoordinator {
    interface Actions { void start(); void stop(); }
    private final Actions actions;
    private boolean resumed;
    private boolean surfaceAvailable;
    private boolean running;

    void onResume() { resumed = true; ensureStarted(); }
    void onPause() { resumed = false; }
    void onSurfaceCreated() { surfaceAvailable = true; ensureStarted(); }
    void onSurfaceDestroyed() { surfaceAvailable = false; stopIfRunning(); }
    void onDestroy() { resumed = false; surfaceAvailable = false; stopIfRunning(); }
}
```

`ensureStarted` starts only when `resumed && surfaceAvailable && !running`. `stopIfRunning` calls `actions.stop()` once and clears `running`.

- [ ] **Step 4: Integrate MainActivity**

Create the coordinator after `buildUi`. Its `start` callback calls a renamed `startServer()` that requires `activeSurface != null`; its `stop` callback calls `stopServer()` and clears `server`.

Route Activity and Surface callbacks:

```java
@Override protected void onResume() {
    super.onResume();
    receiverLifecycle.onResume();
}
@Override protected void onPause() {
    receiverLifecycle.onPause();
    super.onPause();
}
```

Call `onSurfaceCreated`, `onSurfaceDestroyed`, and `onDestroy` on the coordinator. Permission grant calls `receiverLifecycle.onResume()` only to re-evaluate the start preconditions; coordinator idempotency prevents duplicates.

- [ ] **Step 5: Run Android tests and build**

Run:

```bash
cd AndroidReceiver
./gradlew clean test assembleDebug assembleRelease
```

Expected: `ProtocolSelfTest PASS`, `VideoStreamPolicySelfTest PASS`, `ReceiverLifecycleSelfTest PASS`, and `BUILD SUCCESSFUL`.

- [ ] **Step 6: Commit**

```bash
git add AndroidReceiver/app/src/main/java/app/opendisplay/android/MainActivity.java \
  AndroidReceiver/app/src/main/java/app/opendisplay/android/ReceiverLifecycleCoordinator.java \
  AndroidReceiver/tests/java/app/opendisplay/android/ReceiverLifecycleSelfTest.java \
  AndroidReceiver/app/build.gradle.kts
git commit -m "fix: restart Android receiver on foreground surface"
```

### Task 4: Verify Android foreground and ADB recovery on the real device

**Files:**
- Modify: `docs/stability-test-report.md`
- Modify: `docs/release-checklist.md`

- [ ] **Step 1: Install the new debug APK and establish one USB session**

Run:

```bash
WIRED_SERIAL="$(adb devices -l | awk '$2 == "device" && $0 ~ / usb:/ { print $1; exit }')"
test -n "$WIRED_SERIAL"
adb -s "$WIRED_SERIAL" install -r AndroidReceiver/app/build/outputs/apk/debug/app-debug.apk
adb devices -l
adb forward --list
```

Expected: both raw USB/wireless-debugging rows may exist in ADB, but DisplayWeave creates one Sender and one owned forward for the wired serial.

- [ ] **Step 2: Execute foreground recovery**

While streaming, run `adb -s "$WIRED_SERIAL" shell input keyevent KEYCODE_HOME`, wait 10 seconds, then run `adb -s "$WIRED_SERIAL" shell am start -n app.opendisplay.android/.MainActivity`.

Expected: picture returns without changing mirror/extend; Mac logs one reconnect, a new hello, streamConfig, and keyframe, with no repeating peer-reset loop.

- [ ] **Step 3: Execute App close/reopen**

Force-stop the Receiver, confirm the Mac shows recovery status, then launch it again inside the bounded recovery window. Expected: stream resumes without a mode toggle.

- [ ] **Step 4: Execute cable, authorization, and ADB daemon cases**

Perform each independently, preserving logs:

- unplug/replug USB;
- revoke USB debugging authorization and re-authorize;
- `adb kill-server`, followed by a normal ADB command that restarts it;
- Auto mode with same-install-ID WiFi Receiver available, then USB recovery exhaustion.

Expected: finite retries, actionable status, exact mapping cleanup, and same-device-only WiFi fallback.

- [ ] **Step 5: Record only observed results and commit**

```bash
git add docs/stability-test-report.md docs/release-checklist.md
git commit -m "test: verify Android foreground and adb recovery"
```

### Task 5: Create a permanent offline Android signing identity

**Files:**
- Create: `tools/create-android-preview-keystore.sh`
- Modify: `.gitignore`
- Modify: `docs/release-checklist.md`

- [ ] **Step 1: Add script syntax and safety checks**

The script must:

- refuse to overwrite an existing keystore;
- create `~/Library/Application Support/DisplayWeave/Signing` with mode 700;
- generate a random password without echoing it;
- invoke `keytool` using environment-backed password options rather than literal password command arguments;
- create alias `displayweave-preview` with a long validity and non-personal certificate subject such as `CN=DisplayWeave Preview, O=DisplayWeave`;
- store the password in Keychain service `app.displayweave.android-preview-signing`, account `displayweave-preview`;
- set keystore mode 600 and print the certificate SHA-256, never the password.

Use this keytool pattern:

```bash
DISPLAYWEAVE_KEYSTORE_PASSWORD="$password" keytool -genkeypair \
  -keystore "$keystore" -storepass:env DISPLAYWEAVE_KEYSTORE_PASSWORD \
  -keypass:env DISPLAYWEAVE_KEYSTORE_PASSWORD -alias displayweave-preview \
  -keyalg RSA -keysize 4096 -validity 9125 \
  -dname "CN=DisplayWeave Preview, O=DisplayWeave"
```

- [ ] **Step 2: Verify shell syntax before execution**

Run `bash -n tools/create-android-preview-keystore.sh`. Expected: exit 0.

- [ ] **Step 3: Execute once with explicit user approval**

Run `./tools/create-android-preview-keystore.sh`. Expected: repository-external JKS exists, Keychain item exists, and `keytool -list -v` prints the certificate without exposing the password.

- [ ] **Step 4: Document backup responsibility and commit**

Add the exact keystore location, alias, certificate SHA-256, and offline-backup warning to the release checklist; do not record passwords.

```bash
git add .gitignore tools/create-android-preview-keystore.sh docs/release-checklist.md
git commit -m "build: add offline Android release identity setup"
```

### Task 6: Package and verify Android, Mac, and iOS Preview artifacts

**Files:**
- Modify: `tools/package-preview-0.1.sh`
- Modify: `docs/release-checklist.md`
- Modify: `docs/release-notes-preview-0.1.md`

- [ ] **Step 1: Load Android signing data from repository-external state**

Resolve the fixed JKS path and retrieve the password with:

```bash
password="$(security find-generic-password \
  -s app.displayweave.android-preview-signing \
  -a displayweave-preview -w)"
```

Export the four existing Gradle variables only for the Gradle process. Unset the password after the build.

- [ ] **Step 2: Add unsigned iOS device resigning input**

Build with `-sdk iphoneos CODE_SIGNING_ALLOWED=NO`, stage `Payload/DisplayWeave.app`, and create:

`DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa`

Verify that the app executable is a device architecture with `lipo -info`, that no `_CodeSignature` directory is present, and that Info.plist has the expected bundle identifier. Never label it directly installable.

- [ ] **Step 3: Keep Mac preview checks**

Build Release 0.1 with the ad-hoc entitlement and `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`. Verify with `codesign --verify --deep --strict`; include the unnotarized warning in release notes.

- [ ] **Step 4: Build and verify Android release**

Run `clean test assembleRelease`, require `app-release.apk`, and execute:

```bash
apksigner verify --verbose --print-certs app-release.apk
WIRED_SERIAL="$(adb devices -l | awk '$2 == "device" && $0 ~ / usb:/ { print $1; exit }')"
test -n "$WIRED_SERIAL"
adb -s "$WIRED_SERIAL" install -r app-release.apk
```

Expected: v2/v3 signature verification succeeds, the printed certificate digest matches the recorded identity, and install/launch succeeds.

- [ ] **Step 5: Generate hashes and run the package script end-to-end**

`SHA256SUMS.txt` must include the signed APK, Mac ZIP, Simulator ZIP if retained, and unsigned iOS resigning input. Run the package script from a clean artifact directory and verify each listed hash.

- [ ] **Step 6: Commit**

```bash
git add tools/package-preview-0.1.sh docs/release-checklist.md docs/release-notes-preview-0.1.md
git commit -m "release: package offline-signed Preview artifacts"
```

### Task 7: Verify Android and iPhone concurrency

**Files:**
- Modify: `docs/stability-test-report.md`
- Modify: `docs/release-checklist.md`

- [ ] **Step 1: Establish two independent sessions**

Connect Android through wired ADB and iPhone through Apple USB. Record session IDs, VirtualDisplay IDs, codec, requested/actual refresh, and transport.

- [ ] **Step 2: Exercise isolation**

Send Android Home/foreground and cable-replug events while the iPhone stream remains active; disconnect/reconnect iPhone while Android remains active. Repeat with iPhone WiFi if discoverable.

Expected: one device's lifecycle events do not end, rebuild, or alter the other device's session.

- [ ] **Step 3: Record scope accurately and commit**

Mark Android+iPhone concurrency according to direct evidence. Keep “two Android USB devices” pending.

```bash
git add docs/stability-test-report.md docs/release-checklist.md
git commit -m "test: verify Android and iPhone concurrency"
```

### Task 8: Align the performance audit and Benchmark with the uploaded plan

**Files:**
- Modify: `docs/usb-vs-wifi-benchmark.md`
- Create: `docs/performance-metrics-audit.md`
- Modify: `docs/release-notes-preview-0.1.md`

- [ ] **Step 1: Audit every requested metric end-to-end**

For Capture/Encode/Sent/Received/Decoded/Rendered FPS, bitrate, encode/decode latency, Frame Age, queue depth, drops, RTT, CPU, and memory, record:

- producer file/type;
- wire field if transmitted;
- Android overlay/log consumer;
- sampling interval and units;
- whether exportable as a time series;
- verified, implemented-but-unverified, or missing.

- [ ] **Step 2: Define fixed scenarios and raw data format**

Use desktop dynamic test content, browser scroll, YouTube 4K60, and high-motion/game content. Define CSV columns with monotonic timestamp, transport, codec, resolution, requested/actual FPS, bitrate, all latency/queue/drop metrics, CPU, and memory.

- [ ] **Step 3: Define the ordered experiment matrix**

Keep the RTF order: metric completeness, Frame Age, Manual bitrate, high-bitrate staircase, adaptive bitrate, USB mode, queue 1/2/3, keyframe interval, WiFi Benchmark, USB Benchmark. Do not implement a later optimization before its input metrics are verified.

- [ ] **Step 4: Preserve unexecuted status honestly and commit**

Do not fill 30-minute, 2-hour, or paired USB/WiFi results. Note that the maintainer owns those long-duration runs.

```bash
git add docs/performance-metrics-audit.md docs/usb-vs-wifi-benchmark.md \
  docs/release-notes-preview-0.1.md
git commit -m "docs: define evidence-first performance benchmark"
```

### Task 9: Final regression and evidence audit

**Files:**
- Modify only if evidence finds an error: `docs/release-checklist.md`, `docs/stability-test-report.md`, `docs/release-notes-preview-0.1.md`

- [ ] **Step 1: Run all seven Swift self-tests**

Compile and run RefreshRatePolicy, StreamEncodingPolicy, StreamSettings, DeviceCapabilities, AndroidAdb, AndroidAdbForward, and TransportSelectionPolicy tests. Expected: seven PASS lines.

- [ ] **Step 2: Run clean builds**

Run macOS Debug and Release xcodebuild, iOS Simulator and unsigned iphoneos builds, Android `clean test assembleRelease`, and website `pnpm build`. Expected: all exit 0.

- [ ] **Step 3: Verify artifact identities**

- APK: `apksigner verify --verbose --print-certs` succeeds and digest matches checklist.
- Mac: `codesign --verify --deep --strict` succeeds; signature remains ad-hoc and unnotarized.
- iOS resigning input: unsigned device Mach-O is present and documentation says re-signing is mandatory.
- SHA-256: recompute every published file and compare with `SHA256SUMS.txt`.

- [ ] **Step 4: Audit every approved-spec completion criterion**

Mark each item proven, pending, or blocked using direct command/log/artifact evidence. Specifically keep 30-minute, 2-hour, and two-Android tests pending unless the maintainer later supplies results.

- [ ] **Step 5: Run repository hygiene checks and commit any evidence corrections**

Run:

```bash
git diff --check
git status --short --branch
```

Expected: no whitespace errors and no unexplained files.
