# Android ADB USB Transport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add multi-device Android USB streaming through `adb forward`, with Auto/USB/WiFi selection, bounded recovery, and identity-safe WiFi fallback while preserving every existing wire protocol and Apple transport.

**Architecture:** Add a testable Mac-side ADB layer whose pure value types parse devices, locate executables, allocate mappings, and decide transport policy. `AndroidAdbManager` owns subprocesses and mappings; `SenderController` consumes its published devices and creates ordinary TCP `MacSender` sessions against loopback. Recovery remains session-scoped, and only Auto mode may fall back to a Bonjour endpoint with the same Android install ID.

**Tech Stack:** Swift 5.9, Foundation `Process`, Network.framework, SwiftUI, existing standalone `swiftc` self-tests, XcodeGen/Xcode, Android Gradle tests.

---

## File structure

- Create `Mac/AndroidAdb.swift`: ADB path resolution, device-list parsing, process-runner protocol, state/error types.
- Create `Mac/AndroidAdbForward.swift`: loopback port allocation, mapping ownership, exact mapping creation/removal.
- Create `Mac/TransportSelectionPolicy.swift`: pure Auto/USB/WiFi candidate selection, recovery schedule, install-ID-safe fallback.
- Modify `Mac/StreamSettings.swift`: expose and persist Auto/USB/WiFi.
- Modify `Mac/MacSender.swift`: identify Android ADB TCP as USB and expose bounded reconnect lifecycle signals without changing framing.
- Modify `Mac/OpenSidecarMacApp.swift`: add Android ADB targets/devices/sessions, connect mappings to `MacSender`, clean mappings, recover/fallback, and render actionable state.
- Create `MacTests/AndroidAdbSelfTest.swift`: resolver, parser, command and error tests.
- Create `MacTests/AndroidAdbForwardSelfTest.swift`: unique port, mapping ownership and cleanup tests.
- Create `MacTests/TransportSelectionPolicySelfTest.swift`: mode, fallback identity and backoff tests.
- Modify `MacTests/StreamSettingsSelfTest.swift`: transport settings persistence/default tests.
- Modify `README.md`, `README.zh-CN.md`, `AndroidReceiver/README.md`: Preview usage and ADB authorization guidance after behavior is verified.

### Task 1: Add Auto/USB/WiFi settings

**Files:**
- Modify: `Mac/StreamSettings.swift:102-110`
- Modify: `MacTests/StreamSettingsSelfTest.swift`

- [ ] **Step 1: Write the failing transport-mode assertions**

Add to `StreamSettingsSelfTest.main()`:

```swift
assertTrue(StreamTransportMode.allCases.map(\.rawValue) == ["auto", "usb", "wifi"],
           "transport modes remain Auto, USB, WiFi in priority order")
assertTrue(StreamSettings.load(from: emptyDefaults).transportMode == .auto,
           "new installs default transport to Auto")
```

Create `emptyDefaults` with a unique volatile `UserDefaults(suiteName:)`, then clear its persistent domain.

- [ ] **Step 2: Run the self-test and verify failure**

Run:

```bash
swiftc -module-cache-path /private/tmp/displayweave-swift-module-cache Mac/RefreshRatePolicy.swift Mac/StreamEncodingPolicy.swift Mac/StreamSettings.swift MacTests/StreamSettingsSelfTest.swift -o /private/tmp/StreamSettingsSelfTest && /private/tmp/StreamSettingsSelfTest
```

Expected: compile failure because `.auto` and `.usb` do not exist, or assertion failure because the default is WiFi.

- [ ] **Step 3: Implement the three stable settings values**

Replace `StreamTransportMode` with:

```swift
enum StreamTransportMode: String, CaseIterable {
    case auto, usb, wifi

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .usb: return "USB"
        case .wifi: return "WiFi"
        }
    }
}
```

Change the missing/invalid stored-value fallback in `StreamSettings.load` from `.wifi` to `.auto`. Keep the raw persisted key `transportMode` for compatibility.

- [ ] **Step 4: Run the self-test and verify PASS**

Run the Step 2 command. Expected: `StreamSettingsSelfTest PASS`.

- [ ] **Step 5: Commit**

```bash
git add Mac/StreamSettings.swift MacTests/StreamSettingsSelfTest.swift
git commit -m "feat: add Auto USB and WiFi transport settings"
```

### Task 2: Parse and classify ADB devices

**Files:**
- Create: `Mac/AndroidAdb.swift`
- Create: `MacTests/AndroidAdbSelfTest.swift`

- [ ] **Step 1: Write failing parser and error-message tests**

Test these exact inputs:

```swift
let output = """
List of devices attached
R58M123 device product:foo model:Pixel_8 transport_id:1
ABC unauthorized usb:1-2 transport_id:2
XYZ offline usb:1-3 transport_id:3

"""
```

Assert `AndroidAdbDeviceList.parse(output)` returns three entries, preserves serials, maps states to `.device`, `.unauthorized`, `.offline`, and converts `model:Pixel_8` to display name `Pixel 8`. Assert localized failures contain the required Chinese guidance for missing, unauthorized, offline, no devices, and multiple selectable devices.

- [ ] **Step 2: Run and verify compile failure**

```bash
swiftc -module-cache-path /private/tmp/displayweave-swift-module-cache Mac/AndroidAdb.swift MacTests/AndroidAdbSelfTest.swift -o /private/tmp/AndroidAdbSelfTest
```

Expected: failure because `Mac/AndroidAdb.swift` or its types do not exist.

- [ ] **Step 3: Implement pure ADB device types and parser**

Define:

```swift
enum AndroidAdbState: Equatable { case device, unauthorized, offline, unknown(String) }

struct AndroidAdbDevice: Equatable, Identifiable {
    let serial: String
    let state: AndroidAdbState
    let model: String?
    var id: String { serial }
}

enum AndroidAdbFailure: Error, LocalizedError, Equatable {
    case executableNotFound([String])
    case noDevices
    case unauthorized(String)
    case offline(String)
    case multipleDevices([String])
    case commandFailed(exitCode: Int32, message: String)
    case timedOut
}
```

Implement whitespace-line parsing after the header. Split metadata fields only on the first colon so values are not truncated. Unknown daemon/status lines must be ignored unless they contain a serial and state token.

- [ ] **Step 4: Run and verify PASS**

Compile and execute the test binary. Expected: `AndroidAdbSelfTest PASS`.

- [ ] **Step 5: Commit**

```bash
git add Mac/AndroidAdb.swift MacTests/AndroidAdbSelfTest.swift
git commit -m "feat: parse Android ADB device states"
```

### Task 3: Resolve and run ADB without a shell

**Files:**
- Modify: `Mac/AndroidAdb.swift`
- Modify: `MacTests/AndroidAdbSelfTest.swift`

- [ ] **Step 1: Add failing resolver-priority and command tests**

Use injected `fileExists`, `isExecutable`, environment, home directory and PATH. Assert priority is configured path, PATH, `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `~/Library/Android/sdk`, `/opt/homebrew/bin`, `/usr/local/bin`. With a fake runner, assert discovery uses arguments `devices -l`; assert a selected serial always produces `-s`, the exact serial, then the subcommand. Assert no API accepts a shell command string.

- [ ] **Step 2: Run and verify failure**

Run the Task 2 compile command. Expected: missing resolver/runner symbols.

- [ ] **Step 3: Implement resolver and injectable process runner**

Add:

```swift
struct AndroidAdbCommandResult: Equatable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

protocol AndroidAdbProcessRunning {
    func run(executable: URL, arguments: [String], timeout: Duration) async throws
        -> AndroidAdbCommandResult
}
```

The production runner configures `Process.executableURL` and `Process.arguments`, captures stdout/stderr with pipes, enforces a finite timeout, terminates on cancellation, and never invokes `/bin/sh` or `/bin/zsh`. Error text truncates stderr to a safe bounded length.

- [ ] **Step 4: Run and verify PASS**

Run `AndroidAdbSelfTest`. Expected PASS for priority, no-PATH fallback, arguments, exit-code and timeout cases.

- [ ] **Step 5: Commit**

```bash
git add Mac/AndroidAdb.swift MacTests/AndroidAdbSelfTest.swift
git commit -m "feat: locate and execute ADB safely"
```

### Task 4: Allocate and own per-device forward mappings

**Files:**
- Create: `Mac/AndroidAdbForward.swift`
- Create: `MacTests/AndroidAdbForwardSelfTest.swift`

- [ ] **Step 1: Write failing multi-device mapping tests**

With fake runner and port allocator, create mappings for serial A and B. Assert different local ports, both remote ports equal 9000, and command arrays are:

```swift
["-s", "A", "forward", "tcp:19001", "tcp:9000"]
["-s", "B", "forward", "tcp:19002", "tcp:9000"]
```

Release A and assert only `["-s", "A", "forward", "--remove", "tcp:19001"]` runs; B remains owned. Assert no emitted arguments contain `--remove-all`.

- [ ] **Step 2: Run and verify compile failure**

```bash
swiftc -module-cache-path /private/tmp/displayweave-swift-module-cache Mac/AndroidAdb.swift Mac/AndroidAdbForward.swift MacTests/AndroidAdbForwardSelfTest.swift -o /private/tmp/AndroidAdbForwardSelfTest
```

Expected: missing forward-mapping types.

- [ ] **Step 3: Implement actor-isolated mapping ownership**

Define:

```swift
struct AndroidAdbForward: Equatable, Identifiable {
    let sessionID: UUID
    let serial: String
    let localPort: UInt16
    let remotePort: UInt16
    var id: UUID { sessionID }
}

actor AndroidAdbForwardManager {
    func create(serial: String, remotePort: UInt16 = 9000) async throws -> AndroidAdbForward
    func recreate(_ mapping: AndroidAdbForward) async throws
    func remove(sessionID: UUID) async
}
```

Allocate by binding an IPv4 loopback listener to port zero, read the assigned port, close it immediately before invoking ADB, and serialize allocation plus mapping creation in the actor. On ADB failure, do not record ownership. Removal looks up the exact owned mapping and is idempotent.

- [ ] **Step 4: Run and verify PASS**

Run the test binary. Expected: `AndroidAdbForwardSelfTest PASS`.

- [ ] **Step 5: Commit**

```bash
git add Mac/AndroidAdbForward.swift MacTests/AndroidAdbForwardSelfTest.swift
git commit -m "feat: manage per-device ADB forward mappings"
```

### Task 5: Define transport selection and recovery policy

**Files:**
- Create: `Mac/TransportSelectionPolicy.swift`
- Create: `MacTests/TransportSelectionPolicySelfTest.swift`

- [ ] **Step 1: Write failing mode and identity tests**

Cover:

```swift
assertEqual(.androidUSB("A"), policy.preferred(mode: .auto, androidUSB: "A", wifi: receiver))
assertEqual(.wifi(receiver.id), policy.preferred(mode: .wifi, androidUSB: "A", wifi: receiver))
assertEqual(nil, policy.preferred(mode: .usb, androidUSB: nil, wifi: receiver))
assertEqual(receiver.id, policy.fallbackWifi(usbInstallID: "install-1",
                                              receivers: [receiver]))
assertEqual(nil, policy.fallbackWifi(usbInstallID: nil, receivers: [receiver]))
assertEqual([0.5, 1, 2, 4, 8], TransportSelectionPolicy.recoveryDelays)
```

Also assert a receiver with a different install ID is never selected.

- [ ] **Step 2: Run and verify compile failure**

```bash
swiftc -module-cache-path /private/tmp/displayweave-swift-module-cache Mac/RefreshRatePolicy.swift Mac/StreamEncodingPolicy.swift Mac/StreamSettings.swift Mac/TransportSelectionPolicy.swift MacTests/TransportSelectionPolicySelfTest.swift -o /private/tmp/TransportSelectionPolicySelfTest
```

Expected: missing policy types.

- [ ] **Step 3: Implement the pure policy**

Keep Bonjour framework objects out of the policy. Use value candidates:

```swift
struct WifiTransportCandidate: Equatable {
    let id: String
    let installID: String?
}

enum TransportCandidate: Equatable {
    case androidUSB(String)
    case wifi(String)
}
```

Auto prefers available authorized Android USB; USB never returns WiFi; WiFi never returns USB. `fallbackWifi` requires non-nil equal install IDs. Recovery delays are finite and cancellation-aware at the controller layer.

- [ ] **Step 4: Run and verify PASS**

Run the test binary. Expected: `TransportSelectionPolicySelfTest PASS`.

- [ ] **Step 5: Commit**

```bash
git add Mac/TransportSelectionPolicy.swift MacTests/TransportSelectionPolicySelfTest.swift
git commit -m "feat: define Android transport selection policy"
```

### Task 6: Integrate Android ADB devices and TCP sessions

**Files:**
- Modify: `Mac/OpenSidecarMacApp.swift:95-565`
- Modify: `Mac/MacSender.swift:29-35,437-530`
- Modify: `MacTests/AndroidAdbForwardSelfTest.swift`

- [ ] **Step 1: Add a failing target-to-endpoint integration test**

Extract a pure adapter and test that `ConnectionTarget.androidAdb(serial: "A", localPort: 19001)` has session ID `android-adb:A`, transport label `USB`, and creates `.tcp(.hostPort(host: "127.0.0.1", port: 19001))` with advertised transport name `usb`.

- [ ] **Step 2: Run and verify failure**

Run `AndroidAdbForwardSelfTest`. Expected: missing Android target/adapter symbols.

- [ ] **Step 3: Add Android-specific target and device state**

Extend `ConnectionTarget` with `.androidAdb(serial: String, localPort: UInt16)` and keep `.usb` exclusively for Apple `usbmuxd`. Add published `androidDevices` and `androidAdbStatus` to `SenderController`. Start an `AndroidAdbManager` polling task with a moderate idle interval and immediate refresh on user action; stop it when mode is WiFi.

For each authorized Android device selected by policy:

1. create an owned forward mapping;
2. append a session whose stable ID is `android-adb:<serial>`;
3. create `MacSender` with a loopback TCP endpoint and explicit transport metadata `usb`;
4. store mapping ownership on the session;
5. on hello, persist `serial -> install ID` separately from Apple UDID identities.

Unauthorized/offline entries remain visible but are not connected. Multiple authorized devices each receive independent mappings and sessions.

- [ ] **Step 4: Implement exact mapping cleanup**

Make `end(_:)`, `disconnect`, `disconnectAll`, failed start, and app termination schedule `forwardManager.remove(sessionID:)` only for that Android session. Preserve existing Apple `sender.stop()` behavior.

- [ ] **Step 5: Run focused tests and build**

Run all four Mac self-tests plus the three new self-tests, then:

```bash
xcodebuild -quiet -project OpenSidecar.xcodeproj -scheme OpenSidecarMac -configuration Debug -derivedDataPath build-run -clonedSourcePackagesDirPath build-run/SourcePackages build
```

Expected: every self-test prints PASS and Xcode exits 0.

- [ ] **Step 6: Commit**

```bash
git add Mac/OpenSidecarMacApp.swift Mac/MacSender.swift MacTests/AndroidAdbForwardSelfTest.swift
git commit -m "feat: connect Android sessions through ADB forward"
```

### Task 7: Add bounded USB recovery and Auto WiFi fallback

**Files:**
- Modify: `Mac/MacSender.swift:437-530,728-820`
- Modify: `Mac/OpenSidecarMacApp.swift:380-493`
- Modify: `Mac/TransportSelectionPolicy.swift`
- Modify: `MacTests/TransportSelectionPolicySelfTest.swift`

- [ ] **Step 1: Add failing recovery-transition tests**

Use a deterministic recovery reducer with events `.socketFailed`, `.adbAvailable`, `.adbUnavailable`, `.reconnectSucceeded`, `.retriesExhausted`, `.wifiMatched`, `.cancelled`. Assert socket failure schedules 0.5 seconds; successful mapping recreation requests reconnect; exhausted Auto selects only a matching WiFi install ID; exhausted USB becomes a terminal error; cancellation schedules nothing.

- [ ] **Step 2: Run and verify failure**

Run `TransportSelectionPolicySelfTest`. Expected: missing recovery state/event symbols.

- [ ] **Step 3: Implement session-scoped recovery**

On Android ADB socket failure, controller retains the session identity, cancels the failed sender, checks the exact serial state, recreates its mapping, and attempts a fresh sender after each finite delay. Generation tokens prevent stale attempts from reviving a disconnected session.

After a reconnect receives hello:

- send the existing `streamConfig` through normal `MacSender` startup;
- invoke a new `requestKeyframe()` that sends existing `{\"type\":\"kf\"}` framing;
- mark recovery complete only after connection/hello; show “正在恢复” until then.

After retries exhaust in Auto, locate Bonjour TXT `id` equal to the persisted Android install ID and replace the target with WiFi. USB mode reports failure; WiFi mode never enters ADB recovery.

- [ ] **Step 4: Run policy tests and Mac build**

Expected: policy self-test PASS, existing framing/codec self-tests PASS, Xcode build exit 0.

- [ ] **Step 5: Commit**

```bash
git add Mac/MacSender.swift Mac/OpenSidecarMacApp.swift Mac/TransportSelectionPolicy.swift MacTests/TransportSelectionPolicySelfTest.swift
git commit -m "feat: recover Android USB and fall back to WiFi"
```

### Task 8: Expose device selection and actionable UI states

**Files:**
- Modify: `Mac/OpenSidecarMacApp.swift:607-760`
- Modify: `Mac/StreamSettings.swift`

- [ ] **Step 1: Add failing presentation-model assertions**

Add pure `AndroidAdbPresentation` tests to `AndroidAdbSelfTest` for no ADB, no devices, unauthorized, offline, one ready device and multiple ready devices. Assert each required Chinese message and whether Connect is enabled.

- [ ] **Step 2: Run and verify failure**

Run `AndroidAdbSelfTest`. Expected: missing presentation type.

- [ ] **Step 3: Implement UI**

Replace the read-only Transport label with a segmented picker over Auto/USB/WiFi and restart sessions on change. Add Android ADB rows keyed by serial, with model/short serial, state, explicit Connect button, and clear guidance. In USB mode, display failures without WiFi fallback. In Auto, show “USB 恢复失败，正在尝试同一设备 WiFi” only when identity match exists.

Add an advanced ADB path text field backed by `UserDefaults` key `androidAdbPath`; blank means automatic search. Do not require PATH changes.

- [ ] **Step 4: Run tests and build**

Expected: `AndroidAdbSelfTest PASS`, `StreamSettingsSelfTest PASS`, Xcode build exit 0.

- [ ] **Step 5: Commit**

```bash
git add Mac/OpenSidecarMacApp.swift Mac/StreamSettings.swift MacTests/AndroidAdbSelfTest.swift
git commit -m "feat: expose Android USB controls and errors"
```

### Task 9: Regression verification and Preview documentation

**Files:**
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- Modify: `AndroidReceiver/README.md`
- Create: `docs/stability-test-report.md`
- Create: `docs/usb-vs-wifi-benchmark.md`

- [ ] **Step 1: Run every automated verification gate**

Run all Mac standalone self-tests, Android Gradle tests, Android debug build, Mac Xcode build, and:

```bash
git diff --check
```

Expected: all commands exit 0. Record command, date, host/device scope and result in `docs/stability-test-report.md`.

- [ ] **Step 2: Run safe connected-device diagnostics when hardware exists**

Run the resolved ADB executable with `devices -l`. Do not change device state merely to make a test pass. If an authorized device is present, verify forward creation/removal through the app and confirm no stale mapping in `adb -s <serial> forward --list` after disconnect.

- [ ] **Step 3: Execute or explicitly defer the hardware matrix**

Test single USB, two Android USB devices, mixed USB/WiFi, Apple coexistence, unplug/replug, ADB server restart, app restart, lock/unlock, 50 reconnects, 10-minute benchmark, 30-minute stability and 2-hour endurance. For every item not actually run, write `待人工验证` with prerequisites; never infer PASS from a build.

- [ ] **Step 4: Document setup and measured results**

Update English/Chinese READMEs and Android README with USB debugging authorization, Auto/USB/WiFi behavior, explicit security warning, and troubleshooting. Fill `docs/usb-vs-wifi-benchmark.md` with identical codec/fps/resolution/bitrate conditions and every metric required by the approved design. Do not claim USB improves FPS unless measurements prove it.

- [ ] **Step 5: Commit**

```bash
git add README.md README.zh-CN.md AndroidReceiver/README.md docs/stability-test-report.md docs/usb-vs-wifi-benchmark.md
git commit -m "docs: verify Android USB preview transport"
```

### Task 10: Continue Preview 0.1 release closure

**Files:**
- Audit/update: `ARCHITECTURE.md`, `ROADMAP.md`, `CONTRIBUTING.md`, `SECURITY.md`, `THIRD_PARTY_NOTICES.md`, `docs/*`, `src/*`, `index.html`, `public/*`
- Create/update: `docs/brand-assets.md`, `docs/release-checklist.md`, `docs/release-notes-preview-0.1.md`

- [ ] **Step 1: Reconcile status claims against verified evidence**

Classify each feature as completed, experimental, verified, planned, or incomplete. Correct stale H.264-only architecture text, decoder names, HEVC roadmap state, Android USB status, iOS/iPadOS 120Hz status, measured 109–111 FPS wording, DisplayWeave/OpenDisplay relationship, SideScreen attribution, and GPL-3.0 terms.

- [ ] **Step 2: Audit brand assets without inventing a final logo**

Inventory README, Mac/iOS/Android icons, website logo/favicon/OG/Twitter assets and old OpenDisplay imagery in `docs/brand-assets.md`. Reuse an existing committed DisplayWeave logo if present; otherwise list missing assets and mark placeholders explicitly.

- [ ] **Step 3: Build Preview artifacts and record truthfully**

Run Android clean/test/release build, signature verification and SHA-256; run Mac self-tests, clean Xcode build and launch smoke test. Record unsigned/unnotarized status when applicable. Do not claim install or hardware tests that were not executed.

- [ ] **Step 4: Write checklist and release notes**

Create the two required release documents with supported features and the stated limitations: hardware-dependent Android 120fps, measured 109–111 FPS device result, iOS/iPadOS 120Hz not implemented, Android WiFi encrypted pairing not implemented, and exact Mac signing/notarization state.

- [ ] **Step 5: Final requirement-by-requirement audit**

Map every item from the user-provided Preview 0.1 goal to authoritative evidence. Keep unverified hardware items open and clearly identify the manual actions needed. Run `git diff --check` and inspect `git status --short --branch` before claiming completion.

