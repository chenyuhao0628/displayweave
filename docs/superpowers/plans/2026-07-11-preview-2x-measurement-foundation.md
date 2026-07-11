# Preview 2.x Measurement Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add trustworthy Android-to-Mac performance samples, stable clock-offset estimates, and CSV/JSONL short-benchmark recording without changing bitrate caps, adaptive bitrate, or send-queue policy.

**Architecture:** Keep transport compatibility by extending the existing length-prefixed `stats` JSON message. Android owns receiver/decode/render and single-clock frame-age aggregation; Mac owns capture/encode/send and file recording. Pure policy/value types remain outside UI classes so standalone Java and Swift self-tests can drive every behavior before integration.

**Tech Stack:** Java 17 self-tests, Android `org.json`, Swift 5.9/Foundation, Network.framework JSON control frames, existing Gradle and standalone `swiftc` test harnesses.

---

### Task 1: Android latency distribution and clock estimator policies

**Files:**
- Create: `AndroidReceiver/app/src/main/java/app/opendisplay/android/MetricDistribution.java`
- Create: `AndroidReceiver/app/src/main/java/app/opendisplay/android/ClockOffsetEstimator.java`
- Modify: `AndroidReceiver/tests/java/app/opendisplay/android/VideoStreamPolicySelfTest.java`
- Modify: `AndroidReceiver/app/build.gradle.kts`

- [ ] **Step 1: Write failing policy tests**

Add tests that require: empty distributions return `MISSING_MS`; sorted nearest-rank P50/P95/P99; latest value is preserved; the clock estimator rejects negative and high RTT, stays `estimating` before three accepted samples, selects the median offset from the lowest-RTT stable window, and reports confidence as half of the selected RTT spread.

```java
MetricDistribution ages = new MetricDistribution(120);
for (long value : new long[] {8, 4, 20, 10, 6}) ages.add(value);
assertEquals(8L, ages.p50());
assertEquals(20L, ages.p95());
assertEquals(6L, ages.latest());

ClockOffsetEstimator clock = new ClockOffsetEstimator(8, 250.0, 3);
clock.addSample(12.0, 101.0);
clock.addSample(8.0, 99.0);
assertEquals("estimating", clock.state());
clock.addSample(10.0, 100.0);
assertEquals("stable", clock.state());
assertEquals(100.0, clock.offsetMs());
```

- [ ] **Step 2: Run the self-test and confirm RED**

Run: `ANDROID_HOME=/Users/cyh/Library/Android/sdk ./gradlew runVideoStreamPolicySelfTest`

Expected: Java compilation fails because `MetricDistribution` and `ClockOffsetEstimator` do not exist.

- [ ] **Step 3: Implement the minimal pure policies**

Use bounded `ArrayDeque<Double>` storage, copy-and-sort only when a percentile is requested, nearest-rank indexes clamped to the list bounds, and a `Snapshot`/getter API that never fabricates zero for missing latency. The clock estimator keeps accepted `(rtt, offset)` samples, drops RTT outside `[0, 250]`, uses the lowest-RTT half of the window, and derives a median offset plus explicit `estimating`/`stable` state.

- [ ] **Step 4: Run GREEN and the complete Android tests**

Run: `ANDROID_HOME=/Users/cyh/Library/Android/sdk ./gradlew runVideoStreamPolicySelfTest test`

Expected: `VideoStreamPolicySelfTest PASS` and `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```bash
git add AndroidReceiver/app/src/main/java/app/opendisplay/android/MetricDistribution.java AndroidReceiver/app/src/main/java/app/opendisplay/android/ClockOffsetEstimator.java AndroidReceiver/tests/java/app/opendisplay/android/VideoStreamPolicySelfTest.java AndroidReceiver/app/build.gradle.kts
git commit -m "feat: add receiver metric and clock policies"
```

### Task 2: Android structured stats message

**Files:**
- Create: `AndroidReceiver/app/src/main/java/app/opendisplay/android/ReceiverStatsSnapshot.java`
- Modify: `AndroidReceiver/app/src/main/java/app/opendisplay/android/protocol/LengthPrefixedProtocol.java`
- Modify: `AndroidReceiver/app/src/main/java/app/opendisplay/android/StreamMetrics.java`
- Modify: `AndroidReceiver/app/src/main/java/app/opendisplay/android/OpenDisplayServer.java`
- Modify: `AndroidReceiver/app/src/main/java/app/opendisplay/android/MainActivity.java`
- Modify: `AndroidReceiver/tests/java/app/opendisplay/android/protocol/ProtocolSelfTest.java`
- Modify: `AndroidReceiver/tests/java/app/opendisplay/android/VideoStreamPolicySelfTest.java`

- [ ] **Step 1: Write failing JSON and snapshot tests**

Require a `stats` object containing receiver timestamps and every receiver-owned field. Use JSON `null` for unavailable numeric values, never zero or a string sentinel on wire.

```java
ReceiverStatsSnapshot stats = ReceiverStatsSnapshot.unavailable("wifi", "hevc", 2560, 1600, 120);
String json = stats.toJson();
assertContains(json, "\"type\":\"stats\"");
assertContains(json, "\"frameAgeP95Ms\":null");
assertContains(json, "\"clockState\":\"estimating\"");
assertContains(json, "\"inputP95Ms\":null");
```

- [ ] **Step 2: Run RED**

Run: `ANDROID_HOME=/Users/cyh/Library/Android/sdk ./gradlew runProtocolSelfTest runVideoStreamPolicySelfTest`

Expected: compilation fails on the missing snapshot type and fields.

- [ ] **Step 3: Implement receiver aggregation and publication**

`OpenDisplayServer` must collect receive-to-render latest/P50/P95/P99, estimated E2E, send-to-render estimate, RTT, offset/confidence/state, queue depth, classified receiver drops, actual display Hz, and input P50/P95. On every >=1-second metrics window it sends one `stats` message through the existing receiver transport and still updates the local overlay. Preserve old ping/pong, old video framing, and old clients that ignore unknown JSON keys.

- [ ] **Step 4: Correct names at the boundary without breaking overlay compatibility**

Expose canonical names (`frameAgeAvgMs`, `frameAgeLatestMs`, `sendToRenderEstimatedMs`, `encodeApiLatencyAvgMs`) in stats JSON. Legacy `StreamMetrics` fields may remain temporarily as adapter properties, but new code and docs must use canonical names. Display `androidDisplayRefreshRate` as actual Hz and retain requested FPS separately.

- [ ] **Step 5: Run GREEN and Android regression suite**

Run: `ANDROID_HOME=/Users/cyh/Library/Android/sdk ./gradlew clean test assembleDebug`

Expected: four self-tests print PASS and Gradle exits 0.

- [ ] **Step 6: Commit**

```bash
git add AndroidReceiver/app/src/main AndroidReceiver/tests AndroidReceiver/app/build.gradle.kts
git commit -m "feat: publish structured Android stream stats"
```

### Task 3: Mac stats decoder and benchmark sample schema

**Files:**
- Create: `Mac/BenchmarkSample.swift`
- Create: `MacTests/BenchmarkSampleSelfTest.swift`
- Modify: `project.yml`

- [ ] **Step 1: Write a failing standalone decoder test**

Require decoding a receiver `stats` JSON object, preserving null as unavailable, merging explicit local measurements, and serializing stable JSONL/CSV column order.

```swift
let receiver = try ReceiverStats(json: #"{"type":"stats","renderedFps":118,"frameAgeP95Ms":14,"clockState":"stable"}"#)
let sample = BenchmarkSample.fixture(receiver: receiver)
assertEqual(118, sample.renderedFps)
assertEqual("notAvailable", sample.csvValue(\.macCPUPercent))
assertTrue(sample.jsonLine.contains(#""frameAgeP95Ms":14"#))
assertEqual(BenchmarkSample.csvHeader.count, sample.csvRow.count)
```

- [ ] **Step 2: Run RED**

Run: `swiftc -module-cache-path /private/tmp/displayweave-swift-module-cache Mac/BenchmarkSample.swift MacTests/BenchmarkSampleSelfTest.swift -o /private/tmp/BenchmarkSampleSelfTest`

Expected: missing-file/type compile failure.

- [ ] **Step 3: Implement Codable value types**

Use `Optional` for unavailable numbers, `ContinuousClock` duration for monotonic elapsed time, ISO-8601 UTC for wall timestamp, and fixed schema names from the roadmap. `BenchmarkSample` must include every required CSV/JSONL field, plus `runId`, `sessionId`, `scene`, `clockState`, and `offsetConfidenceMs`. CSV escapes commas/quotes/newlines and writes `notAvailable` for nil; JSONL writes JSON `null`.

- [ ] **Step 4: Run GREEN**

Run the compile command and `/private/tmp/BenchmarkSampleSelfTest`.

Expected: `BenchmarkSampleSelfTest PASS`.

- [ ] **Step 5: Commit**

```bash
git add Mac/BenchmarkSample.swift MacTests/BenchmarkSampleSelfTest.swift project.yml
git commit -m "feat: define benchmark sample schema"
```

### Task 4: Atomic CSV/JSONL benchmark recorder

**Files:**
- Create: `Mac/BenchmarkRecorder.swift`
- Create: `MacTests/BenchmarkRecorderSelfTest.swift`
- Modify: `project.yml`

- [ ] **Step 1: Write failing recorder lifecycle tests**

Test a temporary directory: start creates one `.csv` and one `.jsonl`; CSV header is written once; two samples produce two data rows and two JSON lines; stop flushes/closes; a second run uses a different run ID; invalid output paths return a surfaced error without crashing the stream.

- [ ] **Step 2: Run RED**

Run: `swiftc -module-cache-path /private/tmp/displayweave-swift-module-cache Mac/BenchmarkSample.swift Mac/BenchmarkRecorder.swift MacTests/BenchmarkRecorderSelfTest.swift -o /private/tmp/BenchmarkRecorderSelfTest`

Expected: missing recorder compile failure.

- [ ] **Step 3: Implement the recorder**

Use a dedicated serial dispatch queue and two `FileHandle`s. Create files under `~/Library/Application Support/DisplayWeave/Benchmarks/<run-id>/`; dependency-inject the root directory and clock for tests. `append` writes a complete encoded line per file on the queue. `stop` synchronizes, closes both handles, and returns final URLs. Never create placeholder samples.

- [ ] **Step 4: Run GREEN and both benchmark self-tests**

Run both standalone binaries. Expected: both print PASS.

- [ ] **Step 5: Commit**

```bash
git add Mac/BenchmarkRecorder.swift MacTests/BenchmarkRecorderSelfTest.swift project.yml
git commit -m "feat: record benchmark CSV and JSONL"
```

### Task 5: Integrate receiver stats with the Mac session

**Files:**
- Modify: `Mac/MacSender.swift`
- Modify: `Mac/OpenSidecarMacApp.swift`
- Modify: `Mac/VirtualDisplay.swift`
- Modify: `MacTests/StreamEncodingPolicySelfTest.swift`
- Modify: `MacTests/BenchmarkRecorderSelfTest.swift`

- [ ] **Step 1: Write failing integration-policy tests**

Add pure tests for: stats JSON decoding; target and actual bitrate remain distinct; actual virtual-display refresh can be updated from a new mode read; receiver stats do not start a recorder unless Benchmark Mode is explicitly active; missing CPU/memory fields serialize unavailable.

- [ ] **Step 2: Run RED**

Run the relevant standalone Swift self-tests. Expected: failures on missing session integration API.

- [ ] **Step 3: Implement minimal session integration**

Decode Android `stats` in the existing `case "stats"`. Merge it with the latest local counters and append only while a recorder run is active. Keep `onStats(frames, mbps)` working for the existing UI. Sample Mac resident memory with `task_info`; if CPU sampling cannot be reliable within the interval, leave it nil. Reread `CGDisplayCopyDisplayMode` periodically and update the sample rather than assuming the creation-time value remains current.

- [ ] **Step 4: Add explicit Benchmark controls**

In the existing session/settings UI, add Debug-only scene selection (`staticDesktop`, `textScroll`, `browserScroll`, `testPattern120`, `rapidWindowDrag`), duration (`3 min`, `5 min`, optional `10 min`), and Start/Stop actions. Starting generates run/session IDs and begins a 30-second warm-up; samples during warm-up carry `phase=warmup`, followed by `phase=run`. Do not auto-run physical scenarios or synthesize samples.

- [ ] **Step 5: Run GREEN, xcodegen, self-tests, and xcodebuild**

Run standalone tests, `xcodegen generate`, then:

`xcodebuild -quiet -project OpenSidecar.xcodeproj -scheme OpenSidecarMac -configuration Debug -derivedDataPath build/preview2x-measurement -clonedSourcePackagesDirPath /Users/cyh/Documents/opendisplay/build-run/SourcePackages -disableAutomaticPackageResolution build CODE_SIGNING_ALLOWED=NO`

Expected: every self-test prints PASS and xcodebuild exits 0.

- [ ] **Step 6: Commit**

```bash
git add Mac MacTests project.yml
git commit -m "feat: integrate short benchmark recording"
```

### Task 6: Benchmark and latency documentation

**Files:**
- Create: `docs/benchmark-guide.md`
- Create: `docs/benchmark-guide.zh-CN.md`
- Create: `docs/latency-measurement.md`
- Create: `docs/latency-measurement.zh-CN.md`
- Modify: `docs/README.md`
- Modify: `docs/README.zh-CN.md`

- [ ] **Step 1: Document the reproducible protocol**

Specify the five scenes, fixed parameter matrix, 30-second warm-up, 3-minute standard, 5-minute extended, optional 10-minute local run, two required repetitions and optional third. Explain output paths, all schema fields, `notAvailable`/JSON null behavior, and how to annotate an aborted run.

- [ ] **Step 2: Document honest latency semantics**

Define capture timestamp, encoder submit/output, socket send, Android receive, decoder submit/output, and render timestamp. Separate encode API latency, network transit estimate, MediaCodec latency, render delay, receive-to-render frame age, and estimated E2E. Explain clock state/confidence and why `estimating`/`unavailable` suppresses cross-clock values.

- [ ] **Step 3: Run documentation checks**

Run: `pnpm run check:docs && pnpm run check:release && git diff --check`

Expected: all commands exit 0.

- [ ] **Step 4: Commit**

```bash
git add docs
git commit -m "docs: add short benchmark and latency guides"
```

### Task 7: Measurement foundation verification

**Files:**
- Modify only if verification uncovers a defect covered by a new failing regression test.

- [ ] **Step 1: Run Android clean build and tests**

Run: `ANDROID_HOME=/Users/cyh/Library/Android/sdk ./gradlew --no-daemon clean test assembleDebug`

Expected: all four or newly registered self-tests PASS and Gradle exits 0.

- [ ] **Step 2: Run all Mac standalone self-tests**

Compile and execute every file in `MacTests/` using its declared production dependencies. Expected: every binary prints `PASS`.

- [ ] **Step 3: Run macOS Debug xcodebuild**

Generate the project and build `OpenSidecarMac` with signing disabled and the cached Sparkle checkout. Expected: exit 0.

- [ ] **Step 4: Run site/docs checks and diff validation**

Run: `pnpm build && pnpm run check:docs && pnpm run check:release && git diff --check`

Expected: all commands exit 0.

- [ ] **Step 5: Verify an honest empty benchmark**

Start and stop a recorder through the unit-tested API without a receiver. Confirm headers exist and no fabricated sample row is written. Physical 3-minute runs remain pending until an available device is connected and must be documented as pending, not passed.

- [ ] **Step 6: Commit any verification-only regression fix**

Only if Step 1–5 exposed a defect: first add a failing regression test, then the minimal fix, rerun the full gate, and commit the exact affected files.
