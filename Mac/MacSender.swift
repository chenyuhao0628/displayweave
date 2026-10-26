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

@preconcurrency import ScreenCaptureKit
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
    case tcp(NWEndpoint, interface: NWInterface? = nil)                   // WiFi (Bonjour) or -host/-port override
    case usb(udid: String?, port: UInt16)  // native usbmuxd dial; nil = first device
    case androidAdb(port: UInt16)          // localhost endpoint created by adb forward
}

enum SenderDisconnectReason { case connectionLost, receiverExit }

@available(macOS 14.0, *)
final class MacSender: NSObject, SCStreamOutput, SCStreamDelegate, DisplayUnitParticipant, @unchecked Sendable {

    // Status surfaced to the UI (updated on main thread).
    @MainActor var onStatus: ((String) -> Void)?
    @MainActor var onStats: ((Int, Double) -> Void)?   // framesSent, mbps
    @MainActor var onTargetBitrate: ((Double) -> Void)?
    @MainActor var onStreamDescription: ((String, String?) -> Void)?
    @MainActor var onBenchmarkStatus: ((String) -> Void)?
    // Fired when a previously connected device stays gone past the grace
    // period — the controller ends the session (capture, virtual display,
    // recording indicator all torn down) instead of dialing forever or
    // silently coming back over a different transport.
    @MainActor var onDisconnected: ((SenderDisconnectReason) -> Void)?
    // Fired on every hello — carries the receiver's install id so the
    // controller can deduplicate USB/WiFi sessions to the same device.
    @MainActor var onHello: ((PhoneInfo) -> Void)?
    @MainActor var onSecurityError: ((String) -> Void)?
    @MainActor var onPipelineFailure: ((Error) -> Void)?
    @MainActor var onCaptureStoppedByUser: (() -> Void)?
    private var pipelineFailureReported = false // owned by queue

    private var stream: SCStream?
    private var encoder: VTCompressionSession?
    private let encoderWork = EncoderWorkQueue()
    private var connection: NWConnection?
    private var admission: AppleSecureAdmission?
    private var usbTLSRelay: UsbmuxTLSRelay?
    private let securityPlan: AppleSenderSecurityPlan
    var encrypted: Bool { securityPlan.encrypted }
    var secureReceiverID: String? { securityPlan.receiverID }
    private var virtualDisplay: VirtualDisplay?
    private let queue = DispatchQueue(label: "sender.video", qos: .userInteractive)
    private let startCode: [UInt8] = [0, 0, 0, 1]

    var directLinkInterfaceName: String? {
        if case .tcp(_, let interface) = transport { return interface?.name }
        return nil
    }
    private let transport: SenderTransport
    private let endpointName: String
    private let mode: CaptureMode
    private let quality: StreamQuality
    private let settings: StreamSettings
    private let testPatternOwnerID = UUID()
    // Stable per-device serial for the virtual display, so macOS can tell
    // multiple OpenDisplay monitors apart and persist their arrangement.
    private let displaySerial: UInt32
    private let displayCoordinator: DisplayUnitCoordinator

    // Bound VideoToolbox work and outstanding sends independently. Combining
    // both into Gaming's budget of one made a normal 10 ms asynchronous encode
    // reject every second 120 Hz capture and hard-capped the stream near 60.
    private var pendingSends = 0
    private var pendingEncodeWork = GenerationWorkCounter()
    private var pendingEncodes: Int {
        pendingEncodeWork.count(generation: encoderGeneration)
    }
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
    private let stoppedLock = NSLock()
    private var stoppedStorage = false
    private var stopped: Bool {
        get {
            stoppedLock.lock()
            defer { stoppedLock.unlock() }
            return stoppedStorage
        }
        set {
            stoppedLock.lock()
            stoppedStorage = newValue
            stoppedLock.unlock()
        }
    }
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
    private var disconnectCallbackPending = false

    private var lastHello: PhoneInfo?
    private var helloContinuation: CheckedContinuation<PhoneInfo, Error>?
    private var inputInjector: InputInjector?
    private lazy var desktopInput = DesktopInputSender { [weak self] object in
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        self?.sendJSONFrame(String(decoding: data, as: UTF8.self))
    }
    private var pencilExtendedNegotiated = false
    private lazy var pencilActions = PencilActionSender(targetReady: { [weak self] in self?.inputInjector != nil },
        onChange: { [weak self] in self?.sendPencilConfiguration() },
        perform: { [weak self] action in
            guard let shortcut = PencilShortcut.configured(action) else { return }
            self?.inputInjector?.handleShortcut(shortcut)
        })
    private var protocolIdentity = StreamProtocolIdentity()
    private var protocolHandshake = ReceiverProtocolHandshake()
    private var protocolFailureBudget = ReceiverProtocolFailureBudget(maxReconnects: 1)
    // VideoToolbox callbacks can arrive after a disconnect or reconnect. Tie
    // every encode to the ready connection that accepted it so an old frame
    // can never be written to a newer peer.
    private var pencilNegotiated = false
    private var macCodecFallback = MacCodecFallbackPolicy()
    private var wireConnectionGeneration: UInt64 = 0
    private var encoderGeneration: UInt64 = 0
    // Owns every NWConnection callback. `dialGeneration` only protects an
    // asynchronous usbmux dial before adoption; this generation protects the
    // adopted connection for its entire callback lifetime.
    private var connectionGeneration: UInt64 = 0
    private var reconnectGeneration: UInt64 = 0
    private var reconnectWorkItem: DispatchWorkItem?

    // Liveness: both sides ping every 2s; if nothing arrives for 5s the link
    // is half-open (e.g. usbmuxd accepted but the device is gone) — reconnect.
    private var lastReceived = Date()
    private var dropsTotal = 0

    // Sample pointer position independently of video encoding. The receiver
    // draws it locally; the shared framed transport can still impose latency.
    // Escape hatch: `defaults write app.displayweave.mac.debug localCursor -bool false`.
    private let localCursor = UserDefaults.standard.object(forKey: "localCursor") == nil
        || UserDefaults.standard.bool(forKey: "localCursor")
    private let cursorEcho = CursorEcho()
    private var cursorImageTimer: DispatchSourceTimer?
    private let cursorImageLock = NSLock()
    private var cursorImageContext: (displayID: CGDirectDisplayID, wire: UInt64, encoder: UInt64, hash: Int)?
    private let cursorImages = LatestValueRelay<(json: String, wire: UInt64, encoder: UInt64)>()
    private var captureDisplayID: CGDirectDisplayID = 0

    // Input latency: touches arrive stamped in our clock (the phone applies
    // its sync offset); delta to now = network + deframe + dispatch.
    private var inputLatencies: [Double] = []
    // Capture cadence: SCK only emits on content change, so the phone can't
    // tell "Mac rendered 45fps" from "frames got lost" — count deliveries here.
    private var capFrames = 0
    private var capWindowStart = Date()
    private var pipelineEncodedFrames = 0
    private var pipelineSentFrames = 0
    private var pipelineSentBytes = 0
    private var maxEncodeSubmissionMs: Double = 0
    private var encodeSubmissionMsTotal: Double = 0
    private var encodeSubmissionCount = 0
    private var encoderDropsThisWindow = 0
    private var encoderLoad: EncoderLoadController?
    private var encoderLoadAdjustmentID: UUID?
    private var encoderLoadAdjustmentTask: Task<Void, Never>?
    private var requestedCaptureFps = 60
    private var decoderFpsAdjustmentInFlight = false
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
    private var benchmarkPendingEncodePeak = 0
    private var benchmarkFinishWorkItem: DispatchWorkItem?
    private var benchmarkOutputDirectory: URL?
    private var benchmarkCPU = ProcessCPUSampler()

    // ScreenCaptureKit emits frames only when content changes. After a
    // reconnect on a static screen there is nothing to hang the forced
    // keyframe on — so keep the last frame around and re-encode it.
    private var captureFrames = CaptureFrameReplay<CVPixelBuffer>()
    private var lastPixelBuffer: CVPixelBuffer? { captureFrames.latest }
    private var lastCaptureAt = Date.distantPast
    private var dropReplayWork: DispatchWorkItem?
    private var dropReplayID: UUID?
    private var captureRecoveryWork: DispatchWorkItem?
    private var captureRecoveryID: UUID?
    private var captureStopTask: Task<Void, Never>?
    private var captureRecovery = CaptureRecoveryPolicy()
    private var captureSourceCheck = CaptureSourceCheck()
    private var captureNeedsRebuild = false
    private var appliedCaptureInfo: PhoneInfo? // queue-owned configuration actually installed
    private var encoderFailureRecovery = EncoderFailureRecovery()
    private var releasedForRenumbering = false
    private var waitingForConsole = false
    private var encodeFailureLog = ThrottledLogPolicy<String>()
    private var encodeFailureLogWork: DispatchWorkItem?
    private var unknownControlLog = UnknownControlTypeLogPolicy()

    init(transport: SenderTransport, name: String, mode: CaptureMode,
         securityPlan: AppleSenderSecurityPlan,
         displayCoordinator: DisplayUnitCoordinator,
         settings: StreamSettings = StreamSettings.load(), displaySerial: UInt32 = 0x0001) {
        self.securityPlan = securityPlan
        self.transport = transport
        self.endpointName = name
        self.mode = mode
        self.settings = settings
        self.quality = settings.quality
        self.displaySerial = displaySerial
        self.displayCoordinator = displayCoordinator
        super.init()
    }

    // MARK: - Lifecycle

    func start() async throws {
        guard !stopped else { throw CancellationError() }
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
            await status("需要屏幕录制权限，请打开设置 → 权限与诊断")
            Log.info("Screen Recording permission missing — waiting for grant via the permission panel")
            while !CGPreflightScreenCaptureAccess() {
                try await Task.sleep(for: .seconds(2))
                if stopped { return }
            }
            Log.info("Screen Recording permission granted")
        }

        switch mode {
        case .mirror:
            let info = try await waitForHello()
            try await setupMirror(info)
            if let latest = queue.sync(execute: { lastHello }), !latest.sameDisplayConfiguration(as: info) {
                _ = await reconfigure(latest)
            }
            if !info.isMacReceiver { try await waitForAccessibilityIfNeeded(statusText: "正在镜像，请授权“辅助功能”以启用触摸输入") }

        case .extend:
            await status("正在等待设备连接…")
            let info = try await waitForHello()
            try await setupExtend(info)
            if let latest = queue.sync(execute: { lastHello }), !latest.sameDisplayConfiguration(as: info) {
                _ = await reconfigure(latest)
            }

            // Touch back-channel (Milestone 3). Needs Accessibility trust;
            // streaming works without it, so don't interrupt with a prompt —
            // the permission panel's Grant button asks when the user is ready.
            if !info.isMacReceiver { try await waitForAccessibilityIfNeeded(statusText: "正在扩展，请授权“辅助功能”以启用触摸输入") }
        }
    }

    @MainActor
    private func setupMirror(_ info: PhoneInfo) async throws {
        guard !stopped else { throw CancellationError() }
        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
            throw NSError(domain: "MacSender", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "未找到可捕获的显示器"])
        }
        // SCDisplay reports points; capture at point resolution for M1.
        let macPlan = info.usesAppleVideoCapabilities ? MacReceiverPolicy.plan(info: info, settings: settings, sourceWidth: display.width, sourceHeight: display.height, hardwareHEVCEncode: EncoderHardwareCapabilities.hevc) : nil
        logAppleStreamPlan(macPlan)
        let mobileRaster = DesktopResolutionPolicy.mirrorRaster(sourceWidth: display.width,
            sourceHeight: display.height, qualityScale: quality.scale,
            maxWidth: info.maxEncodeWide ?? info.pixelsWide,
            maxHeight: info.maxEncodeHigh ?? info.pixelsHigh)
        let captureW = macPlan?.width ?? mobileRaster.width
        let captureH = macPlan?.height ?? mobileRaster.height
        let captureFps = macPlan?.fps ?? settings.selectedFps(deviceMaxFps: info.negotiatedMaxFps)
        let codec = macPlan?.codec ?? (info.isAndroidReceiver ? settings.selectedCodec(
            supportedCodecs: info.negotiatedSupportedCodecs, preferredCodec: info.negotiatedPreferredCodec) : .h264)
        try await startCapture(display: display, pixelsWide: captureW, pixelsHigh: captureH,
                           fps: captureFps, virtualDisplayRefreshRate: captureFps,
                           codec: codec)
        queue.sync {
            appliedCaptureInfo = info
            inputInjector?.cancelPress()
            if !stopped {
                inputInjector = InputInjector(displayID: display.displayID)
                desktopInput.configure(displayID: display.displayID)
                pencilActions.begin(encrypted: encrypted, supported: pencilExtendedNegotiated)
            }
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
    @MainActor
    private func setupExtend(_ info: PhoneInfo) async throws {
        try await displayCoordinator.exclusively { try await self.setupExtendExclusive(info) }
    }

    @MainActor
    private func setupExtendExclusive(_ info: PhoneInfo) async throws {
        Log.info("phone hello: \(info.pixelsWide)x\(info.pixelsHigh) @\(info.scale)x device=\(info.negotiatedDeviceModel) refresh=\(info.negotiatedRefreshRate)Hz maxFps=\(info.negotiatedMaxFps) codecs=\(info.negotiatedSupportedCodecs.joined(separator: ",")) preferred=\(info.negotiatedPreferredCodec) sdk=\(info.negotiatedAndroidSdk) transport=\(info.negotiatedTransport)")

        guard !stopped else { throw CancellationError() }
        let macPlan = info.usesAppleVideoCapabilities ? MacReceiverPolicy.plan(info: info, settings: settings, hardwareHEVCEncode: EncoderHardwareCapabilities.hevc) : nil
        logAppleStreamPlan(macPlan)
        let mobileDesktop = DesktopResolutionPolicy.geometry(
            settings.desktopResolutions.resolution(for: info.id),
            nativeWidth: info.pixelsWide, nativeHeight: info.pixelsHigh, backingScale: 2)
        let pointsWide = macPlan?.pointsWide ?? mobileDesktop.pointsWide
        let pointsHigh = macPlan?.pointsHigh ?? mobileDesktop.pointsHigh
        // Rough physical size so macOS picks a sane default UI scale.
        let mm = info.isMacReceiver ? CGSize(width: Double(pointsWide) * 25.4 / 110, height: Double(pointsHigh) * 25.4 / 110) : info.pixelsWide >= info.pixelsHigh
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
        let requestedRefreshRate = macPlan?.fps ?? settings.selectedFps(deviceMaxFps: info.negotiatedMaxFps)
        let arrangementKey = info.id ?? "serial-\(displaySerial)"
        let desktopSize = CGSize(width: pointsWide, height: pointsHigh)
        try displayCoordinator.register(self)
        let vd = try await makeAvoidingUnitClash { () -> VirtualDisplay? in
            guard !self.stopped else { return nil }
            return VirtualDisplay(name: displayName,
                           pointsWide: pointsWide, pointsHigh: pointsHigh,
                           sizeInMillimeters: mm, serialNum: serial,
                           requestedRefreshRate: requestedRefreshRate,
                           backingScale: macPlan?.scale ?? 2,
                           restoreOrigin: DisplayArrangement.origin(for: desktopSize, device: arrangementKey),
                           onOriginChange: { origin, size in
                               DisplayArrangement.save(origin: origin, size: size, device: arrangementKey)
                           })
        }
        guard let vd else {
            throw NSError(domain: "MacSender", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "创建虚拟显示器失败"])
        }
        Log.info("virtual display refresh selected: requested=\(requestedRefreshRate) actual=\(vd.actualRefreshRate) deviceMaxFps=\(info.negotiatedMaxFps) fallback=\(vd.refreshRateFallbackReason ?? "none")")
        let installed = queue.sync { () -> Bool in
            guard !stopped else { return false }
            virtualDisplay = vd
            inputInjector?.cancelPress()
            inputInjector = InputInjector(displayID: vd.displayID)
            desktopInput.configure(displayID: vd.displayID)
            pencilActions.begin(encrypted: encrypted, supported: pencilExtendedNegotiated)
            return true
        }
        guard installed else { throw CancellationError() }

        let display = try await findSCDisplay(id: vd.displayID)
        // Mobile legacy peers have no decoder envelope; don't exceed the panel
        // raster they already support. Desktop layout remains independently selected.
        let mobileRaster = DesktopResolutionPolicy.raster(mobileDesktop, qualityScale: quality.scale,
            maxWidth: info.maxEncodeWide ?? info.pixelsWide,
            maxHeight: info.maxEncodeHigh ?? info.pixelsHigh)
        let captureW = macPlan?.width ?? mobileRaster.width
        let captureH = macPlan?.height ?? mobileRaster.height
        let codec = macPlan?.codec ?? (info.isAndroidReceiver ? settings.selectedCodec(
            supportedCodecs: info.negotiatedSupportedCodecs,
            preferredCodec: info.negotiatedPreferredCodec) : .h264)
        try await startCapture(display: display, pixelsWide: captureW, pixelsHigh: captureH,
                               fps: macPlan.map { min($0.fps, vd.actualRefreshRate) } ?? vd.actualRefreshRate,
                               virtualDisplayRefreshRate: vd.actualRefreshRate,
                               codec: codec)
        queue.sync { appliedCaptureInfo = info }

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
    @MainActor private var reconfiguring = false
    private var reconfigurationTask: Task<Void, Never>? // owned by queue
    private var reconfigurationID: UUID? // queued/cancelled task completions cannot clear a replacement

    @MainActor
    private func reconfigure(_ info: PhoneInfo) async -> PhoneInfo? {
        do {
            return try await displayCoordinator.exclusively { await self.reconfigureExclusive(info) }
        } catch {
            if !(error is CancellationError), !stopped { queue.async { self.failPipeline(error) } }
            return nil
        }
    }

    @MainActor
    private func reconfigureExclusive(_ info: PhoneInfo, recoveringCapture: Bool = false) async -> PhoneInfo? {
        guard !reconfiguring, !stopped else { return nil }
        reconfiguring = true
        defer { reconfiguring = false }
        await finishRetiredCapture()
        if recoveringCapture && !consoleCanCapture { return nil }
        queue.sync { captureRecovery.beginAttempt() }
        var target = info
        while !stopped && !Task.isCancelled {
            Log.info("reconfiguring for \(target.pixelsWide)x\(target.pixelsHigh)")
            let testPatternOwnerID = self.testPatternOwnerID
            await MainActor.run {
                TestPattern.hide(ownerID: testPatternOwnerID)
            }
            var detached: (stream: SCStream?, display: VirtualDisplay?) = queue.sync {
                let activeStream = invalidateCapturePipeline()
                let activeDisplay = virtualDisplay
                virtualDisplay = nil
                requestKeyframe(.streamReconfigure)
                return (activeStream, activeDisplay)
            }
            if let activeStream = detached.stream {
                try? await activeStream.stopCapture()
            }
            // Releasing the detached object on MainActor removes the display.
            detached.stream = nil
            detached.display = nil
            do {
                try Task.checkCancellation()
                if recoveringCapture && !consoleCanCapture { return nil }
                if mode == .mirror { try await setupMirror(target) }
                else { try await setupExtendExclusive(target) }
            } catch {
                guard !(error is CancellationError), !stopped else { return nil }
                Log.info("reconfigure failed: \(error)")
                if error is EncoderSessionFactory.Failure {
                    queue.async { self.failPipeline(error) }
                } else {
                    await status("显示配置失败：\(error.localizedDescription)")
                }
                return nil
            }
            if let latest = queue.sync(execute: { lastHello }),
               !latest.sameDisplayConfiguration(as: target) {
                target = latest   // rotated again while we were rebuilding
                continue
            }
            return target
        }
        return nil
    }

    @MainActor var displayUnitIdentity: DisplayUnitIdentity? {
        queue.sync {
            guard !stopped, let display = virtualDisplay else { return nil }
            return DisplayUnitIdentity(displayID: display.displayID, unit: CGDisplayUnitNumber(display.displayID))
        }
    }

    /// The coordinator already owns the display-mutation lock. A queued
    /// rebuild may be cancelled here; never await it while holding that lock.
    @MainActor func releaseDisplayForRenumbering(expectedID: UInt32) async -> Bool {
        var retired: (stream: SCStream?, display: VirtualDisplay?)? = queue.sync {
            guard !stopped, !releasedForRenumbering, virtualDisplay?.displayID == expectedID else { return nil }
            releasedForRenumbering = true
            reconfigurationTask?.cancel(); reconfigurationTask = nil; reconfigurationID = nil
            captureRecoveryWork?.cancel(); captureRecoveryWork = nil; captureRecoveryID = nil
            let retired = (invalidateCapturePipeline(), virtualDisplay)
            virtualDisplay = nil
            inputInjector?.cancelPress(); inputInjector = nil
            desktopInput.reset(removeTarget: true)
            return retired
        }
        guard retired != nil else { return false }
        TestPattern.hide(ownerID: testPatternOwnerID)
        await finishRetiredCapture()
        if let stream = retired?.stream { try? await stream.stopCapture() }
        retired?.stream = nil
        retired?.display = nil
        return true
    }

    @MainActor func resumeAfterDisplayRenumbering() async {
        let rebuilding = queue.sync { () -> Task<Void, Never>? in
            guard self.releasedForRenumbering else { return nil }
            self.releasedForRenumbering = false
            guard !self.stopped, !self.pipelineFailureReported else { return nil }
            self.scheduleReconfiguration(recoverCapture: true)
            return self.reconfigurationTask
        }
        await rebuilding?.value
    }

    @MainActor
    private func makeAvoidingUnitClash(_ make: @MainActor () -> VirtualDisplay?) async throws -> VirtualDisplay? {
        var created = make()
        guard let id = created?.displayID else { return nil }
        let identity = try await DisplayTopology.settledUnit(id)
        guard !stopped else { throw CancellationError() }
        let plan = DisplayUnitCollisionPolicy.plan(created: identity,
            online: DisplayTopology.onlineUnits(), owned: displayCoordinator.identities)
        switch plan {
        case .none: return created
        case .unavailable:
            throw DisplayUnitCoordinator.failure("虚拟显示器编号不可用，请解锁 Mac 后重新连接。")
        case .unowned:
            throw DisplayUnitCoordinator.failure("虚拟显示器与外部显示器编号冲突，请断开本次会话后重新连接。")
        case .rebuild(let ids):
            Log.info("DISPLAY-UNIT-RECOVERY releasing \(ids.count + 1) owned displays in unit order")
            created = nil
            return try await displayCoordinator.withReleasedPeers(ids) { retiredIDs in
                try await DisplayTopology.waitUntilOffline([id] + retiredIDs)
                guard !stopped else { throw CancellationError() }
                let replacement = make()
                guard let replacementID = replacement?.displayID else { return nil }
                let replacementIdentity = try await DisplayTopology.settledUnit(replacementID)
                guard !stopped else { throw CancellationError() }
                guard DisplayUnitCollisionPolicy.plan(created: replacementIdentity,
                    online: DisplayTopology.onlineUnits(), owned: displayCoordinator.identities) == .none else {
                    throw DisplayUnitCoordinator.failure("虚拟显示器编号仍冲突，请断开相关会话后重新连接。")
                }
                return replacement
            }
        }
    }

    /// Queue-owned retirement shared by stop, resize and capture recovery.
    /// Cached pixels and every delayed replay belong to this capture only.
    @discardableResult
    private func invalidateCapturePipeline() -> SCStream? {
        let retired = stream
        stream = nil
        encoderLoadAdjustmentTask?.cancel()
        encoderLoadAdjustmentTask = nil
        encoderLoadAdjustmentID = nil
        encoderLoad = nil
        stopCursorEcho()
        captureDisplayID = 0
        captureFrames.retire()
        captureSourceCheck = CaptureSourceCheck()
        lastCaptureAt = .distantPast
        dropReplayWork?.cancel(); dropReplayWork = nil
        dropReplayID = nil
        captureRecoveryWork?.cancel(); captureRecoveryWork = nil; captureRecoveryID = nil
        pendingEncodeWork.discard(generation: encoderGeneration)
        keyframeRequests.retireInFlightRequest()
        encoderGeneration &+= 1
        retireEncoder()
        return retired
    }

    /// The virtual display takes a moment to show up in shareable content.
    private func findSCDisplay(id: CGDirectDisplayID) async throws -> SCDisplay {
        for _ in 0..<20 {
            try Task.checkCancellation()
            guard !stopped else { throw CancellationError() }
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
        try Task.checkCancellation()
        let filter = SCContentFilter(display: display, excludingWindows: [])

        let prepared = try queue.sync { () throws -> (SCStreamConfiguration, StreamCodec, Int, Int)? in
            guard !stopped, !pipelineFailureReported else { return nil }
            let captureFps = lastHello?.usesAppleVideoCapabilities == true ? max(1, min(120, fps)) : RefreshRatePolicy.sanitize(fps)
            requestedCaptureFps = captureFps
            encoderLoad = lastHello?.isMacReceiver == true && settings.adaptEncoderLoad && settings.bitrateMode != .benchmark
                ? EncoderLoadController(configuration: .init(width: pixelsWide, height: pixelsHigh, fps: captureFps), priority: settings.priority)
                : nil
            actualVirtualDisplayRefreshRate = RefreshRatePolicy.sanitize(
                virtualDisplayRefreshRate)
            lastCaptureFpsWarningAt = Date.distantPast
            let config = makeCaptureConfiguration(
                width: pixelsWide, height: pixelsHigh, fps: captureFps)
            try setupEncoder(
                width: pixelsWide, height: pixelsHigh,
                fps: captureFps, preferredCodec: codec)
            activeStreamWidth = pixelsWide
            activeStreamHeight = pixelsHigh
            sendStreamConfig(width: pixelsWide, height: pixelsHigh)
            return (config, streamCodec, streamBitrate, actualVirtualDisplayRefreshRate)
        }
        guard let prepared else { throw CancellationError() }
        let config = prepared.0
        let captureFps = Int(config.minimumFrameInterval.timescale)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        let attached = queue.sync { () -> Bool in
            guard !stopped, !pipelineFailureReported, self.stream == nil else { return false }
            self.stream = stream
            captureDisplayID = display.displayID
            _ = captureFrames.begin()
            captureSourceCheck = CaptureSourceCheck()
            return true
        }
        guard attached else { throw CancellationError() }
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
            try Task.checkCancellation()
        } catch {
            queue.sync { if self.stream === stream { _ = invalidateCapturePipeline() } }
            try? await stream.stopCapture()
            throw error
        }
        let kind = queue.sync { () -> String? in
            guard !stopped, !pipelineFailureReported, self.stream === stream else { return nil }
            waitingForConsole = false
            startCursorEcho()
            return lastHello?.kind ?? "设备"
        }
        guard let kind else {
            try? await stream.stopCapture()
            throw CancellationError()
        }
        Log.info("capture started: \(pixelsWide)x\(pixelsHigh) display \(display.displayID) mode \(mode.rawValue) requestedCaptureFps=\(captureFps) actualVirtualDisplayRefreshRate=\(prepared.3) codec=\(prepared.1.rawValue) bitrate=\(prepared.2) minimumFrameInterval=1/\(RefreshRatePolicy.captureIntervalTimescale(fps: captureFps)) localCursor=\(localCursor)")
        await status("\(mode == .extend ? "正在扩展到" : "正在镜像到") \(kind)（\(pixelsWide)×\(pixelsHigh)）")
    }

    private func makeCaptureConfiguration(
        width: Int, height: Int, fps: Int
    ) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(max(1, min(120, fps))))
        // 420v matches the encoder's native input and avoids an extra conversion.
        config.pixelFormat = UserDefaults.standard.string(forKey: "pixfmt") == "bgra"
            ? kCVPixelFormatType_32BGRA
            : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        // Keep enough SCK headroom for keyframe replay and asynchronous encode.
        config.queueDepth = 8
        config.showsCursor = !localCursor
        return config
    }

    private func logAppleStreamPlan(_ plan: MacStreamPlan?) {
        guard let plan else { return }
        Log.info("APPLE-STREAM-PLAN desktopPoints=\(plan.pointsWide)x\(plan.pointsHigh) scale=\(plan.scale) raster=\(plan.width)x\(plan.height) fps=\(plan.fps) requestedCodec=\(settings.codecMode.rawValue) selectedCodec=\(plan.codec.rawValue) hardwareHEVCEncoder=\(EncoderHardwareCapabilities.hevc) priority=\(settings.priority.rawValue) adaptEncoderLoad=\(settings.adaptEncoderLoad)")
    }

    @MainActor
    @discardableResult
    func stop() -> Task<Void, Never> {
        stopped = true
        displayCoordinator.unregister(self)
        cursorEcho.stop()
        TestPattern.hide(ownerID: testPatternOwnerID)
        let detached: (stream: SCStream?, display: VirtualDisplay?, reconfiguration: Task<Void, Never>?, captureStop: Task<Void, Never>?) = queue.sync {
            let reconfiguration = reconfigurationTask
            reconfigurationTask = nil
            reconfigurationID = nil
            reconfiguration?.cancel()
            captureRecoveryWork?.cancel(); captureRecoveryWork = nil
            encodeFailureLogWork?.cancel(); encodeFailureLogWork = nil
            let captureStop = captureStopTask
            captureStopTask = nil
            let activeStream = invalidateCapturePipeline()
            inputInjector?.cancelPress()
            inputInjector = nil
            desktopInput.reset(removeTarget: true)
            invalidateConnection()
            cancelPendingReconnect()
            dialGeneration &+= 1
            connectionReady = false
            pendingSends = 0
            pendingSendStartedAt.removeAll()
            let activeDisplay = virtualDisplay
            virtualDisplay = nil
            finishBenchmarkOnQueue(message: "Benchmark stopped with session")
            // Unblock a start() that is still waiting for the hello.
            helloContinuation?.resume(throwing: CancellationError())
            helloContinuation = nil
            return (activeStream, activeDisplay, reconfiguration, captureStop)
        }
        return Task { @MainActor in
            await detached.reconfiguration?.value
            await detached.captureStop?.value
            if let stream = detached.stream { try? await stream.stopCapture() }
            // Keep the display alive until capture stops, then release it here.
            withExtendedLifetime(detached.display) {}
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
            benchmarkCPU.reset()
            _ = benchmarkCPU.sample()
            benchmarkPhasePolicy = BenchmarkPhasePolicy(runSeconds: TimeInterval(duration.rawValue))
            benchmarkRunId = runId
            benchmarkSessionId = UUID().uuidString.lowercased()
            benchmarkScene = scene
            benchmarkPendingEncodePeak = pendingEncodes
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
            self.disconnectCallbackPending = false
            self.scheduleReconnect()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { [weak self, weak stream] in
            guard let self, let stream,
                  !self.stopped, !self.pipelineFailureReported,
                  self.stream === stream else { return }
            Log.info("stream stopped with error: \(error)")
            let userStopped = (error as? SCStreamError)?.code == .userStopped
            if CaptureRecoveryPolicy.honorsSystemStop(userStopped: userStopped,
                                                      consoleInteractive: self.consoleIsInteractive) {
                self.connectionReady = false
                Task { @MainActor in
                    guard !self.stopped else { return }
                    self.onCaptureStoppedByUser?()
                }
                return
            }
            Task { await self.status("采集已中断，正在恢复…") }
            self.captureRecovery.finished(succeeded: false, consoleAvailable: self.consoleCanCapture)
            self.retireCaptureForRecovery()
        }
    }

    private var consoleIsInteractive: Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        return (info[kCGSessionOnConsoleKey as String] as? Bool ?? true)
            && !(info["CGSSessionScreenIsLocked"] as? Bool ?? false)
    }

    private var consoleCanCapture: Bool {
        consoleIsInteractive && CGDisplayIsAsleep(CGMainDisplayID()) == 0
    }

    private func retireCaptureForRecovery() {
        if let retired = invalidateCapturePipeline() {
            captureStopTask = Task { try? await retired.stopCapture() }
        }
        scheduleCaptureRecovery()
    }

    @MainActor private func finishRetiredCapture() async {
        let retiring = queue.sync { (captureStopTask, captureFrames.generation) }
        await retiring.0?.value
        queue.sync {
            if captureFrames.generation == retiring.1 { captureStopTask = nil }
        }
    }

    private func scheduleCaptureRecovery(delay: TimeInterval = 3) {
        guard !stopped, !pipelineFailureReported, !releasedForRenumbering,
              stream == nil, lastHello != nil else { return }
        captureRecoveryWork?.cancel()
        let recoveryID = UUID()
        captureRecoveryID = recoveryID
        let generation = captureFrames.generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped, !self.pipelineFailureReported,
                  !self.releasedForRenumbering, self.captureRecoveryID == recoveryID,
                  self.captureFrames.generation == generation,
                  self.stream == nil else { return }
            self.captureRecoveryWork = nil
            self.captureRecoveryID = nil
            switch self.captureRecovery.action(consoleAvailable: self.consoleCanCapture,
                displayOnline: self.virtualDisplay.map { DisplayTopology.isOnline($0.displayID) } ?? false) {
            case .waitForConsole:
                if !self.waitingForConsole {
                    self.waitingForConsole = true
                    Log.info("CAPTURE-RECOVERY waiting for unlocked, awake console; retry budget unchanged")
                    Task { await self.status("等待发送端唤醒并解锁后恢复画面") }
                }
                self.scheduleCaptureRecovery()
            case .exhausted:
                self.failPipeline(DisplayUnitCoordinator.failure("采集连续恢复失败，请检查屏幕录制权限并重新连接。"))
            case .reattach, .rebuild:
                self.waitingForConsole = false
                self.scheduleReconfiguration(recoverCapture: true)
            }
        }
        captureRecoveryWork = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    @MainActor private func recoverCapture(_ info: PhoneInfo) async -> PhoneInfo? {
        do {
            return try await displayCoordinator.exclusively {
                guard !self.stopped else { throw CancellationError() }
                await self.finishRetiredCapture()
                guard self.queue.sync(execute: { self.stream == nil && !self.releasedForRenumbering }) else { return info }
                guard self.consoleCanCapture else { return nil }
                self.queue.sync { self.captureRecovery.beginAttempt() }
                let existing = self.queue.sync { () -> (VirtualDisplay, Int, Int, Int, StreamCodec)? in
                    guard !self.captureNeedsRebuild,
                          self.appliedCaptureInfo?.sameDisplayConfiguration(as: info) == true,
                          let vd = self.virtualDisplay, DisplayTopology.isOnline(vd.displayID),
                          self.activeStreamWidth > 0, self.activeStreamHeight > 0 else { return nil }
                    return (vd, self.activeStreamWidth, self.activeStreamHeight, self.requestedCaptureFps, self.streamCodec)
                }
                if let existing {
                    do {
                        Log.info("CAPTURE-RECOVERY reattaching to existing display; retaining negotiated raster/FPS")
                        let display = try await self.findSCDisplay(id: existing.0.displayID)
                        guard self.queue.sync(execute: { !self.stopped && self.virtualDisplay === existing.0 }) else { throw CancellationError() }
                        guard self.consoleCanCapture else { return nil }
                        try await self.startCapture(display: display, pixelsWide: existing.1, pixelsHigh: existing.2,
                            fps: existing.3, virtualDisplayRefreshRate: existing.0.actualRefreshRate, codec: existing.4)
                        self.queue.sync { _ = self.requestKeyframe(.streamReconfigure) }
                        return info
                    } catch {
                        if error is CancellationError || error is EncoderSessionFactory.Failure { throw error }
                        Log.info("CAPTURE-RECOVERY reattach failed: \(error); scheduling a display rebuild")
                        // Drop the local display reference before rebuilding.
                        // The next recovery round can release the owner safely.
                        self.queue.sync { self.captureNeedsRebuild = true }
                        return nil
                    }
                }
                return await self.reconfigureExclusive(info, recoveringCapture: true)
            }
        } catch {
            if !(error is CancellationError), !stopped { queue.async { self.failPipeline(error) } }
            return nil
        }
    }

    private func scheduleReconfiguration(delay: Duration = .zero, recoverCapture: Bool = false) {
        guard !stopped, !pipelineFailureReported, !releasedForRenumbering, reconfigurationTask == nil else { return }
        let id = UUID()
        reconfigurationID = id
        reconfigurationTask = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: delay) } catch { return }
            let hello = self.queue.sync { self.lastHello }
            let applied: PhoneInfo?
            if let hello {
                applied = recoverCapture ? await self.recoverCapture(hello) : await self.reconfigure(hello)
            } else { applied = nil }
            self.queue.async {
                guard self.reconfigurationID == id else { return }
                self.reconfigurationTask = nil
                self.reconfigurationID = nil
                guard !self.stopped, !self.pipelineFailureReported, !self.releasedForRenumbering else { return }
                if self.stream != nil { self.captureNeedsRebuild = false }
                if self.stream == nil {
                    self.captureRecovery.finished(succeeded: false, consoleAvailable: self.consoleCanCapture)
                }
                if let applied, let latest = self.lastHello, !applied.sameDisplayConfiguration(as: latest) {
                    self.scheduleReconfiguration()
                } else if self.stream == nil {
                    self.scheduleCaptureRecovery()
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
        case .tcp(let endpoint, let interface): connectTCP(endpoint, interface: interface)
        case .usb(let udid, let port): connectUSB(udid: udid, port: port)
        case .androidAdb(let port):
            connectTCP(.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!))
        }
    }

    /// Bookkeeping shared by both transports once a connection is live.
    private func adoptConnection(_ conn: NWConnection) -> UInt64 {
        cancelDropReplay()
        desktopInput.reset()
        pencilActions.reset(); pencilExtendedNegotiated = false
        pencilNegotiated = false
        macCodecFallback.beginConnection()
        inputInjector?.cancelPress()
        connectionGeneration &+= 1
        connection = conn
        return connectionGeneration
    }

    private func isCurrentConnection(_ conn: NWConnection,
                                     generation: UInt64) -> Bool {
        ConnectionGenerationPolicy.accepts(
            callbackGeneration: generation,
            currentGeneration: connectionGeneration,
            isCurrentObject: connection === conn,
            stopped: stopped)
    }

    private func invalidateConnection() {
        keyframeRequests.retireInFlightRequest()
        stopCursorEcho()
        desktopInput.reset()
        pencilActions.reset(); pencilExtendedNegotiated = false
        pencilNegotiated = false
        inputInjector?.cancelPress()
        connectionGeneration &+= 1
        let previous = connection
        connection = nil
        let pending = admission; admission = nil
        pending?.cancel()
        let relay = usbTLSRelay; usbTLSRelay = nil
        relay?.onClosed = nil; relay?.stop()
        previous?.stateUpdateHandler = nil
        previous?.cancel()
    }

    private func cancelPendingReconnect() {
        reconnectGeneration &+= 1
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
    }

    private func becomeReady(_ conn: NWConnection, generation: UInt64) {
        guard isCurrentConnection(conn, generation: generation) else {
            Log.info("ignoring ready callback from stale connection generation=\(generation)")
            return
        }
        cancelPendingReconnect()
        connectionReady = false
        lastReceived = Date()
        receiveControl(on: conn, generation: generation)
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.isCurrentConnection(conn, generation: generation), !self.connectionReady else { return }
            self.failSecurity("未收到匹配的接收端确认，请更新对端应用并重新连接")
        }
        Task { await self.status("正在验证 \(self.endpointName) 的接收能力…") }
    }

    private func helloReady() {
        Log.info("connection ready to \(endpointName)")
        connectionReady = true
        keyframeRequests.retireInFlightRequest()
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
        startCursorEcho()
        if let path = connection?.currentPath {
            Log.info("TRANSPORT-PATH wiredEthernet=\(path.usesInterfaceType(.wiredEthernet)) wifi=\(path.usesInterfaceType(.wifi)) loopback=\(path.usesInterfaceType(.loopback)) pinnedInterface=\(directLinkInterfaceName ?? "system-route")")
        }
        lastReceived = Date()  // fresh grace period for the watchdog
    }

    private func failSecurity(_ message: String) {
        connectionReady = false
        dialGeneration += 1
        cancelPendingReconnect()
        invalidateConnection()
        Task { @MainActor in self.onSecurityError?(message) }
    }

    private func watchAuthenticatedConnection(_ conn: NWConnection, generation: UInt64) {
        conn.stateUpdateHandler = { [weak self] state in
            guard let self, self.isCurrentConnection(conn, generation: generation) else { return }
            switch state {
            case .failed, .waiting: self.scheduleReconnect()
            case .cancelled: self.connectionReady = false
            default: break
            }
        }
        becomeReady(conn, generation: generation)
    }

    private func connectTCP(_ endpoint: NWEndpoint, interface: NWInterface? = nil) {
        let options = NWProtocolTCP.Options()
        options.noDelay = true   // latency matters more than throughput here
        let tls: NWProtocolTLS.Options?
        let clientPlan: SecureClientAdmission?
        do {
            if securityPlan.encrypted {
                let plan = try securityPlan.admission(localName: Host.current().localizedName ?? "DisplayWeave Mac")
                clientPlan = plan
                tls = try AppleTLS.options(identity: securityPlan.identity, peerIsServer: true, queue: queue,
                                           acceptedFingerprint: { $0 == plan.fingerprint })
            } else { tls = nil; clientPlan = nil }
        } catch { failSecurity(error.localizedDescription); return }
        let params = NWParameters(tls: tls, tcp: options)
        params.serviceClass = .interactiveVideo
        params.requiredInterface = interface
        let conn = NWConnection(to: DirectCable.endpoint(endpoint, on: interface), using: params)
        let generation = adoptConnection(conn)
        if let clientPlan {
            let admission = AppleSecureAdmission(connection: conn, queue: queue) { [weak self] result in
                guard let self, self.isCurrentConnection(conn, generation: generation) else { conn.cancel(); return }
                self.admission = nil
                switch result {
                case .success:
                    self.securityPlan.didAuthenticate()
                    self.watchAuthenticatedConnection(conn, generation: generation)
                case .failure(let error):
                    if self.everConnected {
                        // A lost LAN/USB route may fail during the new TLS
                        // handshake. Keep the existing bounded recovery and
                        // handover policy, always with this same frozen pin.
                        Task { await self.status(error.localizedDescription + "；正在有限重试已配对连接") }
                        self.scheduleReconnect()
                    } else { self.failSecurity(error.localizedDescription) }
                }
            }
            self.admission = admission
            admission.startClient(clientPlan)
            return
        }
        conn.stateUpdateHandler = { [weak self] state in
            guard let self,
                  self.isCurrentConnection(conn, generation: generation) else {
                return
            }
            switch state {
            case .ready:
                self.becomeReady(conn, generation: generation)
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
                    if self.securityPlan.encrypted {
                        let relay = UsbmuxTLSRelay(tunnel: conn, queue: self.queue)
                        self.usbTLSRelay = relay
                        relay.onClosed = { [weak self, weak relay] in
                            guard let self, let relay, self.usbTLSRelay === relay,
                                  generation == self.dialGeneration, !self.stopped else { return }
                            self.scheduleReconnect()
                        }
                        relay.start { [weak self, weak relay] result in
                            guard let self, let relay, self.usbTLSRelay === relay,
                                  generation == self.dialGeneration, !self.stopped else { return }
                            switch result {
                            case .success(let port):
                                self.connectTCP(.hostPort(host: "127.0.0.1", port: .init(rawValue: port)!))
                            case .failure(let error): self.failSecurity(error.localizedDescription)
                            }
                        }
                        return
                    }
                    let connectionGeneration = self.adoptConnection(conn)
                    conn.stateUpdateHandler = { [weak self] state in
                        guard let self,
                              self.isCurrentConnection(
                                conn, generation: connectionGeneration) else {
                            return
                        }
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
                    self.becomeReady(conn, generation: connectionGeneration)
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

    private func scheduleReconnect(failureObservedAt: Date = Date()) {
        guard !stopped else { return }
        desktopInput.reset()
        pencilActions.reset(); pencilExtendedNegotiated = false
        inputInjector?.cancelPress()
        pencilNegotiated = false
        if everConnected {
            let now = Date()
            let since = DisconnectGracePolicy.startedAt(
                existing: disconnectedSince,
                failureObservedAt: failureObservedAt)
            if disconnectedSince == nil {
                disconnectedSince = since
                let remaining = DisconnectGracePolicy.remainingSeconds(
                    startedAt: since, now: now,
                    graceSeconds: disconnectGraceSeconds)
                Task { await status("连接已断开，最多重试 \(remaining) 秒…") }
            }
            if DisconnectGracePolicy.hasExpired(
                startedAt: since, now: now,
                graceSeconds: disconnectGraceSeconds) {
                if !disconnectCallbackPending {
                    disconnectCallbackPending = true
                    Log.info("device gone for >\(Int(disconnectGraceSeconds))s — ending session")
                    Task { @MainActor in self.onDisconnected?(.connectionLost) }
                }
                return
            }
        }
        guard reconnectWorkItem == nil else {
            Log.info("reconnect already scheduled — coalescing duplicate request")
            return
        }
        connectionReady = false
        dialGeneration += 1   // a USB dial still in flight must not adopt
        invalidateConnection()
        pendingSends = 0
        pendingSendStartedAt.removeAll()
        reconnectGeneration &+= 1
        let generation = reconnectGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  ConnectionGenerationPolicy.acceptsReconnectTask(
                    taskGeneration: generation,
                    currentGeneration: self.reconnectGeneration,
                    stopped: self.stopped) else { return }
            self.reconnectWorkItem = nil
            self.connect()
        }
        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 1.0, execute: workItem)
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
                let capturedFrames = self.capFrames
                self.capFrames = 0
                self.capWindowStart = Date()
                self.logCaptureFpsIfLimited(actualFps: capFps)
                let sorted = self.inputLatencies.sorted()
                let inp50 = sorted.isEmpty ? 0 : sorted[sorted.count / 2].rounded()
                let inp95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))].rounded()
                let stats = StreamDebugStats(
                    droppedFramesMac: self.dropsThisWindow,
                    queueDepthMac: self.pendingSends,
                    pendingEncodesMac: self.pendingEncodes,
                    totalPendingWorkMac: self.pendingSends + self.pendingEncodes,
                    pendingEncodePeak: self.pendingEncodeWork.peak,
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
                if self.settings.enableDebugStats {
                    let seconds = max(elapsed, 0.001)
                    Log.info("PIPELINE-STATS captureFps=\(capFps) encodedFps=\(Double(self.pipelineEncodedFrames) / seconds) sentFps=\(Double(self.pipelineSentFrames) / seconds) preEncodeAndOutputDrops=\(self.dropsThisWindow) pendingEncodes=\(self.pendingEncodes) encodeBudget=\(SendQueuePolicy.encodeBudget(fps: self.requestedCaptureFps)) pendingSends=\(self.pendingSends) sendCompletionMs=\(self.lastSendCompletionDelayMs) actualMbps=\(Double(self.pipelineSentBytes) * 8 / seconds / 1_000_000) encodeSubmitMaxMs=\(self.maxEncodeSubmissionMs) encodeSubmitAverageMs=\(self.encodeSubmissionMsTotal / Double(max(1, self.encodeSubmissionCount))) encoderPressureDrops=\(self.encoderDropsThisWindow)")
                }
                self.evaluateEncoderLoad(captures: capturedFrames, seconds: elapsed)
                self.encodeSubmissionMsTotal = 0
                self.encodeSubmissionCount = 0
                self.encoderDropsThisWindow = 0
                self.pipelineEncodedFrames = 0
                self.pipelineSentFrames = 0
                self.pipelineSentBytes = 0
                self.maxEncodeSubmissionMs = 0
                self.lastMacDropsSnapshot = self.dropsThisWindow
                self.dropsThisWindow = 0
            }
            self.schedulePing()
        }
    }

    private func evaluateEncoderLoad(captures: Int, seconds: Double) {
        guard encoderLoadAdjustmentID == nil, !decoderFpsAdjustmentInFlight,
              let activeStream = stream, var controller = encoderLoad else { return }
        let decision = controller.evaluate(.init(
            now: ProcessInfo.processInfo.systemUptime, seconds: seconds,
            captures: captures, outputs: pipelineEncodedFrames, encoderDrops: encoderDropsThisWindow,
            submissions: encodeSubmissionCount,
            submissionMs: encodeSubmissionMsTotal / Double(max(1, encodeSubmissionCount)),
            pendingSends: pendingSends, sendCompletionMs: lastSendCompletionDelayMs))
        encoderLoad = controller
        guard let decision else { return }
        let target = decision.configuration
        let id = UUID()
        encoderLoadAdjustmentID = id
        cancelDropReplay()
        _ = captureFrames.begin() // no old-size cached frame can reach the new encoder
        let config = makeCaptureConfiguration(width: target.width, height: target.height, fps: target.fps)
        Log.info("ENCODER-LOAD action=\(decision.recovering ? "recover" : "reduce") raster=\(target.width)x\(target.height) fps=\(target.fps) priority=\(settings.priority.rawValue) desktopUnchanged=true")
        encoderLoadAdjustmentTask = Task { [weak self, weak activeStream] in
            guard let self, let activeStream else { return }
            do {
                try Task.checkCancellation()
                try await activeStream.updateConfiguration(config)
                try Task.checkCancellation()
                self.queue.async {
                    guard !self.stopped, !self.pipelineFailureReported,
                          self.stream === activeStream, self.encoderLoadAdjustmentID == id else { return }
                    defer { self.encoderLoadAdjustmentID = nil; self.encoderLoadAdjustmentTask = nil }
                    self.retireEncoder()
                    self.activeStreamWidth = target.width
                    self.activeStreamHeight = target.height
                    self.requestedCaptureFps = target.fps
                    do {
                        // A codec fallback may have completed while SCK updated.
                        // Use the current codec owned by this capture pipeline.
                        try self.setupEncoder(width: target.width, height: target.height,
                                              fps: target.fps, preferredCodec: self.streamCodec)
                        self.sendStreamConfig(width: target.width, height: target.height)
                        self.requestKeyframe(.streamReconfigure)
                    } catch { self.failPipeline(error) }
                }
            } catch {
                self.queue.async {
                    guard !self.stopped, self.stream === activeStream,
                          self.encoderLoadAdjustmentID == id else { return }
                    self.encoderLoadAdjustmentID = nil; self.encoderLoadAdjustmentTask = nil
                    // SCK may have applied part of a failed configuration. Stop
                    // cleanly rather than encoding mismatched dimensions forever.
                    self.failPipeline(DisplayUnitCoordinator.failure("自动调整编码负载失败，请重新连接；也可在串流设置中关闭自动适配。"))
                }
            }
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
            if self.connectionReady { self.desktopInput.refresh() }
            if self.connectionReady && self.pencilExtendedNegotiated { self.pencilActions.refresh() }
            if !AXIsProcessTrusted() { self.inputInjector?.cancelPress() }
            if self.connectionReady, Date().timeIntervalSince(self.lastReceived) > 5 {
                Log.info("watchdog: nothing from the phone for >5s — reconnecting")
                Task { await self.status("连接无响应，正在重新连接…") }
                // Anchor the 10-second grace to the last proof that the peer
                // was alive. Starting it here would add the watchdog's five
                // seconds to the advertised disconnect timeout.
                self.scheduleReconnect(failureObservedAt: self.lastReceived)
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

    private func stopCursorEcho() {
        cursorEcho.stop()
        cursorImageTimer?.cancel(); cursorImageTimer = nil
        cursorImageLock.withLock { cursorImageContext = nil }
        cursorImages.reset()
    }

    /// Called only on the sender queue; the echo owns an independent sampling
    /// queue and retains only this ready connection until stop/replacement.
    private func startCursorEcho() {
        guard localCursor, connectionReady, let connection,
              captureDisplayID != 0, stream != nil, !stopped else { return }
        let displayID = captureDisplayID
        cursorImages.reset()
        cursorImageLock.withLock {
            cursorImageContext = (displayID, wireConnectionGeneration, encoderGeneration, 0)
        }
        cursorEcho.start(sample: { CursorPosition.sample(displayID: displayID) },
                         write: CursorEcho.writer(on: connection),
                         log: settings.enableDebugStats ? { Log.info($0) } : nil)
        scheduleCursorImagePoll()
    }

    /// Sprite changes (arrow ↔ I-beam ↔ resize…) must land fast or the wrong
    /// cursor shows over hot areas — poll at 30Hz on the main thread (NSCursor
    /// is AppKit), hash the raw bitmap, and only PNG-encode + send on change.
    ///
    /// A dedicated timer (cancelled+replaced here, like the position sampler above) — not
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

    private func pollCursorImage() {
        // Display size read LIVE, not snapshotted at capture start: the
        // HiDPI mode settles (and macOS re-flips it) asynchronously, and a
        // sprite normalized against the 1x size renders at half size on the
        // device. Mixing the size into the dedup hash re-sends the sprite
        // whenever the mode flips, so the proportion always heals.
        guard let context = cursorImageLock.withLock({ cursorImageContext }),
              let cursor = NSCursor.currentSystem else { return }
        let displaySize = CGDisplayBounds(context.displayID).size   // points, current mode
        guard displaySize.width > 0, displaySize.height > 0 else { return }
        let image = cursor.image
        guard let tiff = image.tiffRepresentation else { return }
        let hash = tiff.hashValue ^ Int(displaySize.width) &* 31
        guard hash != context.hash else { return }
        guard let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]),
              png.count < 24_000 else { return }
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
        let current = cursorImageLock.withLock {
            guard let active = cursorImageContext, active.displayID == context.displayID,
                  active.wire == context.wire, active.encoder == context.encoder,
                  active.hash != hash else { return false }
            cursorImageContext?.hash = hash
            return true
        }
        guard current else { return }
        if let token = cursorImages.offer((msg, context.wire, context.encoder)) {
            queue.async { self.sendCursorImage(token) }
        }
    }

    private func sendCursorImage(_ token: LatestValueRelay<(json: String, wire: UInt64, encoder: UInt64)>.Token) {
        guard let image = cursorImages.take(token) else { return }
        guard connectionReady, !stopped, let connection,
              wireConnectionGeneration == image.wire, encoderGeneration == image.encoder else {
            if let next = cursorImages.complete(token) { sendCursorImage(next) }
            return
        }
        connection.send(content: ReceiverFrameDecoder.frame(Data(image.json.utf8)),
                        completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            if let next = self.cursorImages.complete(token) { self.sendCursorImage(next) }
        })
    }

    // MARK: - Control messages (phone -> Mac)

    private func receiveControl(on conn: NWConnection, generation: UInt64) {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self,
                  self.isCurrentConnection(conn, generation: generation) else {
                return
            }
            guard error == nil, let data, data.count == 4 else {
                self.handleControlReadEnd(
                    on: conn, generation: generation,
                    isComplete: isComplete, error: error)
                return
            }
            let len = Int(UInt32(bigEndian: data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
            guard len > 0, len < 1 << 20 else {
                self.handleConnectionClosure(.endSession)
                return
            }
            conn.receive(minimumIncompleteLength: len, maximumLength: len) { [weak self] payload, _, isComplete, error in
                guard let self,
                      self.isCurrentConnection(conn, generation: generation) else {
                    return
                }
                guard error == nil, let payload, payload.count == len else {
                    self.handleControlReadEnd(
                        on: conn, generation: generation,
                        isComplete: isComplete, error: error)
                    return
                }
                self.handleControl(payload)
                self.receiveControl(on: conn, generation: generation)
            }
        }
    }

    private func handleControlReadEnd(on conn: NWConnection, generation: UInt64,
                                      isComplete: Bool,
                                      error: NWError?) {
        guard isCurrentConnection(conn, generation: generation) else { return }
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

    private func sendPencilConfiguration() {
        guard connectionReady, pencilNegotiated else { return }
        var object: [String: Any] = ["type": "inputConfig", "inputCaps": pencilExtendedNegotiated
            ? [PencilProtocol.capability, PencilProtocol.extendedCapability] : [PencilProtocol.capability],
            "pencilActionStatus": pencilActions.status]
        if let session = pencilActions.session { object["pencilActionSession"] = session }
        if let data = try? JSONSerialization.data(withJSONObject: object) {
            sendJSONFrame(String(decoding: data, as: UTF8.self))
        }
    }

    private func handleControl(_ payload: Data) {
        lastReceived = Date()
        if ReconnectPeerReadinessPolicy.clearsDisconnectGrace(for: .peerMessage) {
            disconnectedSince = nil
            disconnectCallbackPending = false
        }
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let type = obj["type"] as? String else {
            Log.info("unparseable control message (\(payload.count) bytes)")
            return
        }
        // A new connection must identify itself before it can drive input,
        // telemetry, decoder negotiation or re-use captured frames.
        guard connectionReady || type == "hello" else { return }
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
        case "macReceiverStats":
            if settings.enableDebugStats,
               let data = try? JSONSerialization.data(withJSONObject: obj, options: .sortedKeys),
               let line = String(data: data, encoding: .utf8) {
                Log.info("MAC-RECEIVER-STATS \(line)")
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
                guard securityPlan.permitsHello(id: info.id) else {
                    failSecurity("接收端身份不匹配或曾经配对，已拒绝未认证连接；请重新配对")
                    return
                }
                guard info.hasValidGeometry else {
                    Log.info("rejected invalid receiver geometry or video capabilities")
                    handleConnectionClosure(.endSession)
                    return
                }
                guard info.id != StreamReceiver.installID else {
                    handleConnectionClosure(.endSession)
                    return
                }
                let previous = lastHello
                lastHello = info
                if !connectionReady { helloReady() }
                desktopInput.hello(encrypted: encrypted, capabilities: info.isMacReceiver ? info.inputCaps : nil)
                let supportsPencil = !info.isMacReceiver && PencilProtocol.supports(info.inputCaps)
                if pencilNegotiated && !supportsPencil { inputInjector?.cancelPress() }
                pencilNegotiated = supportsPencil
                let extended = supportsPencil && encrypted && info.inputCaps?.contains(PencilProtocol.extendedCapability) == true
                if pencilExtendedNegotiated && !extended { inputInjector?.cancelPress() }
                pencilExtendedNegotiated = extended
                pencilActions.begin(encrypted: encrypted, supported: pencilExtendedNegotiated)
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
                } else if (mode == .extend || info.usesAppleVideoCapabilities), stream != nil, let previous,
                          !previous.sameDisplayConfiguration(as: info) {
                    // Phone rotated — rebuild after a short debounce so a
                    // flurry of orientation flips settles into one rebuild.
                    scheduleReconfiguration(delay: .milliseconds(300))
                }
            }
        case "streamConfigAck", "decoderReady", "firstFrameRendered":
            handleReceiverProtocolProgress(type: type, object: obj)
        case "connectionState":
            let state = obj["state"] as? String ?? "unknown"
            let reason = obj["reason"] as? String ?? ""
            Log.info("receiver connection state=\(state) reason=\(reason)")
        case "desktopInput":
            guard lastHello?.isMacReceiver == true else { return }
            desktopInput.handle(payload)
        case "pencilAction":
            guard pencilExtendedNegotiated else { return }
            pencilActions.handle(payload)
        case "pencil", "pencil2":
            guard pencilNegotiated else { return }
            guard type != "pencil2" || pencilExtendedNegotiated else { return }
            guard let sample = PencilSample(message: obj) else { inputInjector?.cancelPress(); return }
            inputInjector?.handlePencil(sample)
        case "proximity":
            guard pencilNegotiated else { return }
            guard let entering = obj["entering"] as? Bool,
                  let x = obj["x"] as? Double, let y = obj["y"] as? Double,
                  x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else {
                inputInjector?.cancelPress(); return
            }
            inputInjector?.handleProximity(entering: entering, x: x, y: y)
        case "touch":
            guard lastHello?.isMacReceiver != true else { return }
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
            guard lastHello?.isMacReceiver != true else { return }
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
                macCodecFallback.recordFailure(.hevc)
                decoderRecoveryEvent = "codec-fallback"
                retireEncoder()
                do {
                    try setupEncoder(width: max(activeStreamWidth, 2),
                                     height: max(activeStreamHeight, 2),
                                     fps: requestedCaptureFps,
                                     preferredCodec: .h264)
                    sendStreamConfig(width: activeStreamWidth, height: activeStreamHeight)
                    requestKeyframe(.codecFallback)
                } catch { failPipeline(error) }
            }
        default:
            switch unknownControlLog.record(type) {
            case .logType(let type): Log.info("unknown control message type: \(type)")
            case .logSuppression(let limit): Log.info("unknown control types exceed \(limit); suppressing further names")
            case .none: break
            }
        }
    }

    private func finishSessionAfterReceiverExit() {
        connectionReady = false
        invalidateConnection()
        Task { @MainActor in self.onDisconnected?(.receiverExit) }
    }

    private func failPipeline(_ error: Error) {
        guard !stopped, !pipelineFailureReported else { return }
        pipelineFailureReported = true
        connectionReady = false
        stopCursorEcho()
        cancelPendingReconnect()
        invalidateConnection()
        Log.info("sender pipeline failed: \(error.localizedDescription)")
        // Do not await cleanup on the video queue or from the reconfiguration
        // task: stop() must be able to join that task before releasing its display.
        Task { @MainActor in
            guard !self.stopped else { return }
            self.onPipelineFailure?(error)
        }
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
        if type == "decoderReady",
           let selectedDecoderMaxFps = int64(object["selectedDecoderMaxFps"]) {
            applySelectedDecoderFpsCap(Int(selectedDecoderMaxFps))
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

    private func applySelectedDecoderFpsCap(_ reportedFps: Int) {
        guard let decoderCap = RefreshRatePolicy.decoderDowngrade(
                currentFps: requestedCaptureFps,
                reportedMaxFps: reportedFps),
              !decoderFpsAdjustmentInFlight,
              let activeStream = stream else { return }
        let updatedConfiguration = makeCaptureConfiguration(
            width: activeStreamWidth,
            height: activeStreamHeight,
            fps: decoderCap)
        decoderFpsAdjustmentInFlight = true
        Log.info("selected decoder requires fps downgrade current=\(requestedCaptureFps) selectedDecoderMaxFps=\(decoderCap)")
        Task { [weak self, weak activeStream] in
            guard let self else { return }
            guard let activeStream else {
                self.queue.async {
                    self.decoderFpsAdjustmentInFlight = false
                }
                return
            }
            do {
                try await activeStream.updateConfiguration(updatedConfiguration)
                self.queue.async {
                    guard self.stream === activeStream else {
                        self.decoderFpsAdjustmentInFlight = false
                        return
                    }
                    self.requestedCaptureFps = decoderCap
                    self.retireEncoder()
                    defer { self.decoderFpsAdjustmentInFlight = false }
                    do {
                        try self.setupEncoder(
                            width: max(self.activeStreamWidth, 2),
                            height: max(self.activeStreamHeight, 2),
                            fps: decoderCap,
                            preferredCodec: self.streamCodec)
                        self.sendStreamConfig(
                            width: self.activeStreamWidth,
                            height: self.activeStreamHeight)
                        self.requestKeyframe(.streamReconfigure)
                        self.decoderRecoveryEvent = "decoder-fps-downgrade"
                    } catch { self.failPipeline(error) }
                }
            } catch {
                self.queue.async {
                    self.decoderFpsAdjustmentInFlight = false
                    Log.info("decoder fps downgrade failed: \(error)")
                }
            }
        }
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

    private func setupEncoder(width: Int, height: Int, fps: Int, preferredCodec: StreamCodec) throws {
        cancelDropReplay()
        let preferredCodec = macCodecFallback.codec(for: preferredCodec,
                                                   isMacReceiver: lastHello?.usesAppleVideoCapabilities == true)
        if encoderGeneration != 0 {
            pendingEncodeWork.discard(generation: encoderGeneration)
        }
        keyframeRequests.retireInFlightRequest()
        encoderGeneration &+= 1
        let finalFps = lastHello?.usesAppleVideoCapabilities == true ? max(1, min(120, fps)) : RefreshRatePolicy.sanitize(fps)
        streamCodec = preferredCodec
        let automaticBitrate = StreamEncodingPolicy.bitrate(
            width: width, height: height, fps: finalFps, codec: preferredCodec,
            quality: quality, transport: bitrateTransport)
        streamBitrate = selectedBitrate(automatic: automaticBitrate, codec: preferredCodec)
        encodedFramesWindow = 0
        encodedBytesWindow = 0
        localEncodedFrames = 0
        localSentFrames = 0
        pipelineEncodedFrames = 0
        pipelineSentFrames = 0
        pipelineSentBytes = 0
        capFrames = 0
        maxEncodeSubmissionMs = 0
        encodeSubmissionMsTotal = 0
        encodeSubmissionCount = 0
        encoderDropsThisWindow = 0
        capWindowStart = Date()
        localCongestionWindowStart = ProcessInfo.processInfo.systemUptime
        lastLocalOldestPendingSendAgeMs = 0
        lastLocalEncodedFps = 0
        lastLocalSentFps = 0
        lastSendCompletionDelayMs = 0
        encodeLatencyMsWindow.removeAll(keepingCapacity: true)
        encodeStatsWindowStart = Date()

        // Prefer low-latency rate control, but don't require it on encoders
        // that reject that specification (notably some Intel/AMD Macs).
        // Adapted from upstream d9eb302; keep our HEVC hardware requirement.
        let lowLatency = UserDefaults.standard.object(forKey: "lowlatency") == nil
            || UserDefaults.standard.bool(forKey: "lowlatency")
        adaptiveBitrateController = nil
        let selected = try EncoderSessionFactory.make(preferredCodec: preferredCodec, lowLatency: lowLatency, create: { attempt in
            let automatic = StreamEncodingPolicy.bitrate(
                width: width, height: height, fps: finalFps, codec: attempt.codec,
                quality: quality, transport: bitrateTransport)
            return try encoderWork.perform {
                try createEncoder(width: width, height: height, fps: finalFps,
                    codec: attempt.codec, lowLatency: attempt.lowLatency,
                    bitrate: selectedBitrate(automatic: automatic, codec: attempt.codec))
            }
        }, onFailure: { attempt, error in
            Log.info("ENCODER-ATTEMPT codec=\(attempt.codec.rawValue) lowLatencyRC=\(attempt.lowLatency) failed: \(error.localizedDescription)")
        })
        if preferredCodec == .hevc, selected.attempt.codec == .h264 {
            macCodecFallback.recordFailure(.hevc)
            Log.info("HEVC encoder unavailable; falling back to H.264")
        }
        encoder = selected.session
        streamCodec = selected.attempt.codec
        let selectedAutomatic = StreamEncodingPolicy.bitrate(
            width: width, height: height, fps: finalFps, codec: streamCodec,
            quality: quality, transport: bitrateTransport)
        streamBitrate = selectedBitrate(automatic: selectedAutomatic, codec: streamCodec)
        adaptiveBitrateController = settings.bitrateMode == .auto
            ? AdaptiveBitrateController(
                initialBitrate: streamBitrate,
                bounds: StreamEncodingPolicy.bitrateBounds(
                    codec: streamCodec, transport: bitrateTransport),
                localRecovery: lastHello?.isMacReceiver == true)
            : nil
        lastAdaptiveDecision = nil
        Task { @MainActor in onTargetBitrate?(Double(streamBitrate) / 1_000_000) }
        Log.info("encoder ready: \(width)x\(height) \(streamCodec.label) fps=\(finalFps) bitrate=\(streamBitrate / 1_000_000)Mbps keyframeInterval=\(KeyframePolicy.frameInterval(fps: finalFps, transport: bitrateTransport)) quality=\(quality.rawValue) lowLatencyRequested=\(lowLatency) lowLatencyRC=\(selected.attempt.lowLatency)")
        if stream != nil { startCursorEcho() }
    }

    private func retireEncoder() {
        if let encoder { encoderWork.perform { VTCompressionSessionInvalidate(encoder) } }
        encoder = nil
    }

    private func createEncoder(width: Int, height: Int, fps: Int, codec: StreamCodec,
                               lowLatency: Bool, bitrate: Int) throws -> VTCompressionSession {
        var session: VTCompressionSession?
        let codecType: CMVideoCodecType = codec == .hevc
            ? kCMVideoCodecType_HEVC
            : kCMVideoCodecType_H264
        var specification: [String: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true
        ]
        if lowLatency {
            specification[kVTVideoEncoderSpecification_EnableLowLatencyRateControl as String] = true
        }
        if codec == .hevc, lastHello?.isMacReceiver == true {
            specification[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String] = true
        }
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: Int32(width), height: Int32(height),
            codecType: codecType,
            encoderSpecification: specification as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        guard status == noErr, let encoder = session else {
            if let session { VTCompressionSessionInvalidate(session) }
            throw NSError(domain: "MacSender.Encoder", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "VTCompressionSessionCreate status=\(status), session unavailable"
            ])
        }
        var prepared = false
        defer { if !prepared { VTCompressionSessionInvalidate(encoder) } }
        // Low-latency settings: real-time, no B-frames, periodic keyframes.
        VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        let profile: CFString = codec == .hevc
            ? kVTProfileLevel_HEVC_Main_AutoLevel
            : kVTProfileLevel_H264_High_AutoLevel
        VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_ProfileLevel, value: profile)
        VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                             value: KeyframePolicy.frameInterval(
                                fps: fps, transport: bitrateTransport) as CFNumber)
        VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,
                             value: KeyframePolicy.defaultSeconds(transport: bitrateTransport) as CFNumber)
        let frameDelayLimit = SendQueuePolicy.frameDelayLimit(fps: fps)
        let frameDelayStatus = VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: frameDelayLimit as CFNumber)
        VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber)
        let bytesPerSecond = max(bitrate / 8, 1)
        VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_DataRateLimits,
                             value: [bytesPerSecond, 1] as CFArray)
        VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        let speedStatus = VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, value: kCFBooleanTrue)
        let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(encoder)
        guard prepareStatus == noErr else {
            throw NSError(domain: "MacSender.Encoder", code: Int(prepareStatus), userInfo: [
                NSLocalizedDescriptionKey: "VTCompressionSessionPrepareToEncodeFrames status=\(prepareStatus)"
            ])
        }
        prepared = true
        var hardwareValue: Unmanaged<CFTypeRef>?
        let hardwareStatus = VTSessionCopyProperty(encoder,
            key: kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder,
            allocator: nil, valueOut: &hardwareValue)
        let hardware = hardwareValue?.takeRetainedValue()
        var encoderIDValue: Unmanaged<CFTypeRef>?
        VTSessionCopyProperty(encoder, key: kVTCompressionPropertyKey_EncoderID,
                              allocator: nil, valueOut: &encoderIDValue)
        let encoderID = encoderIDValue?.takeRetainedValue()
        Log.info("ENCODER-IMPLEMENTATION hardware=\(hardwareStatus == noErr ? String(describing: hardware ?? "unknown" as CFString) : "unknown") hardwareQueryStatus=\(hardwareStatus) encoderID=\(encoderID ?? "unknown" as CFString) frameDelayLimit=\(frameDelayLimit) frameDelayStatus=\(frameDelayStatus) speedPriorityStatus=\(speedStatus) prepareStatus=\(prepareStatus)")
        return encoder
    }

    // MARK: - Capture callback

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard !stopped, !pipelineFailureReported, self.stream === stream, type == .screen,
              CMSampleBufferIsValid(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        let info = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]])?.first
        if let status = info?[.status] as? Int, status != SCFrameStatus.complete.rawValue { return }
        if mode == .extend, captureDisplayID != 0,
           let rect = info?[.screenRect] as? NSDictionary,
           let source = CGRect(dictionaryRepresentation: rect),
           captureSourceCheck.frame(screenRect: source, expected: CGDisplayBounds(captureDisplayID)) {
            guard captureRecovery.recoverWrongSource() else {
                failPipeline(DisplayUnitCoordinator.failure("采集持续指向其他显示器，已停止会话。请重新连接并检查显示器排列。"))
                return
            }
            Log.info("CAPTURE-SOURCE-MISMATCH reattach=\(captureRecovery.wrongSourceRecoveries)/3; discarding cached pixels")
            retireCaptureForRecovery()
            return
        }
        guard encoderLoadAdjustmentID == nil,
              CVPixelBufferGetWidth(pixelBuffer) == activeStreamWidth,
              CVPixelBufferGetHeight(pixelBuffer) == activeStreamHeight else { return }
        captureRecovery.finished(succeeded: true, consoleAvailable: true)
        captureFrames.offer(pixelBuffer, generation: captureFrames.generation)
        lastCaptureAt = Date()
        capFrames += 1

        // No receiver, or the socket is backed up: skip this frame entirely.
        guard connectionReady else { return }
        let queueDecision = SendQueuePolicy.decision(
            pendingSends: pendingSends, pendingEncodes: pendingEncodes,
            sendBudget: maxPendingSends,
            encodeBudget: SendQueuePolicy.encodeBudget(fps: requestedCaptureFps),
            currentDroppedFrames: dropsThisWindow)
        if queueDecision.shouldDrop {
            if queueDecision.forceKeyframe, let reason = queueDecision.reason {
                requestKeyframe(reason)
            }
            dropsThisWindow = queueDecision.droppedFrames
            if pendingSends < maxPendingSends { encoderDropsThisWindow += 1 }
            dropsTotal += 1
            scheduleDropReplay()
            return
        }

        encode(pixelBuffer, pts: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }

    private func encode(_ pixelBuffer: CVPixelBuffer, pts: CMTime) {
        guard !stopped, !pipelineFailureReported, connectionReady, stream != nil, let encoder else { return }
        guard pipelineHasCapacity else { scheduleDropReplay(); return }
        let capturedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        let encodedForWireGeneration = wireConnectionGeneration
        let encodedForEncoderGeneration = encoderGeneration
        let encodeWorkID = pendingEncodeWork.begin(
            generation: encodedForEncoderGeneration)
        if benchmarkRecorder != nil {
            benchmarkPendingEncodePeak = max(
                benchmarkPendingEncodePeak, pendingEncodes)
        }
        let protocolFrameIdentity = lastHello?.supportsProtocolV2 == true
            ? protocolIdentity.nextFrame()
            : nil
        var frameProperties: CFDictionary?
        let forcedKeyframeRequest = keyframeRequests.consumePendingRequest()
        if let forcedKeyframeRequest {
            frameProperties = [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue!] as CFDictionary
            decoderRecoveryEvent = forcedKeyframeRequest.reason.rawValue
            Log.info("forcing keyframe reason=\(forcedKeyframeRequest.reason.rawValue) requests=\(keyframeRequests.requestCount) coalesced=\(keyframeRequests.coalescedCount)")
        }
        let submission = EncoderFrameSubmission(encoder: encoder, pixels: pixelBuffer, properties: frameProperties)
        let encodeStart = Date()
        let duration = CMTime(
            value: 1,
            timescale: CMTimeScale(lastHello?.isMacReceiver == true ? requestedCaptureFps : StreamEncodingPolicy.frameDurationTimescale(fps: requestedCaptureFps)))
        let accepted = encoderWork.submit(limit: SendQueuePolicy.encodeBudget(fps: requestedCaptureFps)) { [weak self] in
            guard let self else { return }
            let submissionStart = ProcessInfo.processInfo.systemUptime
            let status = VTCompressionSessionEncodeFrame(
                submission.encoder,
                imageBuffer: submission.pixels,
                presentationTimeStamp: pts,
                duration: duration,
                frameProperties: submission.properties,
                infoFlagsOut: nil
            ) { [weak self] status, _, buffer in
                guard let self else { return }
                self.queue.async {
                    self.handleEncodedFrame(
                        status: status, buffer: buffer,
                        forcedKeyframeRequest: forcedKeyframeRequest,
                        capturedAtMs: capturedAtMs,
                        encodedForWireGeneration: encodedForWireGeneration,
                        encodedForEncoderGeneration: encodedForEncoderGeneration,
                        encodeWorkID: encodeWorkID,
                        protocolFrameIdentity: protocolFrameIdentity,
                        encodeStart: encodeStart)
                }
            }
            let submissionMs = (ProcessInfo.processInfo.systemUptime - submissionStart) * 1_000
            self.queue.async {
                guard !self.stopped, encodedForWireGeneration == self.wireConnectionGeneration,
                      encodedForEncoderGeneration == self.encoderGeneration else { return }
                self.maxEncodeSubmissionMs = max(self.maxEncodeSubmissionMs, submissionMs)
                self.encodeSubmissionMsTotal += submissionMs
                self.encodeSubmissionCount += 1
                if status != noErr, self.pendingEncodeWork.complete(
                    generation: encodedForEncoderGeneration, workID: encodeWorkID) {
                    self.keyframeRequests.complete(forcedKeyframeRequest, encodedKeyframe: false)
                    self.handleEncodeFailure(status: status)
                }
            }
        }
        if accepted {
            // Cancel only the replay covered by this admission. New captures can
            // arrive while the worker blocks and must retain their own replay.
            cancelDropReplay()
        } else {
            pendingEncodeWork.complete(generation: encodedForEncoderGeneration, workID: encodeWorkID)
            keyframeRequests.complete(forcedKeyframeRequest, encodedKeyframe: false)
            dropsThisWindow += 1
            encoderDropsThisWindow += 1
            dropsTotal += 1
            scheduleDropReplay()
        }
    }

    private var pipelineHasCapacity: Bool {
        encoderLoadAdjustmentID == nil && !SendQueuePolicy.shouldDrop(pendingSends: pendingSends, pendingEncodes: pendingEncodes,
            sendBudget: maxPendingSends, encodeBudget: SendQueuePolicy.encodeBudget(fps: requestedCaptureFps))
    }

    private func cancelDropReplay() {
        captureFrames.submitted()
        dropReplayWork?.cancel(); dropReplayWork = nil; dropReplayID = nil
    }

    private func scheduleDropReplay() {
        guard !stopped, !pipelineFailureReported, connectionReady, stream != nil,
              encoderLoadAdjustmentID == nil else { return }
        captureFrames.dropped(at: ProcessInfo.processInfo.systemUptime)
        armDropReplay()
    }

    private func armDropReplay() {
        guard let deadline = captureFrames.deadline else { return }
        dropReplayWork?.cancel()
        let id = UUID(), generation = captureFrames.generation
        dropReplayID = id
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped, !self.pipelineFailureReported, self.connectionReady,
                  self.stream != nil, self.dropReplayID == id, self.captureFrames.generation == generation else { return }
            self.dropReplayWork = nil; self.dropReplayID = nil
            if let frame = self.captureFrames.takeDue(at: ProcessInfo.processInfo.systemUptime,
                                                       ready: self.pipelineHasCapacity) {
                self.encode(frame, pts: CMClockGetTime(CMClockGetHostTimeClock()))
            } else { self.armDropReplay() }
        }
        dropReplayWork = work
        queue.asyncAfter(deadline: .now() + max(0, deadline - ProcessInfo.processInfo.systemUptime), execute: work)
    }

    private func handleEncodedFrame(
        status: OSStatus,
        buffer: CMSampleBuffer?,
        forcedKeyframeRequest: KeyframeRequestTracker.Request?,
        capturedAtMs: Int64,
        encodedForWireGeneration: UInt64,
        encodedForEncoderGeneration: UInt64,
        encodeWorkID: GenerationWorkCounter.WorkID,
        protocolFrameIdentity: StreamProtocolFrameIdentity?,
        encodeStart: Date
    ) {
        guard pendingEncodeWork.complete(
                generation: encodedForEncoderGeneration,
                workID: encodeWorkID) else {
            Log.info("dropping duplicate/unmatched encode completion")
            return
        }
        switch EncoderCallbackPolicy.disposition(
            status: status,
            hasSampleBuffer: buffer != nil,
            isCurrentSession: connectionReady && !pipelineFailureReported
                && encodedForWireGeneration == wireConnectionGeneration
                && encodedForEncoderGeneration == encoderGeneration
        ) {
        case .stale:
            // Errors are callbacks too: an old socket's failed encode must not
            // recreate the encoder or stop the replacement connection.
            Log.info("dropping encoded frame from stale wire/encoder generation")
            return
        case .failed:
            if forcedKeyframeRequest != nil {
                keyframeRequests.complete(forcedKeyframeRequest, encodedKeyframe: false)
            }
            handleEncodeFailure(status: status)
            return
        case .dropped:
            if forcedKeyframeRequest != nil {
                keyframeRequests.complete(forcedKeyframeRequest, encodedKeyframe: false)
            }
            dropsThisWindow += 1
            dropsTotal += 1
            recordEncodeFailure("encoder dropped frame without output status=\(status) codec=\(streamCodec.label)")
            recoverEncoderAfterFailure(transient: true)
            return
        case .output:
            break
        }
        guard let buffer else { return }
        encoderFailureRecovery.producedOutput(at: ProcessInfo.processInfo.systemUptime)
        let isKeyframe = Self.isKeyframe(buffer)
        if forcedKeyframeRequest != nil {
            keyframeRequests.complete(forcedKeyframeRequest, encodedKeyframe: isKeyframe)
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
        recordEncodeFailure("encode failed for \(streamCodec.label): \(status)")
        recoverEncoderAfterFailure(transient: status == kVTVideoEncoderNotAvailableNowErr)
    }

    private func recoverEncoderAfterFailure(transient: Bool) {
        switch encoderFailureRecovery.failed(transient: transient) {
        case .retry:
            requestKeyframe(.encodedFrameDiscarded)
            scheduleDropReplay()
        case .exhausted:
            cancelDropReplay()
            failPipeline(DisplayUnitCoordinator.failure("视频编码连续失败，已停止会话。请重新连接；若仍失败，请降低分辨率或帧率。"))
        case .rebuild:
            let fallback = streamCodec == .hevc
            if fallback { macCodecFallback.recordFailure(.hevc) }
            Log.info("rebuilding encoder after failure attempt=\(encoderFailureRecovery.rebuilds) fallback=\(fallback)")
            retireEncoder()
            do {
                try setupEncoder(width: max(activeStreamWidth, 2),
                                 height: max(activeStreamHeight, 2),
                                 fps: requestedCaptureFps, preferredCodec: .h264)
                sendStreamConfig(width: activeStreamWidth, height: activeStreamHeight)
                requestKeyframe(fallback ? .codecFallback : .decoderReset)
                scheduleDropReplay()
            } catch { failPipeline(error) }
        }
    }

    private func recordEncodeFailure(_ detail: String) {
        switch encodeFailureLog.record(detail, at: ProcessInfo.processInfo.systemUptime) {
        case .none: break
        case .report(let report): Log.info("\(report.detail) count=\(report.count)")
        case .schedule(let delay):
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.stopped else { return }
                self.encodeFailureLogWork = nil
                if let report = self.encodeFailureLog.flush(at: ProcessInfo.processInfo.systemUptime) {
                    Log.info("\(report.detail) count=\(report.count)")
                }
            }
            encodeFailureLogWork = work
            queue.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private static func isKeyframe(_ sample: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sample, createIfNecessary: false) as? [[CFString: Any]],
              let first = attachments.first else { return true }
        return !(first[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
    }

    private func recordEncodedFrame(bytes: Int, isKeyframe: Bool, latencyMs: Double) {
        pipelineEncodedFrames += 1
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
        if Self.isKeyframe(sample), let fmt = CMSampleBufferGetFormatDescription(sample) {
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
        switch transport {
        case .tcp:
            transportName = lastHello?.isMacReceiver == true ? "lan" : "wifi"
        case .usb, .androidAdb:
            transportName = "usb"
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
            maxFrameBytes: lastHello?.negotiatedMaxFrameBytes,
            exactFrameRate: lastHello?.usesAppleVideoCapabilities == true)
        sendJSONFrame(message.json)
        let description = "编码 \(width)×\(height) · \(streamCodec.label) · 目标 \(requestedCaptureFps) fps"
        var limits: [String] = []
        if settings.bitrateMode == .manual, settings.bitratePreset.bitsPerSecond != streamBitrate {
            limits.append("请求 \(settings.bitratePreset.megabits) Mbps，按 \(streamCodec.label)／\(bitrateTransport == .usb ? "USB" : "局域网") 范围以 \(streamBitrate / 1_000_000) Mbps 生效")
        }
        if let load = encoderLoad, load.current != load.original {
            limits.append("已按编码负载自动适配，桌面大小不变；可选帧率优先或在设置中关闭自动适配")
        } else if let requested = settings.fpsMode.userSelectedFps, requested > requestedCaptureFps {
            limits.append("请求 \(requested) fps，受屏幕或解码能力限制；Apple 接收端可尝试“帧率优先”")
        }
        if mode == .extend, let info = lastHello, info.isMacReceiver {
            let desktop = MacReceiverPolicy.plan(info: info, settings: settings)
            if width < desktop.pointsWide * desktop.scale || height < desktop.pointsHigh * desktop.scale {
                limits.append("传输画面低于桌面像素尺寸；画质、解码能力或编码负载会限制细节，不改变逻辑桌面")
            }
        }
        let explanation = limits.isEmpty ? nil : limits.joined(separator: "。")
        Task { @MainActor in onStreamDescription?(description, explanation) }
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
            self.pipelineSentFrames += 1
            self.pipelineSentBytes += frame.count
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
                androidQueueDepth: max(Int(receiver.androidQueueDepth ?? 0), 0),
                transport: bitrateTransport),
            mode: settings.bitrateMode)
        guard let decision else { return }
        applyAdaptiveDecision(decision)
    }

    private func applyAdaptiveDecision(_ decision: AdaptiveBitrateDecision) {
        guard let encoder else { return }
        streamBitrate = decision.newBitrate
        encoderWork.perform {
            VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_AverageBitRate,
                                 value: streamBitrate as CFNumber)
            VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_DataRateLimits,
                                 value: [max(streamBitrate / 8, 1), 1] as CFArray)
        }
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
            pendingEncodes: Double(pendingEncodes),
            totalPendingWork: Double(pendingSends + pendingEncodes),
            pendingEncodePeak: Double(benchmarkPendingEncodePeak),
            macQueue: Double(pendingSends), macDrops: Double(lastMacDropsSnapshot),
            macCPU: benchmarkCPU.sample(), macMemory: Self.residentMemoryMB())
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
