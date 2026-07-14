// MacSender — captures a display, encodes it, streams it to the phone.
//
// Milestone 1 (mirror):  capture the main display.
// Milestone 2 (extend):  create a CGVirtualDisplay sized to the phone panel
//                        (announced by the phone in a "hello" message) and
//                        capture that — macOS gains a true second monitor.
//
// Pipeline:  ScreenCaptureKit -> VideoToolbox -> framed TCP
// Roles: the PHONE listens, the MAC connects (required for usbmux/USB).
//
// Wire protocol, Mac -> phone:   [4-byte big-endian length][Annex B payload]
//   (keyframes prefixed with SPS+PPS, NALUs delimited by 00 00 00 01)
// Wire protocol, phone -> Mac:   [4-byte big-endian length][JSON message]
//   e.g. {"type":"hello","pixelsWide":2556,"pixelsHigh":1179,"scale":3}

import ScreenCaptureKit
import VideoToolbox
import Network
import CoreMedia
import AppKit

enum CaptureMode: String {
    case mirror   // main display (Milestone 1)
    case extend   // virtual display (Milestone 2)
}

/// How the sender reaches the receiver. Reconnects re-dial from scratch, so
/// a USB device that was replugged (new usbmuxd DeviceID) is found again.
enum SenderTransport {
    case tcp(NWEndpoint)                   // WiFi (Bonjour) or -host/-port override
    case usb(udid: String?, port: UInt16)  // native usbmuxd dial; nil = first device
    case androidAdb(port: UInt16)          // localhost endpoint created by adb forward
}

@available(macOS 14.0, *)
final class MacSender: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {

    // Status surfaced to the UI (updated on main thread).
    @MainActor var onStatus: ((String) -> Void)?
    @MainActor var onStats: ((Int, Double) -> Void)?   // framesSent, mbps
    @MainActor var onTargetBitrate: ((Double) -> Void)?
    @MainActor var onBenchmarkStatus: ((String) -> Void)?
    // Fired when a previously connected device stays gone past the grace
    // period — the controller ends the session (capture, virtual display,
    // recording indicator all torn down) instead of dialing forever or
    // silently coming back over a different transport.
    @MainActor var onDisconnected: (() -> Void)?
    // Fired on every hello — carries the receiver's install id so the
    // controller can deduplicate USB/WiFi sessions to the same device.
    @MainActor var onHello: ((PhoneInfo) -> Void)?

    private var stream: SCStream?
    private var encoder: VTCompressionSession?
    private var connection: NWConnection?
    private var virtualDisplay: VirtualDisplay?
    private let queue = DispatchQueue(label: "sender.video")
    private let startCode: [UInt8] = [0, 0, 0, 1]

    private let transport: SenderTransport
    private let endpointName: String
    private let mode: CaptureMode
    private let quality: StreamQuality
    private let settings: StreamSettings
    private let testPatternOwnerID = UUID()
    // Stable per-device serial for the virtual display, so macOS can tell
    // multiple OpenDisplay monitors apart and persist their arrangement.
    private let displaySerial: UInt32

    // Backpressure: outstanding sends. If the socket can't keep up we drop
    // the raw capture before VideoToolbox rather than queueing latency. That
    // does not break the encoded reference chain and must not force an IDR.
    // Kept tight: at 60fps each queued send is ~17ms of added latency.
    private var pendingSends = 0
    private var nextPendingSendID: UInt64 = 0
    private var pendingSendStartedAt: [UInt64: TimeInterval] = [:]
    private var lastSendCompletionDelayMs: Double = 0
    private var localEncodedFrames = 0
    private var localSentFrames = 0
    private var localCongestionWindowStart = ProcessInfo.processInfo.systemUptime
    private var lastLocalOldestPendingSendAgeMs: Double = 0
    private var lastLocalEncodedFps: Double = 0
    private var lastLocalSentFps: Double = 0
    private var maxPendingSends: Int { SendQueuePolicy.budget(quality: quality) }
    private var dropsThisWindow = 0
    private var keyframeRequests = KeyframeRequestTracker(initialReason: .streamReconfigure)
    private var needsKeyframe: Bool { keyframeRequests.hasPendingRequest }
    private var connectionReady = false
    private var stopped = false
    // The liveness monitors are self-rescheduling chains guarded only by
    // `stopped`; arm them at most once per instance so a double start() can't
    // stack parallel loops (the failure mode behind #75). Mirrors the
    // `monitorsStarted` guard the iOS PhoneReceiver already uses.
    private var monitorsStarted = false

    // Disconnect detection: before the first connection we dial patiently
    // (the user may start the Mac side first); once connected, a device that
    // stays gone past the grace ends the session via onDisconnected.
    private var everConnected = false
    private var disconnectedSince: Date?
    private let disconnectGraceSeconds: TimeInterval = 10

    private var lastHello: PhoneInfo?
    private var helloContinuation: CheckedContinuation<PhoneInfo, Error>?
    private var inputInjector: InputInjector?
    private var protocolIdentity = StreamProtocolIdentity()
    private var protocolHandshake = ReceiverProtocolHandshake()
    private var protocolFailureBudget = ReceiverProtocolFailureBudget(maxReconnects: 1)
    // VideoToolbox callbacks can arrive after a disconnect or reconnect. Tie
    // every encode to the ready connection that accepted it so an old frame
    // can never be written to a newer peer.
    private var wireConnectionGeneration: UInt64 = 0

    // Liveness: both sides ping every 2s; if nothing arrives for 5s the link
    // is half-open (e.g. usbmuxd accepted but the device is gone) — reconnect.
    private var lastReceived = Date()
    private var dropsTotal = 0

    // Local cursor echo: a cursor baked into the video carries the full
    // capture→encode→stream→display latency (~30ms perceived). Instead we
    // hide it from capture and stream its position on the control channel —
    // the phone draws it locally on the ~2ms path the touches use.
    // Escape hatch: `defaults write app.displayweave.mac.debug localCursor -bool false`.
    private let localCursor = UserDefaults.standard.object(forKey: "localCursor") == nil
        || UserDefaults.standard.bool(forKey: "localCursor")
    private var cursorTimer: DispatchSourceTimer?
    private var cursorImageTimer: DispatchSourceTimer?
    private var lastCursorSent: (x: Double, y: Double, visible: Bool) = (-1, -1, false)
    private var lastCursorPNGHash = 0
    private var captureDisplayID: CGDirectDisplayID = 0

    // Input latency: touches arrive stamped in our clock (the phone applies
    // its sync offset); delta to now = network + deframe + dispatch.
    private var inputLatencies: [Double] = []
    // Capture cadence: SCK only emits on content change, so the phone can't
    // tell "Mac rendered 45fps" from "frames got lost" — count deliveries here.
    private var capFrames = 0
    private var capWindowStart = Date()
    private var requestedCaptureFps = 60
    private var actualVirtualDisplayRefreshRate = 60
    private var lastCaptureFpsWarningAt = Date.distantPast
    private var streamCodec: StreamCodec = .h264
    private var streamBitrate = 0
    private var activeStreamWidth = 0
    private var activeStreamHeight = 0
    private var encodedFramesWindow = 0
    private var encodedBytesWindow = 0
    private var encodeLatencyMsWindow: [Double] = []
    private var encodeStatsWindowStart = Date()
    private var lastEncodedFps = 0
    private var lastAverageFrameSize = 0
    private var lastEncodeLatencyMs: Double = 0
    private var keyframesWindow = 0
    private var keyframeBytesWindow = 0
    private var peakFrameBytesWindow = 0
    private var keyframeQueueDepthWindow = 0
    private var lastKeyframeCount = 0
    private var lastAverageKeyframeSize = 0
    private var lastPeakFrameSize = 0
    private var lastKeyframeQueueDepth = 0
    private var decoderRecoveryEvent: String?

    private var framesSent = 0
    private var bytesSent = 0
    private var statsWindowStart = Date()
    private var lastSentFps = 0
    private var lastCaptureFps = 0
    private var lastActualBitrateMbps: Double = 0
    private var adaptiveBitrateController: AdaptiveBitrateController?
    private var lastAdaptiveDecision: AdaptiveBitrateDecision?
    private var lastMacDropsSnapshot = 0

    private let benchmarkClock = ContinuousClock()
    private var benchmarkRecorder: BenchmarkRecorder?
    private var benchmarkStartedAt: ContinuousClock.Instant?
    private var benchmarkPhasePolicy: BenchmarkPhasePolicy?
    private var benchmarkRunId: String?
    private var benchmarkSessionId: String?
    private var benchmarkScene: BenchmarkScene?
    private var benchmarkFinishWorkItem: DispatchWorkItem?
    private var benchmarkOutputDirectory: URL?

    // ScreenCaptureKit emits frames only when content changes. After a
    // reconnect on a static screen there is nothing to hang the forced
    // keyframe on — so keep the last frame around and re-encode it.
    private var lastPixelBuffer: CVPixelBuffer?
    private var lastCaptureAt = Date.distantPast

    init(transport: SenderTransport, name: String, mode: CaptureMode,
         settings: StreamSettings = StreamSettings.load(), displaySerial: UInt32 = 0x0001) {
        self.transport = transport
        self.endpointName = name
        self.mode = mode
        self.settings = settings
        self.quality = settings.quality
        self.displaySerial = displaySerial
        super.init()
    }

    // MARK: - Lifecycle

    func start() async throws {
        stopped = false
        queue.async { self.connect() }   // dial state lives on `queue`
        if !monitorsStarted {
            monitorsStarted = true
            schedulePing()
            scheduleWatchdog()
            scheduleLocalCongestionCheck()
        }

        // Screen Recording permission: poll until granted. No auto-prompt at
        // launch — the permission panel's Grant button triggers the system
        // dialog, so the request always has visible context.
        if !CGPreflightScreenCaptureAccess() {
            await status("需要屏幕录制权限，请在下方“权限”中授权")
            Log.info("Screen Recording permission missing — waiting for grant via the permission panel")
            while !CGPreflightScreenCaptureAccess() {
                try await Task.sleep(for: .seconds(2))
                if stopped { return }
            }
            Log.info("Screen Recording permission granted")
        }

        switch mode {
        case .mirror:
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else {
                throw NSError(domain: "MacSender", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "未找到可捕获的显示器"])
            }
            // SCDisplay reports points; capture at point resolution for M1.
            let captureW = (Int(Double(display.width) * quality.scale)) & ~1
            let captureH = (Int(Double(display.height) * quality.scale)) & ~1
            let captureFps = RefreshRatePolicy.selected(
                deviceMaxFps: settings.fpsMode.userSelectedFps ?? RefreshRatePolicy.fallbackFps,
                userSelectedFps: settings.fpsMode.userSelectedFps)
            let codec = settings.selectedCodec(supportedCodecs: ["h264"], preferredCodec: "h264")
            try await startCapture(display: display, pixelsWide: captureW, pixelsHigh: captureH,
                                   fps: captureFps, virtualDisplayRefreshRate: captureFps,
                                   codec: codec)
            inputInjector = InputInjector(displayID: display.displayID)
            try await waitForAccessibilityIfNeeded(statusText: "正在镜像，请授权“辅助功能”以启用触摸输入")

        case .extend:
            await status("正在等待设备连接…")
            let info = try await waitForHello()
            try await setupExtend(info)

            // Touch back-channel (Milestone 3). Needs Accessibility trust;
            // streaming works without it, so don't interrupt with a prompt —
            // the permission panel's Grant button asks when the user is ready.
            try await waitForAccessibilityIfNeeded(statusText: "正在扩展，请授权“辅助功能”以启用触摸输入")
        }
    }

    private func waitForAccessibilityIfNeeded(statusText: String) async throws {
        guard !AXIsProcessTrusted() else { return }
        await status(statusText)
        // Event posting is trust-checked per-post, so it starts working
        // the moment the user grants — poll just to log/report it.
        while !AXIsProcessTrusted() {
            try await Task.sleep(for: .seconds(2))
            if stopped { return }
        }
        Log.info("Accessibility permission granted — touch input live")
    }

    /// Build (or rebuild) the virtual display + capture for the announced
    /// phone dimensions. Called at startup and again whenever the phone
    /// rotates (it re-sends hello with swapped dimensions).
    private func setupExtend(_ info: PhoneInfo) async throws {
        Log.info("phone hello: \(info.pixelsWide)x\(info.pixelsHigh) @\(info.scale)x device=\(info.negotiatedDeviceModel) refresh=\(info.negotiatedRefreshRate)Hz maxFps=\(info.negotiatedMaxFps) codecs=\(info.negotiatedSupportedCodecs.joined(separator: ",")) preferred=\(info.negotiatedPreferredCodec) sdk=\(info.negotiatedAndroidSdk) transport=\(info.negotiatedTransport)")

        // Phone panel is @3x; the virtual display runs @2x HiDPI, so points
        // = native pixels / 2 (rounded down to even for the encoder).
        let pointsWide = (info.pixelsWide / 2) & ~1
        let pointsHigh = (info.pixelsHigh / 2) & ~1
        // Rough physical size so macOS picks a sane default UI scale.
        let mm = info.pixelsWide >= info.pixelsHigh
            ? CGSize(width: 147, height: 68)
            : CGSize(width: 68, height: 147)

        // USB sessions can start before lockdown resolves the device name —
        // fall back to the kind from the hello rather than the generic label.
        let displayName = endpointName.hasPrefix("iPhone / iPad")
            ? "DisplayWeave — \(info.kind)"
            : "DisplayWeave — \(endpointName)"
        // Orientation-specific serial: macOS persists the chosen mode per
        // serial, and a portrait mode restored onto a landscape display
        // pillarboxes the desktop INTO the framebuffer (streamed as-is).
        // Distinct serials per orientation keep the two configs apart.
        let serial = info.pixelsWide >= info.pixelsHigh
            ? displaySerial
            : displaySerial ^ 0x8000_0000
        let requestedRefreshRate = settings.selectedFps(deviceMaxFps: info.negotiatedMaxFps)
        let vd = await MainActor.run {
            VirtualDisplay(name: displayName,
                           pointsWide: pointsWide, pointsHigh: pointsHigh,
                           sizeInMillimeters: mm, serialNum: serial,
                           requestedRefreshRate: requestedRefreshRate)
        }
        guard let vd else {
            throw NSError(domain: "MacSender", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "创建虚拟显示器失败"])
        }
        Log.info("virtual display refresh selected: requested=\(requestedRefreshRate) actual=\(vd.actualRefreshRate) deviceMaxFps=\(info.negotiatedMaxFps) fallback=\(vd.refreshRateFallbackReason ?? "none")")
        virtualDisplay = vd
        inputInjector = InputInjector(displayID: vd.displayID)

        let display = try await findSCDisplay(id: vd.displayID)
        // Quality scaling: capture/encode below native when requested — the
        // display itself stays native so window layout is unaffected.
        let captureW = (Int(Double(pointsWide * 2) * quality.scale)) & ~1
        let captureH = (Int(Double(pointsHigh * 2) * quality.scale)) & ~1
        let codec = settings.selectedCodec(
            supportedCodecs: info.negotiatedSupportedCodecs,
            preferredCodec: info.negotiatedPreferredCodec)
        try await startCapture(display: display, pixelsWide: captureW, pixelsHigh: captureH,
                               fps: vd.actualRefreshRate,
                               virtualDisplayRefreshRate: vd.actualRefreshRate,
                               codec: codec)

        // Debug aid (`defaults write app.displayweave.mac.debug testPattern -bool true`):
        // an animated window on the virtual display generates a constant frame
        // stream so steady-state latency can be measured without user activity.
        if ApplicationIdentityPolicy.testPatternEnabled(
            bundleIdentifier: Bundle.main.bundleIdentifier,
            storedValue: UserDefaults.standard.bool(forKey: "testPattern")) {
            let id = vd.displayID
            let testPatternOwnerID = self.testPatternOwnerID
            Task { @MainActor [weak self] in
                guard let self, !self.stopped else { return }
                TestPattern.show(ownerID: testPatternOwnerID, on: id)
            }
        }
    }

    /// Tear down and rebuild when the phone announces new dimensions. Loops
    /// until the built display matches the latest hello, so rotations that
    /// arrive mid-rebuild aren't lost (and rapid flip-flops settle once).
    private var reconfiguring = false
    private func reconfigure(_ info: PhoneInfo) async {
        guard !reconfiguring, !stopped else { return }
        reconfiguring = true
        defer { reconfiguring = false }
        var target = info
        while !stopped {
            Log.info("reconfiguring for \(target.pixelsWide)x\(target.pixelsHigh)")
            if let stream { try? await stream.stopCapture() }
            stream = nil
            if let encoder { VTCompressionSessionInvalidate(encoder) }
            encoder = nil
            let testPatternOwnerID = self.testPatternOwnerID
            await MainActor.run {
                TestPattern.hide(ownerID: testPatternOwnerID)
            }
            virtualDisplay = nil   // removes the old display
            requestKeyframe(.streamReconfigure)
            do {
                try await setupExtend(target)
            } catch {
                Log.info("reconfigure failed: \(error)")
                await status("旋转失败：\(error.localizedDescription)")
                return
            }
            if let latest = lastHello,
               latest.pixelsWide != target.pixelsWide || latest.pixelsHigh != target.pixelsHigh {
                target = latest   // rotated again while we were rebuilding
                continue
            }
            return
        }
    }

    /// The virtual display takes a moment to show up in shareable content.
    private func findSCDisplay(id: CGDirectDisplayID) async throws -> SCDisplay {
        for _ in 0..<20 {
            let content = try await SCShareableContent.current
            if let display = content.displays.first(where: { $0.displayID == id }) {
                return display
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw NSError(domain: "MacSender", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "虚拟显示器未出现在 ScreenCaptureKit 可捕获列表中"])
    }

    private func startCapture(display: SCDisplay, pixelsWide: Int, pixelsHigh: Int,
                              fps: Int, virtualDisplayRefreshRate: Int,
                              codec: StreamCodec) async throws {
        let filter = SCContentFilter(display: display, excludingWindows: [])

        let captureFps = RefreshRatePolicy.sanitize(fps)
        requestedCaptureFps = captureFps
        actualVirtualDisplayRefreshRate = RefreshRatePolicy.sanitize(virtualDisplayRefreshRate)
        lastCaptureFpsWarningAt = Date.distantPast

        let config = SCStreamConfiguration()
        config.width = pixelsWide
        config.height = pixelsHigh
        config.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(RefreshRatePolicy.captureIntervalTimescale(fps: captureFps)))
        // 420v matches the encoder's native input — skips a BGRA→YUV conversion
        // inside VideoToolbox. (`-pixfmt bgra` reverts for A/B testing.)
        config.pixelFormat = UserDefaults.standard.string(forKey: "pixfmt") == "bgra"
            ? kCVPixelFormatType_32BGRA
            : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        // One buffer is held permanently (keyframe replay) and one sits in
        // the encoder for ~13ms — headroom prevents SCK starvation drops.
        config.queueDepth = 8
        config.showsCursor = !localCursor

        setupEncoder(width: pixelsWide, height: pixelsHigh, fps: captureFps, preferredCodec: codec)
        activeStreamWidth = pixelsWide
        activeStreamHeight = pixelsHigh
        sendStreamConfig(width: pixelsWide, height: pixelsHigh)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
        captureDisplayID = display.displayID
        lastCursorPNGHash = 0      // rotation rebuilds: re-send the sprite
        lastCursorSent = (-1, -1, false)
        startCursorEcho()
        Log.info("capture started: \(pixelsWide)x\(pixelsHigh) display \(display.displayID) mode \(mode.rawValue) requestedCaptureFps=\(captureFps) actualVirtualDisplayRefreshRate=\(actualVirtualDisplayRefreshRate) codec=\(streamCodec.rawValue) bitrate=\(streamBitrate) minimumFrameInterval=1/\(RefreshRatePolicy.captureIntervalTimescale(fps: captureFps)) localCursor=\(localCursor)")
        let kind = lastHello?.kind ?? "设备"
        await status("\(mode == .extend ? "正在扩展到" : "正在镜像到") \(kind)（\(pixelsWide)×\(pixelsHigh)）")
    }

    @MainActor
    func stop() {
        stopped = true
        cursorTimer?.cancel()
        cursorTimer = nil
        cursorImageTimer?.cancel()
        cursorImageTimer = nil
        stream?.stopCapture { _ in }
        stream = nil
        connection?.cancel()
        connection = nil
        if let encoder { VTCompressionSessionInvalidate(encoder) }
        encoder = nil
        TestPattern.hide(ownerID: testPatternOwnerID)
        virtualDisplay = nil   // releasing it removes the display
        queue.async { [weak self] in
            self?.finishBenchmarkOnQueue(message: "Benchmark stopped with session")
            // Unblock a start() that is still waiting for the hello.
            self?.helloContinuation?.resume(throwing: CancellationError())
            self?.helloContinuation = nil
        }
    }

    @MainActor
    func startBenchmark(scene: BenchmarkScene, duration: BenchmarkDuration) throws {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DisplayWeave/Benchmarks", isDirectory: true)
        let recorder = BenchmarkRecorder(rootURL: root)
        let runId = UUID().uuidString.lowercased()
        try recorder.start(runId: runId)
        queue.sync {
            finishBenchmarkOnQueue(message: nil)
            benchmarkRecorder = recorder
            benchmarkStartedAt = benchmarkClock.now
            benchmarkPhasePolicy = BenchmarkPhasePolicy(runSeconds: TimeInterval(duration.rawValue))
            benchmarkRunId = runId
            benchmarkSessionId = UUID().uuidString.lowercased()
            benchmarkScene = scene
            benchmarkOutputDirectory = root.appendingPathComponent(runId, isDirectory: true)
            let finish = DispatchWorkItem { [weak self] in
                self?.finishBenchmarkOnQueue(message: "Benchmark completed")
            }
            benchmarkFinishWorkItem = finish
            queue.asyncAfter(
                deadline: .now() + 30 + TimeInterval(duration.rawValue), execute: finish)
        }
        Task { @MainActor in
            onBenchmarkStatus?("Warm-up 30s · \(scene.label) · run \(runId)")
        }
    }

    @MainActor
    func stopBenchmark() {
        queue.async { [weak self] in self?.finishBenchmarkOnQueue(message: "Benchmark stopped") }
    }

    @MainActor
    var isBenchmarkActive: Bool {
        queue.sync { benchmarkRecorder != nil }
    }

    /// Drop the current connection and dial again — fresh TCP through the
    /// tunnel, fresh accept on the phone. Bound to the UI Reconnect button.
    func forceReconnect() {
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            Log.info("manual reconnect requested")
            self.disconnectedSince = Date()   // fresh grace window
            self.scheduleReconnect()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.info("stream stopped with error: \(error)")
        Task { await status("捕获已停止：\(error.localizedDescription)") }
        // E.g. display sleep can tear the virtual display down underneath the
        // stream — rebuild instead of sitting dead until an app restart.
        guard !stopped, mode == .extend else { return }
        self.stream = nil
        scheduleCaptureRecovery()
    }

    /// Retry until capture is back (a rebuild during display sleep can fail).
    private func scheduleCaptureRecovery() {
        queue.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, !self.stopped, self.stream == nil,
                  let hello = self.lastHello else { return }
            Log.info("capture died — rebuilding pipeline")
            Task {
                await self.reconfigure(hello)
                self.queue.async {
                    if self.stream == nil { self.scheduleCaptureRecovery() }
                }
            }
        }
    }

    // MARK: - Connection (with retry)

    // Guards against a stale async USB dial adopting after a newer one (or a
    // manual reconnect) superseded it. Only touched on `queue`.
    private var dialGeneration = 0

    private func connect() {
        guard !stopped else { return }
        switch transport {
        case .tcp(let endpoint): connectTCP(endpoint)
        case .usb(let udid, let port): connectUSB(udid: udid, port: port)
        case .androidAdb(let port):
            connectTCP(.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!))
        }
    }

    /// Bookkeeping shared by both transports once a connection is live.
    private func becomeReady(_ conn: NWConnection) {
        Log.info("connection ready to \(endpointName)")
        connectionReady = true
        wireConnectionGeneration &+= 1
        protocolIdentity.beginConnection()
        everConnected = true
        let hasConfiguredStream = encoder != nil
            && activeStreamWidth > 0 && activeStreamHeight > 0
        for action in ReconnectHandshakePolicy.actions(
            hasConfiguredStream: hasConfiguredStream) {
            switch action {
            case .sendStreamConfig:
                sendStreamConfig(width: activeStreamWidth, height: activeStreamHeight)
            case .forceKeyframe:
                requestKeyframe(.reconnect)   // new peer needs SPS/PPS + IDR
            }
        }
        // A reconnect can recreate the phone's video view with no cursor
        // sprite; the sprite is otherwise only sent on shape change, so the
        // cursor would stay invisible until the user hovers something that
        // changes it. Reset the dedup state to re-send sprite + position to
        // the fresh peer — the cursor analogue of forcing a keyframe.
        lastCursorPNGHash = 0
        lastCursorSent = (-1, -1, false)
        lastReceived = Date()  // fresh grace period for the watchdog
        receiveControl(on: conn)
        Task { await self.status("正在连接到 \(self.endpointName)…") }
    }

    private func connectTCP(_ endpoint: NWEndpoint) {
        let options = NWProtocolTCP.Options()
        options.noDelay = true   // latency matters more than throughput here
        let params = NWParameters(tls: nil, tcp: options)
        let conn = NWConnection(to: endpoint, using: params)
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.becomeReady(conn)
            case .failed(let error):
                Log.info("connection failed: \(error)")
                self.connectionReady = false
                self.scheduleReconnect()
            case .waiting(let error):
                // On loopback there is no "path change" to wake us up again
                // (e.g. a manual -host tunnel not started yet) — treat
                // waiting as failure and poll by reconnecting.
                Log.info("connection waiting: \(error) — will retry")
                self.connectionReady = false
                Task { await self.status("正在等待 \(self.endpointName) 上的接收端…") }
                self.scheduleReconnect()
            case .cancelled:
                self.connectionReady = false
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    /// Dial through macOS's built-in usbmuxd — no external tunnel needed.
    /// The handshake is async, so adoption is gated on `dialGeneration`.
    private func connectUSB(udid: String?, port: UInt16) {
        dialGeneration += 1
        let generation = dialGeneration
        Task { [weak self] in
            guard let self else { return }
            do {
                let conn = try await Usbmux.dial(udid: udid, port: port, queue: queue)
                queue.async {
                    guard generation == self.dialGeneration, !self.stopped else {
                        conn.cancel()
                        return
                    }
                    self.connection = conn
                    conn.stateUpdateHandler = { [weak self] state in
                        guard let self else { return }
                        switch state {
                        case .failed(let error):
                            Log.info("usb connection failed: \(error)")
                            self.connectionReady = false
                            self.scheduleReconnect()
                        case .cancelled:
                            self.connectionReady = false
                        default:
                            break
                        }
                    }
                    self.becomeReady(conn)
                }
            } catch {
                // Distinct guidance per failure: cable missing vs app closed.
                let hint: String
                switch error as? Usbmux.Failure {
                case .noDevice:
                    hint = "正在等待 USB 设备，请连接 iPhone 或 iPad…"
                case .refused:
                    hint = "已发现设备，请在设备上打开 DisplayWeave…"
                default:
                    Log.info("usb dial failed: \(error)")
                    hint = "USB 连接失败：\(error.localizedDescription)"
                }
                queue.async {
                    guard generation == self.dialGeneration, !self.stopped else { return }
                    Task { await self.status(hint) }
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard !stopped else { return }
        if everConnected {
            if let since = disconnectedSince {
                if Date().timeIntervalSince(since) > disconnectGraceSeconds {
                    Log.info("device gone for >\(Int(disconnectGraceSeconds))s — ending session")
                    Task { @MainActor in self.onDisconnected?() }
                    return
                }
            } else {
                disconnectedSince = Date()
                Task { await status("连接已断开，正在重试 \(Int(disconnectGraceSeconds)) 秒…") }
            }
        }
        connectionReady = false
        dialGeneration += 1   // a USB dial still in flight must not adopt
        connection?.cancel()
        connection = nil
        pendingSends = 0
        pendingSendStartedAt.removeAll()
        queue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.connect()
        }
    }

    // MARK: - Liveness (ping + watchdog)

    private func scheduleLocalCongestionCheck() {
        queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, !self.stopped else { return }
            let timestamp = ProcessInfo.processInfo.systemUptime
            let elapsed = max(timestamp - self.localCongestionWindowStart, 0.001)
            let encodedFps = Double(self.localEncodedFrames) / elapsed
            let sentFps = Double(self.localSentFrames) / elapsed
            let oldestPendingAgeMs = self.pendingSendStartedAt.values.min().map {
                max(0, (timestamp - $0) * 1_000)
            } ?? 0
            self.lastLocalOldestPendingSendAgeMs = oldestPendingAgeMs
            self.lastLocalEncodedFps = encodedFps
            self.lastLocalSentFps = sentFps
            self.localEncodedFrames = 0
            self.localSentFrames = 0
            self.localCongestionWindowStart = timestamp

            if self.connectionReady, let controller = self.adaptiveBitrateController,
               let decision = controller.evaluateLocal(
                LocalCongestionMetrics(
                    timestamp: timestamp,
                    pendingSends: self.pendingSends,
                    queueBudget: self.maxPendingSends,
                    oldestPendingSendAgeMs: oldestPendingAgeMs,
                    encodedFps: encodedFps,
                    sentFps: sentFps,
                    sendCompletionDelayMs: self.lastSendCompletionDelayMs),
                mode: self.settings.bitrateMode) {
                self.applyAdaptiveDecision(decision)
            }
            self.scheduleLocalCongestionCheck()
        }
    }

    private func schedulePing() {
        queue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, !self.stopped else { return }
            if self.connectionReady {
                // Liveness + send-side health for the phone's overlay.
                let elapsed = Date().timeIntervalSince(self.capWindowStart)
                let capFps = elapsed > 0 ? Int(Double(self.capFrames) / elapsed) : 0
                self.lastCaptureFps = capFps
                if let virtualDisplay = self.virtualDisplay {
                    Task { @MainActor [weak self, weak virtualDisplay] in
                        guard let self, let virtualDisplay else { return }
                        let refreshed = virtualDisplay.refreshActualRefreshRate()
                        self.queue.async { [weak self] in
                            self?.actualVirtualDisplayRefreshRate = refreshed
                        }
                    }
                }
                self.capFrames = 0
                self.capWindowStart = Date()
                self.logCaptureFpsIfLimited(actualFps: capFps)
                let sorted = self.inputLatencies.sorted()
                let inp50 = sorted.isEmpty ? 0 : sorted[sorted.count / 2].rounded()
                let inp95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))].rounded()
                let stats = StreamDebugStats(
                    droppedFramesMac: self.dropsThisWindow,
                    queueDepthMac: self.pendingSends,
                    captureFps: capFps,
                    requestedFps: self.requestedCaptureFps,
                    actualVirtualDisplayRefreshRate: self.actualVirtualDisplayRefreshRate,
                    encodedFps: self.lastEncodedFps,
                    sentFps: self.lastSentFps,
                    averageFrameSize: self.lastAverageFrameSize,
                    encodeLatencyMs: self.lastEncodeLatencyMs,
                    bitrate: self.streamBitrate,
                    inputP50Ms: inp50,
                    inputP95Ms: inp95)
                self.sendJSONFrame(stats.pingJson(nowMs: Date().timeIntervalSince1970 * 1000))
                self.lastMacDropsSnapshot = self.dropsThisWindow
                self.dropsThisWindow = 0
            }
            self.schedulePing()
        }
    }

    private func logCaptureFpsIfLimited(actualFps: Int) {
        guard requestedCaptureFps >= 90, actualFps > 0,
              actualFps < requestedCaptureFps - 15,
              Date().timeIntervalSince(lastCaptureFpsWarningAt) > 10 else { return }
        lastCaptureFpsWarningAt = Date()
        let likely = [
            "virtual display actual refresh=\(actualVirtualDisplayRefreshRate)Hz",
            "ScreenCaptureKit may be rate limiting",
            "WindowServer may not be producing \(requestedCaptureFps)Hz frames",
            "encoder may be blocking",
            "transport/backpressure pending=\(pendingSends)"
        ].joined(separator: "; ")
        Log.info("capture fps below request: requested=\(requestedCaptureFps) actual=\(actualFps). Possible causes: \(likely)")
    }

    private func scheduleWatchdog() {
        queue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, !self.stopped else { return }
            if self.connectionReady, Date().timeIntervalSince(self.lastReceived) > 5 {
                Log.info("watchdog: nothing from the phone for >5s — reconnecting")
                Task { await self.status("连接无响应，正在重新连接…") }
                self.scheduleReconnect()
            }
            // A reconnect on a static screen produces no capture frames, so
            // the receiver would stay black — replay the last frame as IDR.
            if self.connectionReady, self.needsKeyframe,
               Date().timeIntervalSince(self.lastCaptureAt) > 1,
               let pixelBuffer = self.lastPixelBuffer {
                Log.info("static screen after reconnect — replaying last frame as keyframe")
                self.encode(pixelBuffer, pts: CMClockGetTime(CMClockGetHostTimeClock()))
            }
            self.scheduleWatchdog()
        }
    }

    // MARK: - Local cursor echo (Mac -> phone)

    private func startCursorEcho() {
        guard localCursor else { return }
        cursorTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(8))   // 120Hz
        timer.setEventHandler { [weak self] in self?.pollCursorPosition() }
        timer.resume()
        cursorTimer = timer
        scheduleCursorImagePoll()
    }

    /// Sprite changes (arrow ↔ I-beam ↔ resize…) must land fast or the wrong
    /// cursor shows over hot areas — poll at 30Hz on the main thread (NSCursor
    /// is AppKit), hash the raw bitmap, and only PNG-encode + send on change.
    ///
    /// A dedicated timer (cancelled+replaced here, like cursorTimer above) — not
    /// a self-rescheduling asyncAfter chain. Every rebuild re-enters
    /// startCursorEcho, and sleep/wake rebuilds happen often; a recursive chain
    /// guarded only by `stopped` would stack one extra 30Hz main-thread
    /// TIFF-encode loop per rebuild, creeping CPU to ~50% until a restart (#75).
    private func scheduleCursorImagePoll() {
        cursorImageTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.033, repeating: .milliseconds(33))
        timer.setEventHandler { [weak self] in
            guard let self, !self.stopped, self.localCursor else { return }
            self.pollCursorImage()
        }
        timer.resume()
        cursorImageTimer = timer
    }

    private func pollCursorPosition() {
        guard connectionReady, captureDisplayID != 0,
              let loc = CGEvent(source: nil)?.location else { return }
        let bounds = CGDisplayBounds(captureDisplayID)
        guard bounds.width > 0, bounds.height > 0 else { return }
        if bounds.contains(loc) {
            let x = (loc.x - bounds.minX) / bounds.width
            let y = (loc.y - bounds.minY) / bounds.height
            if !lastCursorSent.visible
                || abs(x - lastCursorSent.x) > 0.0004 || abs(y - lastCursorSent.y) > 0.0004 {
                lastCursorSent = (x, y, true)
                sendJSONFrame(String(format: "{\"type\":\"cursor\",\"x\":%.4f,\"y\":%.4f,\"v\":1}", x, y))
            }
        } else if lastCursorSent.visible {
            lastCursorSent.visible = false
            sendJSONFrame("{\"type\":\"cursor\",\"v\":0}")
        }
    }

    private func pollCursorImage() {
        // Display size read LIVE, not snapshotted at capture start: the
        // HiDPI mode settles (and macOS re-flips it) asynchronously, and a
        // sprite normalized against the 1x size renders at half size on the
        // device. Mixing the size into the dedup hash re-sends the sprite
        // whenever the mode flips, so the proportion always heals.
        guard connectionReady, captureDisplayID != 0,
              let cursor = NSCursor.currentSystem else { return }
        let displaySize = CGDisplayBounds(captureDisplayID).size   // points, current mode
        guard displaySize.width > 0, displaySize.height > 0 else { return }
        let image = cursor.image
        guard let tiff = image.tiffRepresentation else { return }
        let hash = tiff.hashValue ^ Int(displaySize.width) &* 31
        guard hash != lastCursorPNGHash else { return }
        guard let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]),
              png.count < 24_000 else { return }
        lastCursorPNGHash = hash
        let size = image.size            // Mac points
        let hot = cursor.hotSpot
        // Normalized against the display so the phone can size/anchor the
        // sprite without knowing capture scale or HiDPI factor.
        let msg = String(format:
            "{\"type\":\"cursorImg\",\"nw\":%.5f,\"nh\":%.5f,\"ax\":%.3f,\"ay\":%.3f,\"png\":\"%@\"}",
            size.width / displaySize.width,
            size.height / displaySize.height,
            size.width > 0 ? hot.x / size.width : 0,
            size.height > 0 ? hot.y / size.height : 0,
            png.base64EncodedString())
        queue.async { self.sendJSONFrame(msg) }
    }

    // MARK: - Control messages (phone -> Mac)

    private func receiveControl(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard error == nil, let data, data.count == 4 else {
                self.handleControlReadEnd(on: conn, isComplete: isComplete, error: error)
                return
            }
            let len = Int(UInt32(bigEndian: data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
            guard len > 0, len < 1 << 20 else { return }
            conn.receive(minimumIncompleteLength: len, maximumLength: len) { [weak self] payload, _, isComplete, error in
                guard let self else { return }
                guard error == nil, let payload, payload.count == len else {
                    self.handleControlReadEnd(on: conn, isComplete: isComplete, error: error)
                    return
                }
                self.handleControl(payload)
                self.receiveControl(on: conn)
            }
        }
    }

    private func handleControlReadEnd(on conn: NWConnection, isComplete: Bool,
                                      error: NWError?) {
        guard !stopped, connection === conn else { return }
        let event: ConnectionClosureEvent = isComplete && error == nil ? .cleanEnd : .failure
        handleConnectionClosure(ConnectionClosurePolicy.action(
            for: event,
            peer: receiverPeerKind
        ))
    }

    private var receiverPeerKind: ReceiverPeerKind {
        guard let lastHello else { return .unknown }
        return lastHello.isAndroidReceiver ? .android : .legacyApple
    }

    private func handleConnectionClosure(_ action: ConnectionClosureAction) {
        switch action {
        case .endSession:
            Log.info("receiver closed the connection cleanly — ending session")
            finishSessionAfterReceiverExit()
        case .retryWithinGrace:
            scheduleReconnect()
        }
    }

    private func handleControl(_ payload: Data) {
        lastReceived = Date()
        if ReconnectPeerReadinessPolicy.clearsDisconnectGrace(for: .peerMessage) {
            disconnectedSince = nil
        }
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let type = obj["type"] as? String else {
            Log.info("unparseable control message (\(payload.count) bytes)")
            return
        }
        if let action = ReceiverControlPolicy.closureAction(
            messageType: type,
            peer: receiverPeerKind
        ) {
            Log.info("receiver sent goodbye — closure action=\(action)")
            handleConnectionClosure(action)
            return
        }
        switch type {
        case "ping":
            // Echo with our clock so the phone can estimate the offset
            // (NTP-style) and compute true end-to-end frame latency.
            if let t = obj["t"] as? Double {
                let received = Date().timeIntervalSince1970 * 1000
                let sent = Date().timeIntervalSince1970 * 1000
                if let pong = try? BenchmarkControlPolicy.pongData(
                    pingTimestamp: t,
                    macReceivedTimestamp: received,
                    macSentTimestamp: sent) {
                    sendJSONFrame(String(decoding: pong, as: UTF8.self))
                }
            }
        case "stats":
            // Aggregated pipeline health measured on the phone — logged here
            // so one file holds both ends of the story.
            if let json = try? JSONSerialization.data(withJSONObject: obj),
               let line = String(data: json, encoding: .utf8) {
                Log.info("PHONE-STATS \(line) | mac drops=\(dropsThisWindow) pending=\(pendingSends)")
            }
            if let receiver = try? BenchmarkControlPolicy.receiverStats(from: payload) {
                updateAdaptiveBitrate(receiver: receiver)
                appendBenchmarkSample(receiver: receiver)
            }
        case "hello":
            if let info = try? JSONDecoder().decode(PhoneInfo.self, from: payload) {
                let previous = lastHello
                lastHello = info
                if info.supportsProtocolV2 {
                    Task { await self.status("正在协商视频配置…") }
                    if previous?.supportsProtocolV2 != true,
                       encoder != nil, activeStreamWidth > 0, activeStreamHeight > 0 {
                        sendStreamConfig(width: activeStreamWidth, height: activeStreamHeight)
                        requestKeyframe(.streamReconfigure)
                    }
                } else {
                    Task { await self.status("已连接到 \(self.endpointName)") }
                }
                Task { @MainActor in self.onHello?(info) }
                if let continuation = helloContinuation {
                    helloContinuation = nil
                    continuation.resume(returning: info)
                } else if mode == .extend, stream != nil, let previous,
                          previous.pixelsWide != info.pixelsWide
                          || previous.pixelsHigh != info.pixelsHigh {
                    // Phone rotated — rebuild after a short debounce so a
                    // flurry of orientation flips settles into one rebuild.
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard let current = self.lastHello,
                              current.pixelsWide == info.pixelsWide,
                              current.pixelsHigh == info.pixelsHigh else { return }
                        await self.reconfigure(info)
                    }
                }
            }
        case "streamConfigAck", "decoderReady", "firstFrameRendered":
            handleReceiverProtocolProgress(type: type, object: obj)
        case "connectionState":
            let state = obj["state"] as? String ?? "unknown"
            let reason = obj["reason"] as? String ?? ""
            Log.info("receiver connection state=\(state) reason=\(reason)")
        case "touch":
            if let phase = obj["phase"] as? String,
               let x = obj["x"] as? Double,
               let y = obj["y"] as? Double {
                inputInjector?.handleTouch(phase: phase, x: x, y: y)
                if let t = obj["t"] as? Double {
                    let delta = Date().timeIntervalSince1970 * 1000 - t
                    if delta > -50, delta < 1000 {
                        inputLatencies.append(max(delta, 0))
                        if inputLatencies.count > 240 { inputLatencies.removeFirst(120) }
                    }
                }
            }
        case "scroll":
            if let dx = obj["dx"] as? Double, let dy = obj["dy"] as? Double {
                inputInjector?.handleScroll(dx: dx, dy: dy)
            }
        case "kf":
            // The phone's decoder lost sync (e.g. it attached mid-GOP and
            // periodic keyframes are off) — force an IDR on the next frame.
            Log.info("phone requested keyframe")
            decoderRecoveryEvent = "receiver-kf"
            let actions = ReceiverDecoderRecoveryPolicy.actions(
                negotiatedV2: lastHello?.supportsProtocolV2 == true,
                streamConfigRequired: obj["streamConfigRequired"] as? Bool == true
            )
            for action in actions {
                switch action {
                case .resendStreamConfig:
                    sendStreamConfig(
                        width: activeStreamWidth,
                        height: activeStreamHeight
                    )
                case .forceKeyframe:
                    requestKeyframe(.receiverKeyframeRequest)
                }
            }
        case "codecFailure":
            let failedCodec = (obj["codec"] as? String)?.lowercased() ?? "unknown"
            let message = obj["message"] as? String ?? "unspecified codec failure"
            Log.info("phone reported codec failure: codec=\(failedCodec) message=\(message)")
            if failedCodec == StreamCodec.hevc.rawValue, streamCodec == .hevc {
                decoderRecoveryEvent = "codec-fallback"
                if let encoder { VTCompressionSessionInvalidate(encoder) }
                encoder = nil
                setupEncoder(width: max(activeStreamWidth, 2),
                             height: max(activeStreamHeight, 2),
                             fps: requestedCaptureFps,
                             preferredCodec: .h264)
                sendStreamConfig(width: activeStreamWidth, height: activeStreamHeight)
                requestKeyframe(.codecFallback)
            }
        default:
            Log.info("unknown control message type: \(type)")
        }
    }

    private func finishSessionAfterReceiverExit() {
        connectionReady = false
        connection?.cancel()
        connection = nil
        Task { @MainActor in self.onDisconnected?() }
    }

    private func handleReceiverProtocolProgress(type: String, object: [String: Any]) {
        guard lastHello?.supportsProtocolV2 == true,
              let sessionEpoch = int64(object["sessionEpoch"]),
              let configVersion = int64(object["configVersion"]) else {
            return
        }
        if type == "streamConfigAck", object["accepted"] as? Bool != true {
            Log.info("receiver rejected stream config epoch=\(sessionEpoch) config=\(configVersion)")
            return
        }
        let frameSequence = int64(object["frameSequence"]) ?? 0
        let identity = StreamProtocolFrameIdentity(
            sessionEpoch: sessionEpoch,
            configVersion: configVersion,
            frameSequence: frameSequence)
        guard protocolHandshake.receive(type: type, identity: identity) else {
            Log.info("ignored stale/out-of-order receiver progress type=\(type) epoch=\(sessionEpoch) config=\(configVersion)")
            return
        }
        switch protocolHandshake.phase {
        case .awaitingDecoderReady:
            Task { await self.status("正在配置解码器…") }
        case .awaitingFirstFrame:
            Task { await self.status("等待首帧…") }
        case .streaming:
            protocolFailureBudget.markStreaming()
            Task { await self.status("已连接 / Streaming") }
        default:
            break
        }
        scheduleProtocolTimeout(identity: identity, phase: protocolHandshake.phase)
    }

    private func scheduleProtocolTimeout(
        identity: StreamProtocolFrameIdentity,
        phase: ReceiverProtocolHandshakePhase
    ) {
        let delay: TimeInterval
        switch phase {
        case .awaitingStreamConfigAck: delay = 1.5
        case .awaitingDecoderReady: delay = 2.0
        case .awaitingFirstFrame: delay = 3.0
        default: return
        }
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  self.connectionReady,
                  self.protocolHandshake.identity?.sessionEpoch == identity.sessionEpoch,
                  self.protocolHandshake.identity?.configVersion == identity.configVersion,
                  self.protocolHandshake.phase == phase else { return }
            switch self.protocolHandshake.timeoutAction() {
            case .retry:
                Log.info("receiver protocol timeout phase=\(phase); retrying stream config")
                Task { await self.status("接收端响应超时，正在有限重试…") }
                self.requestKeyframe(.decoderReset)
                self.sendStreamConfig(
                    width: self.activeStreamWidth,
                    height: self.activeStreamHeight,
                    protocolRetry: true)
            case .fail:
                Log.info("receiver protocol timeout phase=\(phase); retry budget exhausted")
                switch self.protocolFailureBudget.failureAction() {
                case .reconnect:
                    Task { await self.status("接收端协商失败，正在进行最后一次重连…") }
                    self.scheduleReconnect()
                case .endSession:
                    Task { await self.status("接收端协商失败，已停止重试") }
                    self.finishSessionAfterReceiverExit()
                }
            case .none:
                break
            }
        }
    }

    private func int64(_ value: Any?) -> Int64? {
        (value as? NSNumber)?.int64Value
    }

    private func waitForHello() async throws -> PhoneInfo {
        if let lastHello { return lastHello }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let hello = self.lastHello {
                    continuation.resume(returning: hello)
                } else {
                    self.helloContinuation = continuation
                }
            }
        }
    }

    // MARK: - Encoder setup

    private func setupEncoder(width: Int, height: Int, fps: Int, preferredCodec: StreamCodec) {
        let finalFps = RefreshRatePolicy.sanitize(fps)
        streamCodec = preferredCodec
        let automaticBitrate = StreamEncodingPolicy.bitrate(
            width: width, height: height, fps: finalFps, codec: preferredCodec,
            quality: quality)
        streamBitrate = selectedBitrate(automatic: automaticBitrate, codec: preferredCodec)
        encodedFramesWindow = 0
        encodedBytesWindow = 0
        localEncodedFrames = 0
        localSentFrames = 0
        localCongestionWindowStart = ProcessInfo.processInfo.systemUptime
        lastLocalOldestPendingSendAgeMs = 0
        lastLocalEncodedFps = 0
        lastLocalSentFps = 0
        lastSendCompletionDelayMs = 0
        encodeLatencyMsWindow.removeAll(keepingCapacity: true)
        encodeStatsWindowStart = Date()

        // Low-latency rate control: the hardware encoder emits every frame
        // immediately instead of pipelining. (`-lowlatency NO` for A/B.)
        let lowLatency = UserDefaults.standard.object(forKey: "lowlatency") == nil
            || UserDefaults.standard.bool(forKey: "lowlatency")
        let spec: CFDictionary? = lowLatency
            ? [kVTVideoEncoderSpecification_EnableLowLatencyRateControl: kCFBooleanTrue] as CFDictionary
            : nil
        var created = createEncoder(width: width, height: height, codec: preferredCodec, spec: spec)
        if created == nil, preferredCodec == .hevc {
            Log.info("HEVC encoder unavailable; falling back to H.264")
            streamCodec = .h264
            let fallbackAutomatic = StreamEncodingPolicy.bitrate(
                width: width, height: height, fps: finalFps, codec: .h264,
                quality: quality)
            streamBitrate = selectedBitrate(automatic: fallbackAutomatic, codec: .h264)
            created = createEncoder(width: width, height: height, codec: .h264, spec: spec)
        }
        encoder = created
        guard let encoder else {
            Log.info("FATAL: VTCompressionSessionCreate failed")
            return
        }
        // Low-latency settings: real-time, no B-frames, periodic keyframes.
        VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        let profile: CFString = streamCodec == .hevc
            ? kVTProfileLevel_HEVC_Main_AutoLevel
            : kVTProfileLevel_H264_High_AutoLevel
        VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_ProfileLevel, value: profile)
        VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                             value: KeyframePolicy.frameInterval(
                                fps: finalFps, transport: bitrateTransport) as CFNumber)
        VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,
                             value: KeyframePolicy.defaultSeconds(transport: bitrateTransport) as CFNumber)
        VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: 0 as CFNumber)
        VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_AverageBitRate, value: streamBitrate as CFNumber)
        let bytesPerSecond = max(streamBitrate / 8, 1)
        VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_DataRateLimits,
                             value: [bytesPerSecond, 1] as CFArray)
        VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: finalFps as CFNumber)
        VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, value: kCFBooleanTrue)
        VTCompressionSessionPrepareToEncodeFrames(encoder)
        adaptiveBitrateController = settings.bitrateMode == .auto
            ? AdaptiveBitrateController(
                initialBitrate: streamBitrate,
                bounds: StreamEncodingPolicy.bitrateBounds(
                    codec: streamCodec, transport: bitrateTransport))
            : nil
        lastAdaptiveDecision = nil
        Task { @MainActor in onTargetBitrate?(Double(streamBitrate) / 1_000_000) }
        Log.info("encoder ready: \(width)x\(height) \(streamCodec.label) fps=\(finalFps) bitrate=\(streamBitrate / 1_000_000)Mbps keyframeInterval=\(KeyframePolicy.frameInterval(fps: finalFps, transport: bitrateTransport)) quality=\(quality.rawValue) lowLatencyRC=\(lowLatency)")
    }

    private func createEncoder(width: Int, height: Int, codec: StreamCodec,
                               spec: CFDictionary?) -> VTCompressionSession? {
        var session: VTCompressionSession?
        let codecType: CMVideoCodecType = codec == .hevc
            ? kCMVideoCodecType_HEVC
            : kCMVideoCodecType_H264
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: Int32(width), height: Int32(height),
            codecType: codecType,
            encoderSpecification: spec,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        guard status == noErr else {
            Log.info("VTCompressionSessionCreate failed for \(codec.label): \(status)")
            return nil
        }
        return session
    }

    // MARK: - Capture callback

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen,
              CMSampleBufferIsValid(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        lastPixelBuffer = pixelBuffer
        lastCaptureAt = Date()
        capFrames += 1

        // No receiver, or the socket is backed up: skip this frame entirely.
        guard connectionReady else { return }
        let queueDecision = SendQueuePolicy.decision(
            pendingSends: pendingSends, budget: maxPendingSends,
            currentDroppedFrames: dropsThisWindow)
        if queueDecision.shouldDrop {
            if queueDecision.forceKeyframe, let reason = queueDecision.reason {
                requestKeyframe(reason)
            }
            dropsThisWindow = queueDecision.droppedFrames
            dropsTotal += 1
            return
        }

        encode(pixelBuffer, pts: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }

    private func encode(_ pixelBuffer: CVPixelBuffer, pts: CMTime) {
        guard let encoder else { return }
        let capturedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        let encodedForWireGeneration = wireConnectionGeneration
        let protocolFrameIdentity = lastHello?.supportsProtocolV2 == true
            ? protocolIdentity.nextFrame()
            : nil
        var frameProperties: CFDictionary?
        let forcedKeyframeReason = keyframeRequests.consumePendingRequest()
        if let forcedKeyframeReason {
            frameProperties = [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue!] as CFDictionary
            decoderRecoveryEvent = forcedKeyframeReason.rawValue
            Log.info("forcing keyframe reason=\(forcedKeyframeReason.rawValue) requests=\(keyframeRequests.requestCount) coalesced=\(keyframeRequests.coalescedCount)")
        }
        let encodeStart = Date()
        let duration = CMTime(
            value: 1,
            timescale: CMTimeScale(StreamEncodingPolicy.frameDurationTimescale(fps: requestedCaptureFps)))
        VTCompressionSessionEncodeFrame(
            encoder,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: duration,
            frameProperties: frameProperties,
            infoFlagsOut: nil
        ) { [weak self] status, _, buffer in
            guard let self else { return }
            self.queue.async {
                self.handleEncodedFrame(
                    status: status,
                    buffer: buffer,
                    forcedKeyframeReason: forcedKeyframeReason,
                    capturedAtMs: capturedAtMs,
                    encodedForWireGeneration: encodedForWireGeneration,
                    protocolFrameIdentity: protocolFrameIdentity,
                    encodeStart: encodeStart)
            }
        }
    }

    private func handleEncodedFrame(
        status: OSStatus,
        buffer: CMSampleBuffer?,
        forcedKeyframeReason: FrameDropReason?,
        capturedAtMs: Int64,
        encodedForWireGeneration: UInt64,
        protocolFrameIdentity: StreamProtocolFrameIdentity?,
        encodeStart: Date
    ) {
        guard status == noErr, let buffer else {
            if forcedKeyframeReason != nil {
                keyframeRequests.completeInFlightRequest(encodedKeyframe: false)
            }
            handleEncodeFailure(status: status)
            return
        }
        let isKeyframe = Self.isKeyframe(buffer)
        if forcedKeyframeReason != nil {
            keyframeRequests.completeInFlightRequest(encodedKeyframe: isKeyframe)
        }
        guard connectionReady,
              encodedForWireGeneration == wireConnectionGeneration else {
            Log.info("dropping encoded frame from stale wire connection generation")
            return
        }
        guard let data = annexB(from: buffer) else {
            requestKeyframe(.encodedFrameDiscarded)
            return
        }
        let sndMs = Int64(Date().timeIntervalSince1970 * 1000)
        let framed: Data
        do {
            framed = try VideoFrameWirePayload.encode(
                annexB: data,
                codec: streamCodec,
                isKeyframe: isKeyframe,
                captureTimestampMs: capturedAtMs,
                sendTimestampMs: sndMs,
                identity: protocolFrameIdentity,
                binaryHeaderEnabled: protocolFrameIdentity?.sessionEpoch
                    == protocolIdentity.sessionEpoch
                    && lastHello?.supportsBinaryFrameHeaderV2 == true)
        } catch {
            Log.info("video frame wire encode failed: \(error)")
            requestKeyframe(.encodedFrameDiscarded)
            return
        }
        recordEncodedFrame(
            bytes: data.count,
            isKeyframe: isKeyframe,
            latencyMs: Date().timeIntervalSince(encodeStart) * 1000)
        sendFramed(framed)
    }

    private func handleEncodeFailure(status: OSStatus) {
        Log.info("encode failed for \(streamCodec.label): \(status)")
        guard streamCodec == .hevc else { return }
        Log.info("falling back to H.264 after HEVC encode failure")
        if let encoder { VTCompressionSessionInvalidate(encoder) }
        encoder = nil
        guard let lastPixelBuffer else { return }
        setupEncoder(width: max(2, CVPixelBufferGetWidth(lastPixelBuffer)),
                     height: max(2, CVPixelBufferGetHeight(lastPixelBuffer)),
                     fps: requestedCaptureFps,
                     preferredCodec: .h264)
        sendStreamConfig(width: max(activeStreamWidth, 2), height: max(activeStreamHeight, 2))
        requestKeyframe(.codecFallback)
    }

    private static func isKeyframe(_ sample: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sample, createIfNecessary: false) as? [[CFString: Any]],
              let first = attachments.first else { return false }
        return first[kCMSampleAttachmentKey_NotSync] == nil
    }

    private func recordEncodedFrame(bytes: Int, isKeyframe: Bool, latencyMs: Double) {
        localEncodedFrames += 1
        encodedFramesWindow += 1
        encodedBytesWindow += bytes
        peakFrameBytesWindow = max(peakFrameBytesWindow, bytes)
        if isKeyframe {
            keyframesWindow += 1
            keyframeBytesWindow += bytes
            keyframeQueueDepthWindow = max(keyframeQueueDepthWindow, pendingSends)
        }
        encodeLatencyMsWindow.append(latencyMs)
        let elapsed = Date().timeIntervalSince(encodeStatsWindowStart)
        guard elapsed >= 1 else { return }
        let fps = Double(encodedFramesWindow) / elapsed
        let avgFrame = encodedFramesWindow > 0 ? encodedBytesWindow / encodedFramesWindow : 0
        let avgLatency = encodeLatencyMsWindow.isEmpty
            ? 0
            : encodeLatencyMsWindow.reduce(0, +) / Double(encodeLatencyMsWindow.count)
        lastEncodedFps = Int(fps.rounded())
        lastAverageFrameSize = avgFrame
        lastEncodeLatencyMs = avgLatency
        lastKeyframeCount = keyframesWindow
        lastAverageKeyframeSize = keyframesWindow > 0 ? keyframeBytesWindow / keyframesWindow : 0
        lastPeakFrameSize = peakFrameBytesWindow
        lastKeyframeQueueDepth = keyframeQueueDepthWindow
        if settings.enableDebugStats {
            let averageKeyframeSize = keyframesWindow > 0 ? keyframeBytesWindow / keyframesWindow : 0
            Log.info("ENC-STATS codec=\(streamCodec.rawValue) encodedFps=\(String(format: "%.1f", fps)) encodeLatencyMs=\(String(format: "%.1f", avgLatency)) bitrate=\(streamBitrate) keyframeInterval=\(KeyframePolicy.frameInterval(fps: requestedCaptureFps, transport: bitrateTransport)) keyframeCount=\(keyframesWindow) averageKeyframeSize=\(averageKeyframeSize) peakFrameSize=\(peakFrameBytesWindow) queueAtWindowEnd=\(pendingSends) averageFrameSize=\(avgFrame)")
        }
        encodedFramesWindow = 0
        encodedBytesWindow = 0
        encodeLatencyMsWindow.removeAll(keepingCapacity: true)
        keyframesWindow = 0
        keyframeBytesWindow = 0
        peakFrameBytesWindow = 0
        keyframeQueueDepthWindow = 0
        encodeStatsWindowStart = Date()
    }

    // MARK: - AVCC/HVCC -> Annex B

    private func annexB(from sample: CMSampleBuffer) -> Data? {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return nil }
        var len = 0, total = 0
        var ptr: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0,
                lengthAtOffsetOut: &len, totalLengthOut: &total,
                dataPointerOut: &ptr) == noErr, let ptr else { return nil }

        var out = Data(capacity: total + 128)
        // On keyframes, prepend codec parameter sets from the format description.
        if isKeyframe(sample), let fmt = CMSampleBufferGetFormatDescription(sample) {
            let count = parameterSetCount(from: fmt)
            for i in 0..<count {
                if let parameterSet = parameterSet(from: fmt, index: i) {
                    out.append(contentsOf: startCode)
                    out.append(parameterSet)
                }
            }
        }
        // Convert length-prefixed NALUs to Annex B start codes.
        let raw = UnsafeRawPointer(ptr)
        var offset = 0
        while offset + 4 <= total {
            var nalLen: UInt32 = 0
            memcpy(&nalLen, raw + offset, 4)
            nalLen = CFSwapInt32BigToHost(nalLen)
            offset += 4
            guard offset + Int(nalLen) <= total else { break }
            out.append(contentsOf: startCode)
            out.append(Data(bytes: raw + offset, count: Int(nalLen)))
            offset += Int(nalLen)
        }
        return out
    }

    private func parameterSetCount(from format: CMFormatDescription) -> Int {
        var count = 0
        let status: OSStatus
        if streamCodec == .hevc {
            status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                format, parameterSetIndex: 0, parameterSetPointerOut: nil,
                parameterSetSizeOut: nil, parameterSetCountOut: &count,
                nalUnitHeaderLengthOut: nil)
        } else {
            status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                format, parameterSetIndex: 0, parameterSetPointerOut: nil,
                parameterSetSizeOut: nil, parameterSetCountOut: &count,
                nalUnitHeaderLengthOut: nil)
        }
        return status == noErr ? count : 0
    }

    private func parameterSet(from format: CMFormatDescription, index: Int) -> Data? {
        var pointer: UnsafePointer<UInt8>?
        var size = 0
        let status: OSStatus
        if streamCodec == .hevc {
            status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                format, parameterSetIndex: index, parameterSetPointerOut: &pointer,
                parameterSetSizeOut: &size, parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil)
        } else {
            status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                format, parameterSetIndex: index, parameterSetPointerOut: &pointer,
                parameterSetSizeOut: &size, parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil)
        }
        guard status == noErr, let pointer else { return nil }
        return Data(bytes: pointer, count: size)
    }

    private func isKeyframe(_ sample: CMSampleBuffer) -> Bool {
        guard let arr = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false),
              let dict = (arr as? [[CFString: Any]])?.first else { return true }
        return !(dict[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
    }

    // MARK: - Wire framing: [4-byte big-endian length][payload]

    /// Control messages on the video channel (pong etc.) — framed JSON without
    /// start codes; the receiver routes payloads starting with '{'.
    private func sendJSONFrame(_ json: String) {
        guard let connection, connectionReady else { return }
        let payload = Data(json.utf8)
        var header = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &header, count: 4)
        frame.append(payload)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func sendStreamConfig(width: Int, height: Int, protocolRetry: Bool = false) {
        let transportName: String
        if case .androidAdb = transport {
            transportName = "usb"
        } else {
            transportName = lastHello?.negotiatedTransport ?? "unknown"
        }
        let identity: StreamProtocolFrameIdentity?
        if lastHello?.supportsProtocolV2 == true {
            identity = protocolIdentity.beginConfiguration()
            if let identity {
                if protocolRetry {
                    protocolHandshake.retrying(identity)
                } else {
                    protocolHandshake.begin(identity)
                }
            }
        } else {
            identity = nil
        }
        let message = StreamConfigMessage(
            codec: streamCodec,
            fps: requestedCaptureFps,
            width: width,
            height: height,
            bitrate: streamBitrate,
            transport: transportName,
            identity: identity,
            maxFrameBytes: lastHello?.negotiatedMaxFrameBytes)
        sendJSONFrame(message.json)
        if let identity {
            scheduleProtocolTimeout(identity: identity, phase: .awaitingStreamConfigAck)
        }
        Log.info("stream config sent: codec=\(streamCodec.rawValue) fps=\(requestedCaptureFps) width=\(width) height=\(height) bitrate=\(streamBitrate) profile=\(message.profile) transport=\(transportName) sessionEpoch=\(identity?.sessionEpoch ?? 0) configVersion=\(identity?.configVersion ?? 0)")
    }

    private func sendFramed(_ payload: Data) {
        guard let connection, connectionReady else { return }
        let negotiatedMaxBytes = lastHello?.negotiatedMaxFrameBytes
        guard FrameSizePolicy.permits(
            payloadBytes: payload.count,
            negotiatedMaxBytes: negotiatedMaxBytes
        ) else {
            Log.info("outbound video frame rejected before write: bytes=\(payload.count) negotiatedMaxBytes=\(negotiatedMaxBytes ?? 0) absoluteMaxBytes=\(FrameSizePolicy.absoluteMaxBytes)")
            queue.async { [weak self] in
                guard let self, self.connectionReady else { return }
                self.dropsThisWindow += 1
                self.dropsTotal += 1
                Task { await self.status("视频帧超过协商上限，正在重新连接…") }
                self.scheduleReconnect()
            }
            return
        }
        var header = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &header, count: 4)
        frame.append(payload)
        nextPendingSendID &+= 1
        let pendingSendID = nextPendingSendID
        let sendStartedAt = ProcessInfo.processInfo.systemUptime
        pendingSendStartedAt[pendingSendID] = sendStartedAt
        pendingSends += 1
        connection.send(content: frame, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            let completedAt = ProcessInfo.processInfo.systemUptime
            guard let startedAt = self.pendingSendStartedAt.removeValue(
                forKey: pendingSendID) else { return }
            self.lastSendCompletionDelayMs = max(
                0, (completedAt - startedAt) * 1_000)
            self.pendingSends = max(0, self.pendingSends - 1)
            if let error {
                Log.info("send error: \(error)")
                self.requestKeyframe(.transportWriteFailure)
                return
            }
            self.localSentFrames += 1
            self.framesSent += 1
            self.bytesSent += frame.count
            // Report stats roughly once a second.
            let elapsed = Date().timeIntervalSince(self.statsWindowStart)
            if elapsed >= 1.0 {
                let mbps = Double(self.bytesSent) * 8 / elapsed / 1_000_000
                self.lastActualBitrateMbps = mbps
                let frames = self.framesSent
                self.lastSentFps = Int((Double(self.framesSent) / elapsed).rounded())
                self.framesSent = 0
                self.bytesSent = 0
                self.statsWindowStart = Date()
                Task { @MainActor in self.onStats?(frames, mbps) }
            }
        })
    }

    @discardableResult
    private func requestKeyframe(_ reason: FrameDropReason) -> KeyframeRequestDisposition {
        let disposition = keyframeRequests.request(reason)
        switch disposition {
        case .ignored:
            break
        case .scheduled:
            Log.info("keyframe requested reason=\(reason.rawValue) status=scheduled count=\(keyframeRequests.requestCount)")
        case .coalesced:
            Log.info("keyframe requested reason=\(reason.rawValue) status=coalesced count=\(keyframeRequests.requestCount) coalesced=\(keyframeRequests.coalescedCount)")
        }
        return disposition
    }

    // MARK: - Helpers

    private func status(_ text: String) async {
        await MainActor.run { onStatus?(text) }
    }

    private var activeTransportName: String {
        switch transport {
        case .tcp: return "wifi"
        case .usb: return "apple-usb"
        case .androidAdb: return "android-adb-usb"
        }
    }

    private var bitrateTransport: BitrateTransport {
        switch transport {
        case .tcp: return .wifi
        case .usb, .androidAdb: return .usb
        }
    }

    private func selectedBitrate(automatic: Int, codec: StreamCodec) -> Int {
        StreamEncodingPolicy.selectedBitrate(
            mode: settings.bitrateMode, preset: settings.bitratePreset,
            automatic: automatic, codec: codec, transport: bitrateTransport)
    }

    private func updateAdaptiveBitrate(receiver: ReceiverStats) {
        guard let controller = adaptiveBitrateController else { return }
        let decision = controller.evaluate(
            AdaptiveBitrateMetrics(
                timestamp: ProcessInfo.processInfo.systemUptime,
                pendingSends: pendingSends,
                encodedFps: Double(lastEncodedFps), sentFps: Double(lastSentFps),
                rttMs: receiver.rttMs, frameAgeP95Ms: receiver.frameAgeP95Ms,
                macDrops: lastMacDropsSnapshot,
                androidDrops: max(Int(receiver.androidDroppedFrames ?? 0), 0),
                androidCongestionDrops: max(
                    Int(receiver.androidCongestionDrops ?? 0), 0),
                androidQueueDepth: max(Int(receiver.androidQueueDepth ?? 0), 0)),
            mode: settings.bitrateMode)
        guard let decision else { return }
        applyAdaptiveDecision(decision)
    }

    private func applyAdaptiveDecision(_ decision: AdaptiveBitrateDecision) {
        guard let encoder else { return }
        streamBitrate = decision.newBitrate
        VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: streamBitrate as CFNumber)
        VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_DataRateLimits,
                             value: [max(streamBitrate / 8, 1), 1] as CFArray)
        lastAdaptiveDecision = decision
        Task { @MainActor in onTargetBitrate?(Double(streamBitrate) / 1_000_000) }
        sendStreamConfig(width: activeStreamWidth, height: activeStreamHeight)
        Log.info("adaptive bitrate previousBitrate=\(decision.previousBitrate) newBitrate=\(decision.newBitrate) reason=\(decision.reason) trigger=\(decision.trigger) decisionEpoch=\(decision.decisionEpoch) networkState=\(decision.networkState.rawValue)")
    }

    private func appendBenchmarkSample(receiver: ReceiverStats) {
        guard let recorder = benchmarkRecorder,
              BenchmarkRecordingGate.shouldAppend(
                isRecorderActive: recorder.isActive, hasReceiverStats: true),
              let startedAt = benchmarkStartedAt,
              let policy = benchmarkPhasePolicy,
              let runId = benchmarkRunId,
              let sessionId = benchmarkSessionId,
              let scene = benchmarkScene else { return }
        let elapsed = startedAt.duration(to: benchmarkClock.now)
        let elapsedSeconds = BenchmarkControlPolicy.seconds(from: elapsed)
        let phase = policy.phase(elapsedSeconds: elapsedSeconds)
        guard phase != .finished else {
            finishBenchmarkOnQueue(message: "Benchmark completed")
            return
        }
        let sample = BenchmarkSample(
            timestamp: Date(), monotonicElapsed: elapsed,
            runId: runId, sessionId: sessionId, scene: scene.rawValue, phase: phase.rawValue,
            deviceModel: lastHello?.negotiatedDeviceModel ?? receiver.deviceModel ?? "notAvailable",
            transport: activeTransportName, codec: streamCodec.rawValue,
            resolution: BenchmarkResolution(width: activeStreamWidth, height: activeStreamHeight),
            requestedFps: Double(requestedCaptureFps),
            actualVirtualDisplayRefreshRate: Double(actualVirtualDisplayRefreshRate),
            captureFps: Double(lastCaptureFps), encodedFps: Double(lastEncodedFps),
            sentFps: Double(lastSentFps), receiver: receiver,
            targetBitrateMbps: Double(streamBitrate) / 1_000_000,
            actualBitrateMbps: lastActualBitrateMbps > 0 ? lastActualBitrateMbps : nil,
            previousBitrateMbps: lastAdaptiveDecision.map { Double($0.previousBitrate) / 1_000_000 },
            newBitrateMbps: lastAdaptiveDecision.map { Double($0.newBitrate) / 1_000_000 },
            bitrateChangeReason: lastAdaptiveDecision?.reason,
            bitrateChangeTrigger: lastAdaptiveDecision?.trigger,
            decisionEpoch: adaptiveBitrateController.map {
                Double($0.decisionEpoch)
            },
            lastDecreaseReason: adaptiveBitrateController?.lastDecreaseReason,
            lastDecreaseAt: adaptiveBitrateController?.lastDecreaseAt,
            localOldestPendingSendAgeMs: lastLocalOldestPendingSendAgeMs,
            localSendCompletionDelayMs: lastSendCompletionDelayMs,
            localEncodedFps: lastLocalEncodedFps,
            localSentFps: lastLocalSentFps,
            networkState: lastAdaptiveDecision?.networkState.rawValue,
            keyframeCount: Double(lastKeyframeCount),
            averageKeyframeSize: lastAverageKeyframeSize > 0 ? Double(lastAverageKeyframeSize) : nil,
            peakFrameSize: lastPeakFrameSize > 0 ? Double(lastPeakFrameSize) : nil,
            keyframeQueueDepth: Double(lastKeyframeQueueDepth),
            keyframeFrameAgeP95Ms: lastKeyframeCount > 0 ? receiver.frameAgeP95Ms : nil,
            keyframeRequestReason: keyframeRequests.pendingReason?.rawValue ?? decoderRecoveryEvent,
            keyframeRequestCount: Double(keyframeRequests.requestCount),
            keyframeCoalescedCount: Double(keyframeRequests.coalescedCount),
            decoderRecoveryEvent: decoderRecoveryEvent,
            averageFrameSize: lastAverageFrameSize > 0 ? Double(lastAverageFrameSize) : nil,
            encodeLatencyMs: lastEncodeLatencyMs, pendingSends: Double(pendingSends),
            macQueue: Double(pendingSends), macDrops: Double(lastMacDropsSnapshot),
            macCPU: nil, macMemory: Self.residentMemoryMB())
        do {
            try recorder.append(sample)
            lastAdaptiveDecision = nil
            decoderRecoveryEvent = nil
            Task { @MainActor in
                onBenchmarkStatus?("\(phase.rawValue) · \(scene.label) · \(runId)")
            }
        } catch {
            finishBenchmarkOnQueue(message: "Benchmark failed: \(error)")
        }
    }

    private func finishBenchmarkOnQueue(message: String?) {
        guard let recorder = benchmarkRecorder else { return }
        benchmarkRecorder = nil
        benchmarkStartedAt = nil
        benchmarkPhasePolicy = nil
        benchmarkRunId = nil
        benchmarkSessionId = nil
        benchmarkScene = nil
        benchmarkFinishWorkItem?.cancel()
        benchmarkFinishWorkItem = nil
        let outputDirectory = benchmarkOutputDirectory
        benchmarkOutputDirectory = nil
        do {
            let result = try recorder.stop()
            if let message {
                let finalMessage = "\(message) · \(result.csvURL.deletingLastPathComponent().path)"
                Task { @MainActor in onBenchmarkStatus?(finalMessage) }
            }
        } catch {
            let directory = outputDirectory?.path ?? "output path unavailable"
            let failure = "Benchmark flush failed: \(error) · \(directory)"
            Log.info(failure)
            Task { @MainActor in onBenchmarkStatus?(failure) }
        }
    }

    private static func residentMemoryMB() -> Double? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.resident_size) / 1_048_576
    }

}
