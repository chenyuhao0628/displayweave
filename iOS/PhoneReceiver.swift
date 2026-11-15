// PhoneReceiver — negotiated H.264 / hardware HEVC over framed TCP.
//
// Pipeline:  TCP socket -> deframe -> Annex B parse -> CMSampleBuffer
//            -> AVSampleBufferDisplayLayer (decodes + renders)
//
// The phone LISTENS; the Mac connects (required for usbmux/USB).
// Wire protocol: [4-byte big-endian length][Annex B payload].

import Foundation
import Network
import AVFoundation
import CoreMedia
import VideoToolbox
import UIKit

@objc protocol IOSAudioPlayback: AnyObject {
    init()
    func enqueuePCM(_ pcmData: Data, sampleRate: Int, channels: Int)
    @objc optional func enqueueEncodedAudio(
        _ payloadData: Data,
        formatFlags: Int,
        sampleRate: Int,
        channels: Int,
        captureTimestampMs: Int64,
        arrivalMonoMs: Double
    )
    @objc optional func updateVideoPipelineDelay(udpJitterActive: Bool, explicitDelayMs: Double)
    @objc optional func recordVideoRender(captureTimestampMs: Int64, renderMonoMs: Double)
    func stop()
}

struct OutgoingDesktopInput {
    let kind: DesktopInputEvent.Kind
    var modifiers: Int = 0
    var x: Double = 0
    var y: Double = 0
    var button: Int = 0
    var clicks: Int = 1
    var dx: Double = 0
    var dy: Double = 0
    var keyCode: UInt16 = 0
    var repeating: Bool = false
}

/// One-second window of pipeline health, plus per-frame timing samples for
/// the performance overlay graph.
struct PerfStats: Equatable {
    var fps = 0
    var mbps = 0.0
    var avgFrameMs = 0.0
    var maxFrameMs = 0.0
    var stalls = 0               // frames that arrived >50ms late (this window)
    var decodeFlushes = 0        // display layer failures since connect
    var samples: [Double] = []   // last ~120 inter-frame intervals, ms
    // True end-to-end latency (Mac capture → phone display handoff), using
    // the clock offset estimated from timestamped ping/pong.
    var e2eP50 = 0.0
    var e2eP95 = 0.0
    var encodeP50 = 0.0          // Mac-side capture→socket (encode + queue)
    var rttMs = 0.0              // control-channel round trip
    var e2eSamples: [Double] = []  // last ~120 per-frame e2e latencies, ms
    var transport = "—"          // USB (loopback via usbmux) or WiFi
    var macDrops = 0             // frames the Mac dropped (backpressure), total
    var macPending = 0           // Mac send queue depth right now
    var inputP50 = 0.0           // touch sent → CGEvent injected on the Mac, ms
    var inputP95 = 0.0
    var capFps = 0               // frames ScreenCaptureKit delivered on the Mac
    var decodeP50 = 0.0          // decode / display-layer submission & queue latency, ms
    var photonP50 = 0.0          // Mac capture → frame actually on glass, ms
    var photonP95 = 0.0
}

final class PhoneReceiver: ObservableObject {
    static let desktopInputEnabledKey = "iosDesktopInputEnabled"

    @Published private(set) var status = "正在启动…"
    @Published private(set) var fps = 0
    @Published private(set) var connected = false
    @Published private(set) var encrypted = false
    @Published private(set) var videoSize = CGSize.zero   // for touch coordinate mapping
    @Published private(set) var perf = PerfStats()
    @Published private(set) var nativeHighRefreshTrialSupported = false
    @Published private(set) var pencilAvailable = false
    @Published private(set) var pencilExtendedAvailable = false
    @Published private(set) var pencilShortcutsAvailable = false
    @Published private(set) var selectedPencilTool = PencilTool.pen
    private var pencilActionGrant: String? // main-thread projection
    var onPencilToolChange: (() -> Void)?
    @Published private(set) var pencilActionStatus = "等待高级 Pencil 协商"
    @Published private(set) var desktopInputAvailable = false
    @Published private(set) var desktopInputStatus = "等待键鼠协商"
    @Published private(set) var desktopInputUserEnabledSetting: Bool = (
        UserDefaults.standard.object(forKey: PhoneReceiver.desktopInputEnabledKey) as? Bool ?? true
    )
    var onDesktopInputRevoked: (() -> Void)?
    var onInputReset: (() -> Void)?
    private let inputSendBudget = InputSendBudget()
    private var pencilNegotiated = false
    private var pencilExtendedNegotiated = false
    private var pencilActionSession: String?
    private var pencilActionSequence: UInt64 = 0
    private var pencilForwarder = PencilInputForwarder()
    private var desktopInputUserEnabled: Bool = (
        UserDefaults.standard.object(forKey: PhoneReceiver.desktopInputEnabledKey) as? Bool ?? true
    )
    private var desktopInputSession: String?
    private var desktopInputSequence: UInt64 = 0
    private var lastDesktopInputReason: String = ""
    var inputGeneration: UInt64 { inputSendBudget.generation }

    private var listener: NWListener?
    private lazy var admissionPool = AppleSecureAdmissionPool(queue: queue)
    private var security: AppleReceiverSecurity = .legacy
    private var peerID: String?
    private var securityObserver: NSObjectProtocol?
    private var listenerHealthy = false
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "receiver.video")
    private var frameDecoder = ReceiverFrameDecoder()
    private var running = false
    private var listenerGeneration: UInt64 = 0
    private var formatDesc: CMVideoFormatDescription?
    private let supportsHEVC = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
    private var videoCodec: ReceiverVideoCodec = .h264
    private var bitstream = ReceiverVideoBitstream(codec: .h264)
    private var configuredVideo: AppleVideoConfiguration?
    private var videoFallback = AppleVideoFallbackPolicy()
    private var waitingForKeyframe = true
    private var videoBackpressure = ReceiverVideoBackpressurePolicy()
    private var displayLayerNotReadySince: TimeInterval?
    private var firstVideoDeadline = ReceiverFirstVideoDeadline()
    @Published private(set) var requestedFps = 60
    @Published private(set) var codecLabel = "H.264"

    // Liveness: the Mac streams video and pings every 2s; if nothing arrives
    // for 5s the connection is half-open (Mac killed, tunnel died) — drop it
    // so the listener can accept a fresh one.
    private var lastDataReceived = Date()
    private var port: UInt16 = 9000
    private var monitorSchedule = ReceiverMonitorSchedule()

    private var framesThisWindow = 0
    private var queueRenderedFps = 0
    private var fpsWindowStart = Date()
    private var bytesThisWindow = 0
    private var stallsThisWindow = 0
    private var decodeFlushes = 0
    private var lastFrameAt: Date?
    private var frameIntervals: [Double] = []   // ring buffer, ms
    private let maxSamples = 120

    // Clock sync (NTP-style): offset = macClock − phoneClock, taken from the
    // ping/pong sample with the lowest RTT (least asymmetric).
    private var offsetSamples: [(rtt: Double, offset: Double)] = []
    private var clockOffsetMs: Double?
    private var lastRttMs = 0.0
    private var e2eWindow: [Double] = []        // capture→display, ms
    private var encodeWindow: [Double] = []     // capture→socket on the Mac, ms
    private var e2eRing: [Double] = []          // per-frame, for the overlay graph
    private var statsReportCounter = 0
    private var transport = "—"
    private var macDrops = 0
    private var macPending = 0
    private var macInputP50 = 0.0
    private var macInputP95 = 0.0
    private var macCapFps = 0
    private var udpMediaSession: UDPMediaReceiverSession?
    private var lastUdpMediaEpoch: Int64 = 0
    private var lastCursorSequence: UInt64 = 0
    private var lastAudioSequence: UInt32?
    private var audioPlayer: (any IOSAudioPlayback)? = {
        guard let cls = NSClassFromString("DisplayWeaveIOSAudioPlayer") as? any IOSAudioPlayback.Type else {
            return nil
        }
        return cls.init()
    }()

    private var nowMs: Double { Date().timeIntervalSince1970 * 1000 }

    // Local cursor echo (both called on the main thread): position is
    // normalized [0,1] in video space; the sprite arrives as a PNG with its
    // hotspot anchor and size normalized against the Mac display.
    var onCursor: ((_ x: Double, _ y: Double, _ visible: Bool) -> Void)?
    var onCursorImage: ((_ image: UIImage, _ anchor: CGPoint, _ normSize: CGSize) -> Void)?

    // Only the current main-thread presentation may clear callbacks. SwiftUI can
    // create the replacement before dismantling its predecessor.
    private var presentationID: UUID?
    private var retirePresentation: (() -> Void)?

    func claimPresentation(_ id: UUID, retire: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        let previous = retirePresentation
        presentationID = nil; retirePresentation = nil
        clearPresentationCallbacks()
        previous?() // release old input before the new view can emit any
        presentationID = id; retirePresentation = retire
    }

    func releasePresentation(_ id: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard presentationID == id else { return }
        let previous = retirePresentation
        presentationID = nil; retirePresentation = nil
        clearPresentationCallbacks()
        previous?()
    }

    private func clearPresentationCallbacks() {
        onInputReset = nil; onPencilToolChange = nil; onDesktopInputRevoked = nil
        onCursor = nil; onCursorImage = nil; onDecodedFrame = nil
    }

    // Metal renderer path (experimental, "metalRenderer" setting): we decode
    // explicitly and hand BGRA buffers out; called on the receiver queue.
    private let decodedFrameLock = NSLock()
    private var decodedFrameHandler: ((CVPixelBuffer, Double?) -> Void)?
    var onDecodedFrame: ((_ pixelBuffer: CVPixelBuffer, _ captureMs: Double?) -> Void)? {
        get { decodedFrameLock.lock(); defer { decodedFrameLock.unlock() }; return decodedFrameHandler }
        set { decodedFrameLock.lock(); decodedFrameHandler = newValue; decodedFrameLock.unlock() }
    }
    private var decompressionSession: VTDecompressionSession?
    private var decodeWindow: [Double] = []
    private var latestDecodeMs: Double = 0
    private var photonWindow: [Double] = []
    private let maxWindowSamples = 600
    private var loggedDisplayPath = false
    private var decodeErrorCount = 0
    // Default OFF: A/B measurement showed the system video layer reaches
    // glass faster than our CAMetalLayer path (iOS gives AVSBDL a dedicated
    // compositor plane). Kept as an experimental toggle + for its metrics.
    private var useMetalPath: Bool { UserDefaults.standard.bool(forKey: "metalRenderer") }

    /// Called by the renderer's presented handler: maps the CACurrentMediaTime-
    /// based glass timestamp into wall-clock ms and computes true photon e2e.
    func recordPresented(presentedTime: CFTimeInterval, captureMs: Double?, generation: UInt64) {
        guard let captureMs, presentedTime > 0 else { return }
        let presentedWallMs = nowMs - (CACurrentMediaTime() - presentedTime) * 1000
        queue.async {
            guard self.inputSendBudget.generation == generation, let offset = self.clockOffsetMs else { return }
            let photon = (presentedWallMs + offset) - captureMs
            if photon.isFinite, photon > -50, photon < 5000 {
                self.photonWindow.append(max(photon, 0))
                if self.photonWindow.count > self.maxWindowSamples {
                    self.photonWindow.removeFirst()
                }
            }
        }
    }

    let displayLayer: AVSampleBufferDisplayLayer

    /// Native panel size in pixels + scale, announced to the Mac in a "hello"
    /// message so it can size the virtual display. Orientation-dependent:
    /// rotating the phone or resizing iPad Split View / Stage Manager windows
    /// re-announces debounced geometry so the Mac updates smoothly.
    /// Protected by `panelStateLock` so `@MainActor` readers (e.g.
    /// `supportsNativeHighRefreshTrial`) and `queue` writers never data-race.
    private let panelStateLock = NSLock()
    private var _nativeLong = 0
    private var _nativeShort = 0
    private var _displayMaxFps = 60
    private var _devicePixelsWide = 0
    private var _devicePixelsHigh = 0
    private var _deviceScale: Double = 2
    private var _serviceName = "DisplayWeave"

    private var nativeLong: Int {
        get { panelStateLock.lock(); defer { panelStateLock.unlock() }; return _nativeLong }
        set { panelStateLock.lock(); _nativeLong = newValue; panelStateLock.unlock() }
    }
    private var nativeShort: Int {
        get { panelStateLock.lock(); defer { panelStateLock.unlock() }; return _nativeShort }
        set { panelStateLock.lock(); _nativeShort = newValue; panelStateLock.unlock() }
    }
    private var displayMaxFps: Int {
        get { panelStateLock.lock(); defer { panelStateLock.unlock() }; return _displayMaxFps }
        set { panelStateLock.lock(); _displayMaxFps = newValue; panelStateLock.unlock() }
    }
    // Changing the trial setting cannot change an already-advertised connection.
    private var nativeHighRefreshTrialForConnection = false
    private(set) var devicePixelsWide: Int {
        get { panelStateLock.lock(); defer { panelStateLock.unlock() }; return _devicePixelsWide }
        set { panelStateLock.lock(); _devicePixelsWide = newValue; panelStateLock.unlock() }
    }
    private(set) var devicePixelsHigh: Int {
        get { panelStateLock.lock(); defer { panelStateLock.unlock() }; return _devicePixelsHigh }
        set { panelStateLock.lock(); _devicePixelsHigh = newValue; panelStateLock.unlock() }
    }
    var deviceScale: Double {
        get { panelStateLock.lock(); defer { panelStateLock.unlock() }; return _deviceScale }
        set { panelStateLock.lock(); _deviceScale = newValue; panelStateLock.unlock() }
    }
    private var windowPointsWide: Int?
    private var windowPointsHigh: Int?
    private var panelMillimetersWide: Int?
    private var panelMillimetersHigh: Int?
    private struct AnnouncedHelloGeometry: Equatable {
        let pixelsWide: Int
        let pixelsHigh: Int
        let scaleMilli: Int
        let pointsWide: Int
        let pointsHigh: Int
        let millimetersWide: Int?
        let millimetersHigh: Int?
    }
    private var lastAnnouncedHelloGeometry: AnnouncedHelloGeometry?
    private var helloDebounceWorkItem: DispatchWorkItem?
    // Name advertised over Bonjour for the Mac's WiFi picker. iOS 16+ returns
    // a generic "iPhone" from UIDevice.current.name (the user-assigned name
    // needs an entitlement Apple gates behind approval and personal teams
    // can't get), so this is user-editable in Settings. The USB picker gets
    // the real name host-side via lockdownd regardless.
    var serviceName: String {
        get { panelStateLock.lock(); defer { panelStateLock.unlock() }; return _serviceName }
        set { panelStateLock.lock(); _serviceName = newValue; panelStateLock.unlock() }
    }

    // Stable per-install identity, advertised in the Bonjour TXT record and
    // sent in every hello. The Mac uses it to recognize "same device, other
    // transport" — the service name can't serve that role since it's
    // user-editable, and iOS offers no public API for the hardware UDID
    // that usbmuxd reports.
    static let installID = TransportInstallIdentity.value

    private var advertisedService: NWListener.Service {
        var txt = NWTXTRecord()
        txt["id"] = Self.installID
        if security.encrypted { txt["security"] = "tls-v1" }
        return NWListener.Service(name: serviceName, type: "_opensidecar._tcp",
                                  domain: nil, txtRecord: txt)
    }

    /// Update the advertised name and re-publish if already listening.
    func setServiceName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? UIDevice.current.name : trimmed
        queue.async {
            guard resolved != self.serviceName else { return }
            self.serviceName = resolved
            if self.listener != nil {
                self.listener?.service = self.advertisedService
                Log.info("re-advertising as \"\(resolved)\"")
            }
        }
    }

    func setNativePanel(long: Int, short: Int, scale: Double, maxFps: Int = 60) {
        let clampedLong = ReceiverWindowGeometryPolicy.clampEvenPixels(max(long, short))
        let clampedShort = ReceiverWindowGeometryPolicy.clampEvenPixels(min(long, short))
        let safeScale = scale.isFinite && scale > 0 ? min(4.0, max(0.5, scale)) : 2.0
        let resolvedMaxFps = AppleVideoPolicy.frameRate(maximum: maxFps)
        let supportsTrial = AppleVideoPolicy.nativeHighRefreshEnvelope(
            width: clampedLong, height: clampedShort, maxFps: resolvedMaxFps) != nil
        if Thread.isMainThread {
            if nativeHighRefreshTrialSupported != supportsTrial {
                nativeHighRefreshTrialSupported = supportsTrial
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.nativeHighRefreshTrialSupported != supportsTrial {
                    self.nativeHighRefreshTrialSupported = supportsTrial
                }
            }
        }
        queue.async { [weak self] in
            guard let self else { return }
            self.displayMaxFps = resolvedMaxFps
            self.nativeLong = clampedLong
            self.nativeShort = clampedShort
            if self.windowPointsWide == nil {
                self.deviceScale = safeScale
            }
            if self.devicePixelsWide == 0 {   // default landscape until the view reports
                self.devicePixelsWide = clampedLong
                self.devicePixelsHigh = clampedShort
            }
        }
    }

    func setOrientation(portrait: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            let rawW = portrait ? self.nativeShort : self.nativeLong
            let rawH = portrait ? self.nativeLong : self.nativeShort
            guard rawW > 0, rawH > 0 else { return }
            let w = ReceiverWindowGeometryPolicy.clampEvenPixels(rawW)
            let h = ReceiverWindowGeometryPolicy.clampEvenPixels(rawH)
            guard w != self.devicePixelsWide || h != self.devicePixelsHigh else { return }
            self.devicePixelsWide = w
            self.devicePixelsHigh = h
            self.windowPointsWide = nil
            self.windowPointsHigh = nil
            self.panelMillimetersWide = nil
            self.panelMillimetersHigh = nil
            Log.info("orientation changed -> \(w)x\(h)")
            self.scheduleDebouncedHello()
        }
    }

    func setWindowGeometry(
        pixelsWide: Int,
        pixelsHigh: Int,
        scale: Double,
        pointsWide: Int,
        pointsHigh: Int,
        screenNativeLong: Int,
        screenNativeShort: Int,
        screenNativeScale: Double
    ) {
        let clampedWide = ReceiverWindowGeometryPolicy.clampEvenPixels(pixelsWide)
        let clampedHigh = ReceiverWindowGeometryPolicy.clampEvenPixels(pixelsHigh)
        let clampedScale = scale.isFinite && scale > 0 ? min(4.0, max(0.5, scale)) : 2.0
        let clampedPtsWide = max(2, min(16384, pointsWide))
        let clampedPtsHigh = max(2, min(16384, pointsHigh))
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let mm = Self.estimateMillimeters(
            pixelsWide: clampedWide,
            pixelsHigh: clampedHigh,
            pointsWide: clampedPtsWide,
            pointsHigh: clampedPtsHigh,
            screenNativeLong: screenNativeLong,
            screenNativeShort: screenNativeShort,
            screenNativeScale: screenNativeScale,
            isPad: isPad
        )
        queue.async { [weak self] in
            guard let self else { return }
            let sameGeometry = self.devicePixelsWide == clampedWide
                && self.devicePixelsHigh == clampedHigh
                && abs(self.deviceScale - clampedScale) < 0.001
                && self.windowPointsWide == clampedPtsWide
                && self.windowPointsHigh == clampedPtsHigh
                && self.panelMillimetersWide == mm?.wide
                && self.panelMillimetersHigh == mm?.high
            guard !sameGeometry else { return }
            let hadInitialGeometry = self.devicePixelsWide > 0 && self.windowPointsWide != nil
            let pixelOrScaleChanged = self.devicePixelsWide != clampedWide
                || self.devicePixelsHigh != clampedHigh
                || abs(self.deviceScale - clampedScale) >= 0.001
            self.devicePixelsWide = clampedWide
            self.devicePixelsHigh = clampedHigh
            self.deviceScale = clampedScale
            self.windowPointsWide = clampedPtsWide
            self.windowPointsHigh = clampedPtsHigh
            self.panelMillimetersWide = mm?.wide
            self.panelMillimetersHigh = mm?.high
            if hadInitialGeometry || pixelOrScaleChanged {
                self.scheduleDebouncedHello()
            }
        }
    }

    private func currentHelloGeometrySnapshot() -> AnnouncedHelloGeometry {
        let pxWide = ReceiverWindowGeometryPolicy.clampEvenPixels(
            devicePixelsWide > 0 ? devicePixelsWide : 1920
        )
        let pxHigh = ReceiverWindowGeometryPolicy.clampEvenPixels(
            devicePixelsHigh > 0 ? devicePixelsHigh : 1080
        )
        let safeScale = deviceScale.isFinite && deviceScale > 0 ? min(4.0, max(0.5, deviceScale)) : 2.0
        let ptWide = windowPointsWide ?? max(2, min(16384, Int((Double(pxWide) / safeScale).rounded())))
        let ptHigh = windowPointsHigh ?? max(2, min(16384, Int((Double(pxHigh) / safeScale).rounded())))
        return AnnouncedHelloGeometry(
            pixelsWide: pxWide,
            pixelsHigh: pxHigh,
            scaleMilli: Int((safeScale * 1000).rounded()),
            pointsWide: ptWide,
            pointsHigh: ptHigh,
            millimetersWide: panelMillimetersWide,
            millimetersHigh: panelMillimetersHigh
        )
    }

    private func scheduleDebouncedHello() {
        helloDebounceWorkItem?.cancel()
        helloDebounceWorkItem = nil
        guard connection != nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.helloDebounceWorkItem = nil
            guard self.running, let conn = self.connection else { return }
            guard self.currentHelloGeometrySnapshot() != self.lastAnnouncedHelloGeometry else { return }
            Log.info("window geometry settled -> \(self.devicePixelsWide)x\(self.devicePixelsHigh)")
            self.sendHello(on: conn)
        }
        helloDebounceWorkItem = work
        queue.asyncAfter(
            deadline: .now() + ReceiverWindowGeometryPolicy.debounceIntervalSeconds,
            execute: work
        )
    }

    private static func estimateMillimeters(
        pixelsWide: Int,
        pixelsHigh: Int,
        pointsWide: Int,
        pointsHigh: Int,
        screenNativeLong: Int,
        screenNativeShort: Int,
        screenNativeScale: Double,
        isPad: Bool
    ) -> (wide: Int, high: Int)? {
        let ppi: Double
        if screenNativeScale <= 1.25 {
            ppi = 110.0
        } else if isPad {
            let isMini = max(screenNativeLong, screenNativeShort) == 2266
                && min(screenNativeLong, screenNativeShort) == 1488
            ppi = isMini ? 326.0 : 264.0
        } else {
            ppi = screenNativeScale >= 2.8 ? 460.0 : 326.0
        }
        guard ppi > 0 else { return nil }
        let mmWide = Int((Double(pixelsWide) / ppi * 25.4).rounded())
        let mmHigh = Int((Double(pixelsHigh) / ppi * 25.4).rounded())
        guard (50...2000).contains(mmWide), (50...2000).contains(mmHigh),
              pointsWide >= 2, pointsHigh >= 2 else { return nil }
        let pointAspect = Double(pointsWide) / Double(pointsHigh)
        let mmAspect = Double(mmWide) / Double(mmHigh)
        guard pointAspect > 0, mmAspect > 0,
              abs(log(mmAspect / pointAspect)) <= log(1.12) else { return nil }
        return (mmWide, mmHigh)
    }

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        displayLayer.videoGravity = .resizeAspect
        requestKeyframeAfterConfigHook = { [weak self] in
            guard let self else { return }
            self.lastKeyframeRequest = .distantPast
            self.requestKeyframeIfNeeded()
        }
        securityObserver = NotificationCenter.default.addObserver(forName: TransportSecurityChange.notification,
            object: nil, queue: nil) { [weak self] notification in
            let kind = notification.userInfo?["kind"] as? String, peer = notification.userInfo?["peer"] as? String
            self?.queue.async { [weak self] in self?.securityChanged(kind: kind, peer: peer) }
        }
    }

    deinit { if let securityObserver { NotificationCenter.default.removeObserver(securityObserver) } }

    private func securityChanged(kind: String?, peer: String?) {
        guard kind != "senderMode" else { return }
        admissionPool.cancelAll()
        if (kind == "revoked" && peerID == peer) || kind == "listenerMode" || kind == "identityReset" {
            connection?.cancel(); connection = nil; peerID = nil
            resetStreamState(); setConnected(false)
        }
        if kind == "listenerMode" || kind == "identityReset" {
            listenerGeneration &+= 1
            if running { restartListener() }
        }
    }

    func start(port: UInt16 = 9000) {
        queue.async {
            self.port = port
            self.running = true
            self.listenerGeneration &+= 1
            self.restartListener()
            self.startMonitorsIfNeeded()
        }
    }

    func ensureListening() {
        queue.async {
            if !self.running { self.listenerGeneration &+= 1 }
            self.running = true
            self.startMonitorsIfNeeded()
            guard !self.listenerHealthy else { return }
            self.restartListener()
        }
    }

    func stop() {
        queue.async {
            self.running = false
            self.helloDebounceWorkItem?.cancel()
            self.helloDebounceWorkItem = nil
            self.monitorSchedule.deactivate()
            self.listenerGeneration &+= 1
            let oldListener = self.listener
            self.listener = nil
            oldListener?.cancel()
            self.admissionPool.cancelAll()
            if case .tls(_, let state) = self.security { state.stopPairing() }
            self.listenerHealthy = false
            let old = self.connection
            var farewell = Data()
            if old != nil, let session = self.desktopInputSession,
               self.desktopInputSequence < DesktopInputProtocol.maximumSequence {
                self.desktopInputSequence += 1
                let releaseObj: [String: Any] = [
                    "type": "desktopInput",
                    "inputSession": session,
                    "sequence": self.desktopInputSequence,
                    "kind": DesktopInputEvent.Kind.releaseAll.rawValue,
                    "modifiers": 0,
                ]
                if let releaseData = try? JSONSerialization.data(withJSONObject: releaseObj) {
                    farewell.append(ReceiverFrameDecoder.frame(releaseData))
                }
            }
            self.connection = nil
            self.peerID = nil
            self.resetStreamState()
            self.setConnected(false, updateStatus: false)
            self.setStatus("已在后台断开")
            if let old {
                let payload = Data("{\"type\":\"goodbye\"}".utf8)
                farewell.append(ReceiverFrameDecoder.frame(payload))
                old.send(content: farewell, completion: .contentProcessed { _ in old.cancel() })
                self.queue.asyncAfter(deadline: .now() + 0.25) { old.cancel() }
            }
        }
    }

    private func startMonitorsIfNeeded() {
        guard let generation = monitorSchedule.activateIfNeeded() else { return }
        schedulePing(generation: generation)
        scheduleWatchdog(generation: generation)
    }

    private func restartListener() {
        guard running else { return }
        listener?.cancel()
        listener = nil
        admissionPool.cancelAll()
        listenerHealthy = false
        startListener()
    }

    private func startListener() {
        guard running else { return }
        let generation = listenerGeneration
        do {
            security = try .live(localID: Self.installID)
            // noDelay matters most in THIS direction: touch events are tiny
            // packets, and Nagle would hold each one until the previous is
            // ACKed — batched, late drags read as input lag.
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            let tls: NWProtocolTLS.Options?
            if case .tls(let identity, let state) = security {
                tls = try AppleTLS.options(identity: identity, peerIsServer: false, queue: queue,
                                           acceptedFingerprint: { state.acceptsTLS($0) })
            } else { tls = nil }
            let params = NWParameters(tls: tls, tcp: tcp)
            params.allowLocalEndpointReuse = true
            params.serviceClass = .interactiveVideo
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            setStatus("监听失败：\(error.localizedDescription)")
            return
        }
        // Advertise on the local network so the Mac can discover us for WiFi
        // mode (USB/usbmux connects straight to the port and ignores this).
        guard let active = listener else { return }
        active.service = advertisedService
        active.newConnectionHandler = { [weak self, weak active] conn in
            guard let self, self.running, self.listener === active else { conn.cancel(); return }
            if case .tls(_, let state) = self.security {
                self.admissionPool.accept(conn, pairing: state) { [weak self, weak active] result in
                    guard let self, self.running, self.listener === active,
                          self.listenerGeneration == generation else { conn.cancel(); return }
                    switch result {
                    case .success(let peer): self.adopt(conn, authenticatedPeer: peer)
                    case .failure(let error):
                        if self.connection == nil { self.setStatus(error.localizedDescription) }
                    }
                }
            } else { self.adopt(conn) }
        }
        active.stateUpdateHandler = { [weak self, weak active] state in
            guard let self, self.running, self.listener === active else { return }
            switch state {
            case .ready:
                self.listenerHealthy = true
                self.setStatus(self.security.encrypted ? "正在安全监听 :\(self.port)" : "旧版兼容（未加密） :\(self.port)")
            case .failed(let error):
                Log.info("listener failed: \(error) — restarting in 1s")
                self.listenerHealthy = false
                self.setStatus("监听失败，正在重启…")
                self.queue.asyncAfter(deadline: .now() + 1) { [weak self, weak active] in
                    guard let self, self.running, self.listenerGeneration == generation,
                          self.listener === active else { return }
                    self.restartListener()
                }
            case .cancelled: self.listenerHealthy = false
            default: break
            }
        }
        active.start(queue: queue)
    }

    private func adopt(_ conn: NWConnection, authenticatedPeer: SecurePeerRecord? = nil) {
            Log.info("new connection from \(String(describing: conn.endpoint))")
            self.helloDebounceWorkItem?.cancel()
            self.helloDebounceWorkItem = nil
            // usbmux-forwarded (cable) connections arrive from loopback;
            // anything else came over the network.
            let peer = String(describing: conn.endpoint)
            self.transport = (peer.hasPrefix("127.0.0.1") || peer.hasPrefix("::1")
                              || peer.hasPrefix("localhost")) ? "USB" : "WiFi"
            // Replace any existing connection and reset decoder state before binding the new connection.
            self.connection?.cancel()
            self.connection = nil
            self.peerID = authenticatedPeer?.installID
            self.resetStreamState(acceptingInput: true)
            self.connection = conn
            self.nativeHighRefreshTrialForConnection = UserDefaults.standard.bool(
                forKey: AppleVideoPolicy.nativeHighRefreshTrialKey)
            let encrypted = authenticatedPeer != nil
            conn.stateUpdateHandler = { [weak self, weak conn] state in
                guard let self, let conn, self.running, self.connection === conn else { return }
                switch state {
                case .ready:
                    guard !encrypted else { return }
                    self.lastDataReceived = Date()
                    self.firstVideoDeadline.begin(at: ProcessInfo.processInfo.systemUptime)
                    self.setConnected(true, updateStatus: false)
                    self.setStatus("已连接，正在等待 Mac 画面…")
                    self.sendHello(on: conn)
                case .failed, .cancelled:
                    self.connection = nil
                    self.resetStreamState()
                    self.setConnected(false)
                default: break
                }
            }
            let generation = self.inputSendBudget.generation
            let desktopStatusInitial: String
            if !self.desktopInputUserEnabled {
                desktopStatusInitial = "键鼠回传已关闭"
            } else if encrypted {
                desktopStatusInitial = "等待 Mac 授权键鼠回传"
            } else {
                desktopStatusInitial = "请先配对并使用加密连接"
            }
            DispatchQueue.main.async {
                guard self.inputSendBudget.generation == generation else { return }
                self.encrypted = encrypted
                self.desktopInputStatus = desktopStatusInitial
            }
            if encrypted {
                self.lastDataReceived = Date()
                self.firstVideoDeadline.begin(at: ProcessInfo.processInfo.systemUptime)
                self.setConnected(true, updateStatus: false)
                self.setStatus("安全连接已建立，正在等待 Mac 画面…")
                self.sendHello(on: conn)
            } else { conn.start(queue: self.queue) }
            self.receive(on: conn)
    }

    // MARK: - Liveness (ping + watchdog)

    private func schedulePing(generation: UInt64) {
        queue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, self.running, self.monitorSchedule.isCurrent(generation) else { return }
            if self.connection?.state == .ready {
                self.sendControl(["type": "ping", "t": self.nowMs])
            }
            self.schedulePing(generation: generation)
        }
    }

    /// JSON on the video channel (pong, ping liveness) — payloads starting '{'.
    private func handleVideoChannelJSON(_ data: Data) {
        guard data.count <= 256 * 1024,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }
        switch type {
        case "streamConfig":
            configureVideo(obj)
        case "inputConfig":
            let caps = obj["inputCaps"] as? [String]
            let hasDesktopFields = obj["inputStatus"] != nil
                || obj["inputSession"] != nil
                || caps?.contains(DesktopInputProtocol.capability) == true
                || (caps?.isEmpty == true
                    && obj["pencilActionStatus"] == nil
                    && obj["pencilActionSession"] == nil)
            let hasPencilFields = obj["pencilActionStatus"] != nil
                || obj["pencilActionSession"] != nil
                || PencilProtocol.supports(caps)
                || !hasDesktopFields

            let generation = inputSendBudget.generation
            if hasPencilFields {
                pencilNegotiated = PencilProtocol.supports(caps)
                pencilExtendedNegotiated = pencilNegotiated && peerID != nil
                    && caps?.contains(PencilProtocol.extendedCapability) == true
                let candidate = obj["pencilActionSession"] as? String
                let session = pencilExtendedNegotiated && candidate.flatMap(UUID.init(uuidString:)) != nil ? candidate : nil
                if session != pencilActionSession { pencilActionSequence = 0 }
                pencilActionSession = session
                let enabled = pencilNegotiated
                let extended = pencilExtendedNegotiated
                let labels = ["consentRequired": "请在 Mac 权限设置中允许 Pencil 快捷键", "accessibilityRequired": "请在 Mac 授予辅助功能权限",
                              "targetPending": "等待 Mac 准备显示器", "secureRequired": "快捷键需要加密配对"]
                let actionStatus = session != nil ? "快捷键已授权" : labels[obj["pencilActionStatus"] as? String ?? ""] ?? "发送端未启用高级快捷键"
                DispatchQueue.main.async {
                    guard self.inputSendBudget.generation == generation else { return }
                    self.pencilAvailable = enabled
                    self.pencilExtendedAvailable = extended
                    if !extended && self.selectedPencilTool != .pen {
                        self.onPencilToolChange?(); self.selectedPencilTool = .pen
                    }
                    self.pencilShortcutsAvailable = session != nil
                    self.pencilActionGrant = session
                    self.pencilActionStatus = actionStatus
                }
            }
            if hasDesktopFields {
                let candidate = obj["inputSession"] as? String
                let valid = peerID != nil
                    && desktopInputUserEnabled
                    && caps?.contains(DesktopInputProtocol.capability) == true
                    && candidate.flatMap(UUID.init(uuidString:)) != nil
                let grant = valid ? candidate : nil
                if grant != desktopInputSession {
                    desktopInputSequence = 0
                }
                desktopInputSession = grant
                let reason = obj["inputStatus"] as? String ?? ""
                lastDesktopInputReason = reason
                let statusLabel = Self.desktopInputStatusLabel(
                    userEnabled: desktopInputUserEnabled,
                    encrypted: peerID != nil,
                    granted: grant != nil,
                    reason: reason
                )
                DispatchQueue.main.async {
                    guard self.inputSendBudget.generation == generation else { return }
                    self.desktopInputAvailable = (grant != nil)
                    self.desktopInputStatus = statusLabel
                    if grant == nil {
                        self.onDesktopInputRevoked?()
                    }
                }
            }
        case "pong":
            guard let t1 = obj["t"] as? Double, let mt = obj["mt"] as? Double else { return }
            let t2 = nowMs
            let rtt = t2 - t1
            guard rtt >= 0, rtt < 2000 else { return }
            let offset = mt - (t1 + t2) / 2
            offsetSamples.append((rtt, offset))
            if offsetSamples.count > 15 { offsetSamples.removeFirst() }
            if let best = offsetSamples.min(by: { $0.rtt < $1.rtt }) {
                clockOffsetMs = best.offset
            }
            lastRttMs = rtt
        case "ping":
            // The Mac piggybacks its send-side health on liveness pings.
            let health = SenderHealthTelemetry(obj)
            macDrops = health.droppedFrames ?? macDrops
            macPending = health.queueDepth ?? macPending
            macInputP50 = obj["inp50"] as? Double ?? macInputP50
            macInputP95 = obj["inp95"] as? Double ?? macInputP95
            macCapFps = obj["capFps"] as? Int ?? macCapFps
        case "cursor":
            if let seq = (obj["s"] as? NSNumber)?.uint64Value ?? (obj["sequence"] as? NSNumber)?.uint64Value,
               seq > 0 {
                guard seq > lastCursorSequence else { return }
                lastCursorSequence = seq
            }
            let visible = (obj["v"] as? Int ?? 0) == 1
            let x = obj["x"] as? Double ?? 0
            let y = obj["y"] as? Double ?? 0
            guard x.isFinite, y.isFinite, x >= 0, x <= 1, y >= 0, y <= 1 else { return }
            let generation = inputSendBudget.generation
            DispatchQueue.main.async {
                guard self.inputSendBudget.generation == generation else { return }
                self.onCursor?(x, y, visible)
            }
        case "cursorImg":
            guard let cursor = ReceiverCursorImage.decode(obj) else { return }
            let image = UIImage(cgImage: cursor.image)
            let generation = inputSendBudget.generation
            DispatchQueue.main.async {
                guard self.inputSendBudget.generation == generation else { return }
                self.onCursorImage?(image, cursor.anchor, cursor.normalizedSize)
            }
        case "udpMediaConfig":
            configureUDPMedia(obj)
        case TCPAudioFrameMessage.messageType:
            guard data.count <= TCPAudioFrameMessage.maxControlBytes,
                  let audioPayload = try? TCPAudioFrameMessage.decode(jsonObject: obj, rawByteCount: data.count) else {
                return
            }
            handleIncomingAudio(audioPayload, isUDP: false)
        default:
            break
        }
    }

    private static func desktopInputStatusLabel(
        userEnabled: Bool,
        encrypted: Bool,
        granted: Bool,
        reason: String
    ) -> String {
        if !userEnabled { return "键鼠回传已关闭" }
        if granted { return "已授权 · 外接键盘与指针可直接操作 Mac" }
        if !encrypted { return "请先配对并使用加密连接" }
        let labels = [
            "secureRequired": "请先配对并使用加密连接",
            "consentRequired": "请在 Mac 端设置中允许键鼠回传",
            "accessibilityRequired": "请在 Mac 端授予辅助功能权限",
            "targetPending": "等待 Mac 准备显示器",
        ]
        return labels[reason] ?? "发送端未授权键鼠回传，请检查 Mac 端设置"
    }

    private func scheduleWatchdog(generation: UInt64) {
        queue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, self.running, self.monitorSchedule.isCurrent(generation) else { return }
            if let conn = self.connection, conn.state == .ready,
               Date().timeIntervalSince(self.lastDataReceived) > 5 {
                Log.info("watchdog: nothing from the Mac for >5s — dropping connection")
                conn.cancel()
                self.connection = nil
                self.resetStreamState()
                self.setConnected(false)
            }
            if self.connection != nil, self.firstVideoDeadline.expired(at: ProcessInfo.processInfo.systemUptime) {
                self.rejectVideo("连接已建立但未收到画面，请在 Mac 检查屏幕录制权限后重新连接")
            }
            self.scheduleWatchdog(generation: generation)
        }
    }

    private func resetStreamState(acceptingInput: Bool = false) {
        helloDebounceWorkItem?.cancel()
        helloDebounceWorkItem = nil
        lastAnnouncedHelloGeometry = nil
        udpMediaSession?.stop()
        udpMediaSession = nil
        lastUdpMediaEpoch = 0
        audioPlayer?.stop()
        lastCursorSequence = 0
        lastAudioSequence = nil
        let generation = inputSendBudget.reset(accepting: acceptingInput)
        pencilNegotiated = false
        pencilExtendedNegotiated = false
        pencilActionSession = nil; pencilActionSequence = 0
        pencilForwarder = PencilInputForwarder()
        desktopInputSession = nil
        desktopInputSequence = 0
        lastDesktopInputReason = ""
        let userEnabled = desktopInputUserEnabled
        DispatchQueue.main.async {
            guard self.inputSendBudget.generation == generation else { return }
            self.pencilAvailable = false
            self.pencilExtendedAvailable = false; self.pencilShortcutsAvailable = false
            self.pencilActionGrant = nil; self.selectedPencilTool = .pen
            self.pencilActionStatus = "等待高级 Pencil 协商"
            self.desktopInputAvailable = false
            self.desktopInputStatus = userEnabled ? "等待键鼠协商" : "键鼠回传已关闭"
            self.onDesktopInputRevoked?()
            self.onInputReset?()
        }
        firstVideoDeadline = ReceiverFirstVideoDeadline()
        macDrops = 0; macPending = 0; macInputP50 = 0; macInputP95 = 0; macCapFps = 0
        frameDecoder = ReceiverFrameDecoder()
        videoCodec = .h264
        videoFallback = AppleVideoFallbackPolicy()
        configuredVideo = nil
        activeConfigVersion = 0
        pendingKeyframeAfterStreamConfig = false
        nativeHighRefreshTrialForConnection = false
        resetVideoDecoder()
        DispatchQueue.main.async {
            guard self.inputSendBudget.generation == generation else { return }
            self.requestedFps = 60
            self.codecLabel = "H.264"
        }
        lastFrameAt = nil
        frameIntervals.removeAll()
        decodeFlushes = 0
        framesThisWindow = 0; queueRenderedFps = 0; bytesThisWindow = 0; stallsThisWindow = 0
        fpsWindowStart = Date()
        offsetSamples.removeAll(); clockOffsetMs = nil; lastRttMs = 0
        e2eWindow.removeAll(); e2eRing.removeAll(); encodeWindow.removeAll()
        DispatchQueue.main.async {
            guard self.inputSendBudget.generation == generation else { return }
            self.videoSize = .zero
            self.fps = 0
            self.perf = PerfStats()
            self.onCursor?(0, 0, false)
        }
        latestDecodeMs = 0
        decodeWindow.removeAll(keepingCapacity: true)
        photonWindow.removeAll(keepingCapacity: true)
    }

    // MARK: - Control messages (phone -> Mac)

    private var videoLimits: (width: Int, height: Int) {
        devicePixelsHigh > devicePixelsWide ? (2304, 4096) : (4096, 2304)
    }

    private var activeConfigVersion: Int64 = 0
    private var pendingKeyframeAfterStreamConfig = false
    private var requestKeyframeAfterConfigHook: (() -> Void)?

    var supportsNativeHighRefreshTrial: Bool {
        AppleVideoPolicy.nativeHighRefreshEnvelope(
            width: nativeLong, height: nativeShort, maxFps: displayMaxFps) != nil
    }

    private var nativeVideoEnvelope: AppleNativeVideoEnvelope? {
        guard nativeHighRefreshTrialForConnection else { return nil }
        return AppleVideoPolicy.nativeHighRefreshEnvelope(width: devicePixelsWide,
            height: devicePixelsHigh, maxFps: displayMaxFps)
    }

    private func sendHello(on conn: NWConnection) {
        let codecs = supportsHEVC ? ["h264", "hevc"] : ["h264"]
        let snapshot = currentHelloGeometrySnapshot()
        let pxWide = snapshot.pixelsWide
        let pxHigh = snapshot.pixelsHigh
        let safeScale = deviceScale.isFinite && deviceScale > 0 ? min(4.0, max(0.5, deviceScale)) : 2.0
        lastAnnouncedHelloGeometry = snapshot
        let limits = pxHigh > pxWide ? (width: 2304, height: 4096) : (width: 4096, height: 2304)
        let nativeEnvelope: AppleNativeVideoEnvelope? = nativeHighRefreshTrialForConnection
            ? AppleVideoPolicy.nativeHighRefreshEnvelope(width: pxWide, height: pxHigh, maxFps: displayMaxFps)
            : nil
        var videoCaps: [[String: Any]] = []
        videoCaps.reserveCapacity(codecs.count * (nativeEnvelope == nil ? 1 : 2))
        for codec in codecs {
            videoCaps.append(["codec": codec, "maxWidth": limits.width, "maxHeight": limits.height,
                              "maxFrameRate": displayMaxFps,
                              "maxPixelsPerSecond": AppleVideoPolicy.maxPixelsPerSecond])
            if let nativeEnvelope { videoCaps.append(nativeEnvelope.capability(codec: codec)) }
        }
        var inputCaps = [PencilProtocol.capability]
        if peerID != nil {
            inputCaps.append(PencilProtocol.extendedCapability)
            if desktopInputUserEnabled {
                inputCaps.append(DesktopInputProtocol.capability)
            }
        }
        var panel: [String: Any] = [
            "pixelsWide": pxWide,
            "pixelsHigh": pxHigh,
            "scale": safeScale,
        ]
        let ptWide = windowPointsWide ?? max(2, min(16384, Int((Double(pxWide) / safeScale).rounded())))
        let ptHigh = windowPointsHigh ?? max(2, min(16384, Int((Double(pxHigh) / safeScale).rounded())))
        if (2...16384).contains(ptWide), (2...16384).contains(ptHigh) {
            panel["pointsWide"] = ptWide
            panel["pointsHigh"] = ptHigh
        }
        if let mmWide = panelMillimetersWide, let mmHigh = panelMillimetersHigh,
           (50...2000).contains(mmWide), (50...2000).contains(mmHigh) {
            panel["millimetersWide"] = mmWide
            panel["millimetersHigh"] = mmHigh
        }
        sendControl([
            "type": "hello",
            "pixelsWide": pxWide,
            "pixelsHigh": pxHigh,
            "scale": safeScale,
            "panel": panel,
            "device": UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone",
            "id": Self.installID,
            "inputCaps": inputCaps,
            "capabilities": [
                AppleVideoPolicy.capability,
                AppleVideoPolicy.udpMediaCapability,
                AppleVideoPolicy.udpCursorCapability,
                AppleVideoPolicy.udpAudioCapability,
                AppleVideoPolicy.tcpAudioCapability,
                AppleVideoPolicy.audioOpusCapability,
                AppleVideoPolicy.displayP3Capability,
            ],
            "udpMediaV1": true,
            "refreshRate": displayMaxFps, "maxFps": displayMaxFps,
            "displayMaxFrameRate": displayMaxFps,
            "supportedCodecs": codecs, "preferredCodec": supportsHEVC ? "hevc" : "h264",
            "maxEncodeWide": limits.width, "maxEncodeHigh": limits.height,
            "videoCaps": videoCaps,
        ], on: conn)
        Log.info("hello sent (\(pxWide)x\(pxHigh) @ \(safeScale)x)")
    }

    func setDesktopInputEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.desktopInputEnabledKey)
        if Thread.isMainThread {
            desktopInputUserEnabledSetting = enabled
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.desktopInputUserEnabledSetting = enabled
            }
        }
        queue.async { [weak self] in
            guard let self, self.desktopInputUserEnabled != enabled else { return }
            self.desktopInputUserEnabled = enabled
            let generation = self.inputSendBudget.generation
            if !enabled {
                if let session = self.desktopInputSession,
                   self.desktopInputSequence < DesktopInputProtocol.maximumSequence {
                    self.desktopInputSequence += 1
                    let releaseObj: [String: Any] = [
                        "type": "desktopInput",
                        "inputSession": session,
                        "sequence": self.desktopInputSequence,
                        "kind": DesktopInputEvent.Kind.releaseAll.rawValue,
                        "modifiers": 0,
                    ]
                    self.sendControl(releaseObj)
                }
                self.desktopInputSession = nil
                self.desktopInputSequence = 0
                DispatchQueue.main.async {
                    guard self.inputSendBudget.generation == generation else { return }
                    self.desktopInputAvailable = false
                    self.desktopInputStatus = "键鼠回传已关闭"
                    self.onDesktopInputRevoked?()
                }
            } else {
                let encrypted = self.peerID != nil
                let label = Self.desktopInputStatusLabel(
                    userEnabled: true,
                    encrypted: encrypted,
                    granted: false,
                    reason: self.lastDesktopInputReason
                )
                DispatchQueue.main.async {
                    guard self.inputSendBudget.generation == generation else { return }
                    self.desktopInputStatus = encrypted ? "等待 Mac 授权键鼠回传" : label
                }
            }
            if let conn = self.connection {
                self.sendHello(on: conn)
            }
        }
    }

    func sendDesktopInput(_ event: OutgoingDesktopInput, generation: UInt64) {
        enqueueControl(expectedGeneration: generation) { [weak self] in
            guard let self, self.desktopInputUserEnabled,
                  let session = self.desktopInputSession,
                  self.desktopInputSequence < DesktopInputProtocol.maximumSequence else { return [] }
            guard let payload = self.buildDesktopInputMessage(event, session: session) else { return [] }
            return [payload]
        }
    }

    func releaseDesktopInput(generation: UInt64) {
        sendDesktopInput(OutgoingDesktopInput(kind: .releaseAll), generation: generation)
    }

    private func buildDesktopInputMessage(_ event: OutgoingDesktopInput, session: String) -> [String: Any]? {
        let nextSequence = desktopInputSequence + 1
        let clampedModifiers = min(31, max(0, event.modifiers))
        var obj: [String: Any] = [
            "type": "desktopInput",
            "inputSession": session,
            "sequence": nextSequence,
            "kind": event.kind.rawValue,
            "modifiers": clampedModifiers,
        ]
        switch event.kind {
        case .move:
            guard event.x.isFinite, event.y.isFinite else { return nil }
            obj["x"] = min(1, max(0, event.x))
            obj["y"] = min(1, max(0, event.y))
        case .buttonDown, .buttonUp:
            guard event.x.isFinite, event.y.isFinite, (0...2).contains(event.button) else { return nil }
            obj["x"] = min(1, max(0, event.x))
            obj["y"] = min(1, max(0, event.y))
            obj["button"] = event.button
            obj["clicks"] = min(3, max(1, event.clicks))
        case .scroll:
            guard event.x.isFinite, event.y.isFinite,
                  event.dx.isFinite, event.dy.isFinite else { return nil }
            obj["x"] = min(1, max(0, event.x))
            obj["y"] = min(1, max(0, event.y))
            obj["dx"] = min(4096, max(-4096, event.dx))
            obj["dy"] = min(4096, max(-4096, event.dy))
        case .keyDown, .keyUp:
            let code = Int(event.keyCode)
            guard (0...127).contains(code),
                  ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(code) else { return nil }
            obj["keyCode"] = code
            obj["repeat"] = event.repeating
        case .modifiers, .releaseAll:
            break
        }
        guard let encoded = try? JSONSerialization.data(withJSONObject: obj),
              DesktopInputEvent.decode(encoded) != nil else { return nil }
        desktopInputSequence = nextSequence
        return obj
    }

    /// Touch events: x/y normalized [0,1] in video space, origin top-left.
    /// Stamped in *Mac* clock time (our clock + sync offset) so the Mac can
    /// measure touch→injection latency without doing its own clock sync.
    func sendTouch(phase: String, x: Double, y: Double, generation: UInt64? = nil) {
        guard x.isFinite, y.isFinite else { return }
        enqueueControl(expectedGeneration: generation) {
            var msg: [String: Any] = ["type": "touch", "phase": phase, "x": x, "y": y]
            if let offset = self.clockOffsetMs { msg["t"] = self.nowMs + offset }
            return [msg]
        }
    }

    func sendScroll(dx: Double, dy: Double, generation: UInt64? = nil) {
        guard dx.isFinite, dy.isFinite else { return }
        enqueueControl(expectedGeneration: generation) { [["type": "scroll", "dx": dx, "dy": dy]] }
    }

    func sendPencil(_ sample: PencilSample, generation: UInt64) {
        enqueueControl(expectedGeneration: generation) {
            self.pencilForwarder.messages(for: sample, enabled: self.pencilNegotiated, extended: self.pencilExtendedNegotiated)
        }
    }

    func sendPencilAction(_ action: PencilRemoteAction, generation: UInt64) {
        guard let expected = pencilActionGrant else { return }
        enqueueControl(expectedGeneration: generation) {
            guard self.pencilExtendedNegotiated, let session = self.pencilActionSession,
                  session == expected,
                  self.pencilActionSequence < 9_007_199_254_740_991 else { return [] }
            self.pencilActionSequence += 1
            return [["type": "pencilAction", "action": action.rawValue, "inputSession": session, "sequence": self.pencilActionSequence]]
        }
    }

    func selectPencilTool(_ tool: PencilTool) {
        guard pencilExtendedAvailable, tool != selectedPencilTool else { return }
        onPencilToolChange?()
        selectedPencilTool = tool
    }

    func endPencilProximity(x: Double, y: Double, generation: UInt64) {
        guard x.isFinite, y.isFinite else { return }
        enqueueControl(expectedGeneration: generation) {
            self.pencilNegotiated ? [["type": "proximity", "entering": false, "x": x, "y": y]] : []
        }
    }

    private func sendControl(_ message: [String: Any], on conn: NWConnection? = nil) {
        enqueueControl(on: conn) { [message] }
    }

    private func dropInputConnection(generation: UInt64, status: String) {
        guard inputSendBudget.generation == generation, let conn = connection else { return }
        connection = nil
        conn.cancel()
        resetStreamState()
        setConnected(false, updateStatus: false)
        setStatus(status)
    }

    /// Reserve before dispatch: a slow video queue cannot accumulate unlimited input closures.
    private func enqueueControl(expectedGeneration: UInt64? = nil, on selected: NWConnection? = nil,
                                messages: @escaping () -> [[String: Any]]) {
        switch inputSendBudget.reserve(expectedGeneration: expectedGeneration) {
        case .unavailable: return
        case .overflow(let generation):
            queue.async { [self] in self.dropInputConnection(generation: generation, status: "输入发送拥堵，请在 Mac 重新连接") }
        case .accepted(let ticket):
            queue.async { [self] in
                guard self.inputSendBudget.generation == ticket.generation,
                      let conn = self.connection, selected == nil || selected === conn else {
                    self.inputSendBudget.complete(ticket); return
                }
                var framed = Data()
                for message in messages() {
                    guard let payload = try? JSONSerialization.data(withJSONObject: message),
                          payload.count <= 64 * 1024, framed.count + payload.count + 4 <= 64 * 1024 else {
                        self.dropInputConnection(generation: ticket.generation, status: "输入数据无效，请重新连接")
                        return
                    }
                    framed.append(ReceiverFrameDecoder.frame(payload))
                }
                guard !framed.isEmpty else { self.inputSendBudget.complete(ticket); return }
                conn.send(content: framed, completion: .contentProcessed { [weak self, weak conn] error in
                    guard let self, let conn else { return }
                    self.queue.async { [weak self, weak conn] in
                        guard let self, let conn,
                              self.connection === conn, self.inputSendBudget.complete(ticket) else { return }
                        if error != nil {
                            self.dropInputConnection(generation: ticket.generation, status: "输入连接已结束，等待 Mac 重新连接")
                        }
                    }
                })
            }
        }
    }

    // MARK: - Socket read + length-prefixed deframing

    private func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) {
            [weak self, weak conn] data, _, isComplete, error in
            guard let self, let conn, self.running, self.connection === conn else { return }
            if let data, !data.isEmpty {
                let receivedAtUptime = ProcessInfo.processInfo.systemUptime
                self.lastDataReceived = Date()
                self.bytesThisWindow += data.count
                do {
                    for frame in try self.frameDecoder.append(data) {
                        guard self.connection === conn else { return }
                        self.handleAnnexB(frame, receivedAtUptime: receivedAtUptime, isUDP: false)
                    }
                } catch {
                    self.connection = nil
                    conn.cancel()
                    self.resetStreamState()
                    self.setConnected(false, updateStatus: false)
                    self.setStatus("已拒绝无效数据，等待 Mac 重新连接")
                    return
                }
            }
            guard self.connection === conn else { return }
            if isComplete || error != nil {
                self.connection = nil
                conn.cancel()
                self.resetStreamState()
                self.setConnected(false)
            } else { self.receive(on: conn) }
        }
    }

    // MARK: - Annex B -> CMSampleBuffer

    private func handleAnnexB(
        _ data: Data,
        receivedAtUptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        isUDP: Bool = false
    ) {
        // Pure JSON payload = control message (pong, cursor sprite etc.).
        // Video frames also begin with '{' (telemetry prefix) but always
        // contain start codes — the null bytes make them unambiguous even
        // against multi-KB JSON (cursor sprites are base64, NUL-free).
        if data.count < 32_768, data.first == UInt8(ascii: "{"), !data.contains(0x00) {
            handleVideoChannelJSON(data)
            return
        }

        guard !videoFallback.awaitingFallback else { return }
        let packet: ReceiverVideoBitstream.Packet
        do { packet = try bitstream.parse(data) }
        catch { failVideo(); return }
        if packet.formatChanged { waitingForKeyframe = true }
        guard let format = packet.format else { requestKeyframeIfNeeded(); return }
        if packet.formatChanged {
            let dims = CMVideoFormatDescriptionGetDimensions(format)
            let limits = videoLimits
            let maxDim = max(limits.width, limits.height)
            let minDim = min(limits.width, limits.height)
            let withinUnconfiguredLimits = (Int(dims.width) <= maxDim && Int(dims.height) <= minDim)
                || (Int(dims.width) <= minDim && Int(dims.height) <= maxDim)
            guard dims.width > 0, dims.height > 0, dims.width <= 8192, dims.height <= 8192,
                  Int64(dims.width) * Int64(dims.height) <= 33_554_432 else {
                rejectVideo("视频尺寸与配置不符，请重新连接"); return
            }
            let matchesConfigured = (configuredVideo == nil && withinUnconfiguredLimits)
                || (Int(dims.width) == configuredVideo?.width
                  && Int(dims.height) == configuredVideo?.height)
                || (withinUnconfiguredLimits
                  && Int(dims.width) == configuredVideo?.height
                  && Int(dims.height) == configuredVideo?.width)
            if !matchesConfigured {
                if isUDP, withinUnconfiguredLimits {
                    bitstream = ReceiverVideoBitstream(codec: videoCodec)
                    pendingKeyframeAfterStreamConfig = true
                    waitingForKeyframe = true
                    requestKeyframeIfNeeded()
                    return
                }
                rejectVideo("视频尺寸与配置不符，请重新连接"); return
            }
            displayLayer.flush()
            videoBackpressure = ReceiverVideoBackpressurePolicy()
            displayLayerNotReadySince = nil
            formatDesc = format
            let generation = inputSendBudget.generation
            DispatchQueue.main.async {
                guard self.inputSendBudget.generation == generation else { return }
                self.videoSize = CGSize(width: Int(dims.width), height: Int(dims.height))
            }
            setStatus("正在接收 \(dims.width)×\(dims.height) · \(videoCodec.rawValue.uppercased())")
        }
        guard !packet.slices.isEmpty else { return }
        if displayLayer.status == .failed { failVideo(); return }
        if waitingForKeyframe, !packet.keyframe { requestKeyframeIfNeeded(); return }
        if !(useMetalPath && onDecodedFrame != nil) {
            switch videoBackpressure.action(isReady: displayLayer.isReadyForMoreMediaData,
                                            now: ProcessInfo.processInfo.systemUptime) {
            case .enqueue: break
            case .flushAndWait:
                decodeFlushes += 1
                displayLayer.flush()
                waitingForKeyframe = true
                requestKeyframeIfNeeded()
                return
            case .wait: requestKeyframeIfNeeded(); return
            }
        }
        waitingForKeyframe = false
        let metadata = packet.metadata.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let captureMs = metadata?["cap"] as? Double
        let sendMs = metadata?["snd"] as? Double
        let nowUptime = ProcessInfo.processInfo.systemUptime
        if !isUDP {
            let syncAgeMs: Double?
            if let captureMs, let offset = clockOffsetMs {
                syncAgeMs = (nowMs + offset) - captureMs
            } else {
                syncAgeMs = nil
            }
            if ReceiverFrameAgePolicy.isExpired(
                receivedAtUptime: receivedAtUptime,
                nowUptime: nowUptime,
                isKeyframe: packet.keyframe,
                synchronizedAgeMs: syncAgeMs
            ) {
                waitingForKeyframe = true
                requestKeyframeIfNeeded()
                return
            }
        }
        if !(useMetalPath && onDecodedFrame != nil) {
            if displayLayer.isReadyForMoreMediaData {
                displayLayerNotReadySince = nil
            } else if displayLayerNotReadySince == nil {
                displayLayerNotReadySince = nowUptime
            }
        } else {
            displayLayerNotReadySince = nil
        }
        audioPlayer?.updateVideoPipelineDelay?(udpJitterActive: isUDP, explicitDelayMs: -1)
        if let captureMs, captureMs.isFinite {
            audioPlayer?.recordVideoRender?(
                captureTimestampMs: Int64(captureMs.rounded()),
                renderMonoMs: nowUptime * 1_000.0
            )
        }
        enqueueFrame(packet.slices, isKeyframe: packet.keyframe,
                     captureMs: captureMs,
                     sendMs: sendMs,
                     receivedAtUptime: receivedAtUptime)
    }

    private func resetVideoDecoder() {
        videoBackpressure = ReceiverVideoBackpressurePolicy()
        displayLayerNotReadySince = nil
        latestDecodeMs = 0
        formatDesc = nil
        bitstream = ReceiverVideoBitstream(codec: videoCodec)
        waitingForKeyframe = true
        lastKeyframeRequest = .distantPast
        decodeErrorCount = 0
        displayLayer.flushAndRemoveImage()
        if let session = decompressionSession { VTDecompressionSessionInvalidate(session) }
        decompressionSession = nil
    }

    private func configureVideo(_ object: [String: Any]) {
        let swappedEnvelope = nativeVideoEnvelope.flatMap {
            AppleVideoPolicy.nativeHighRefreshEnvelope(width: $0.height, height: $0.width, maxFps: $0.fps)
        }
        guard let config = AppleVideoConfiguration(object,
                maxWidth: videoLimits.width, maxHeight: videoLimits.height,
                maxFps: displayMaxFps, nativeEnvelope: nativeVideoEnvelope)
            ?? AppleVideoConfiguration(object,
                maxWidth: videoLimits.height, maxHeight: videoLimits.width,
                maxFps: displayMaxFps, nativeEnvelope: swappedEnvelope) else {
            rejectVideo("视频配置超出能力，请降低画质后重连"); return
        }
        guard videoFallback.accepts(config.codec) else {
            rejectVideo("HEVC 回退失败，请选择 H.264 后重连"); return
        }
        if let version = (object["configVersion"] as? NSNumber)?.int64Value, version >= 0 {
            activeConfigVersion = version
        }
        let changed = configuredVideo?.codec != config.codec
            || configuredVideo?.width != config.width || configuredVideo?.height != config.height
        videoCodec = config.codec
        configuredVideo = config
        if changed { resetVideoDecoder() }
        if config.codec == .hevc, !supportsHEVC { failVideo(); return }
        if config.codec == .h264 { videoFallback.receivedH264() }
        if pendingKeyframeAfterStreamConfig {
            pendingKeyframeAfterStreamConfig = false
            requestKeyframeAfterConfigHook?()
        }
        let generation = inputSendBudget.generation
        DispatchQueue.main.async {
            guard self.inputSendBudget.generation == generation else { return }
            self.requestedFps = config.fps
            self.codecLabel = config.codec == .hevc ? "HEVC" : "H.264"
        }
    }

    private func rejectVideo(_ message: String) {
        dropInputConnection(generation: inputSendBudget.generation, status: message)
    }

    private func configureUDPMedia(_ object: [String: Any]) {
        guard let config = UDPMediaConfigMessage(jsonObject: object),
              let conn = connection else { return }
        if config.sessionEpoch < lastUdpMediaEpoch {
            return
        }
        if config.sessionEpoch == lastUdpMediaEpoch, let existing = udpMediaSession {
            sendControl([
                "type": "udpMediaReady",
                "sessionEpoch": config.sessionEpoch,
                "udpPort": Int(existing.localPort),
            ], on: conn)
            return
        }
        udpMediaSession?.stop()
        udpMediaSession = nil
        let generation = inputSendBudget.generation
        let senderHost = UDPEndpointResolver.hostString(from: conn.currentPath?.remoteEndpoint)
            ?? UDPEndpointResolver.hostString(from: conn.endpoint)
        guard let session = UDPMediaReceiverSession(
            config: config,
            generation: generation,
            senderHost: senderHost
        ) else { return }
        lastUdpMediaEpoch = config.sessionEpoch

        session.onFrameReady = { [weak self, weak conn] gen, frame in
            guard let self else { return }
            let receivedAtUptime = ProcessInfo.processInfo.systemUptime
            self.queue.async { [weak self, weak conn] in
                guard let self, let conn,
                      self.running,
                      self.connection === conn,
                      self.inputSendBudget.generation == gen else { return }
                self.lastDataReceived = Date()
                if self.configuredVideo == nil {
                    self.pendingKeyframeAfterStreamConfig = true
                    self.waitingForKeyframe = true
                    return
                }
                if self.activeConfigVersion > 0, frame.configVersion > 0,
                   frame.configVersion != self.activeConfigVersion {
                    self.waitingForKeyframe = true
                    if frame.configVersion < self.activeConfigVersion {
                        self.requestKeyframeIfNeeded()
                    } else {
                        self.pendingKeyframeAfterStreamConfig = true
                    }
                    return
                }
                self.bytesThisWindow += frame.annexB.count
                let prefix = Data("{\"cap\":\(frame.captureTimestampMs),\"snd\":\(frame.captureTimestampMs)}".utf8)
                var combined = Data(capacity: prefix.count + frame.annexB.count)
                combined.append(prefix)
                combined.append(frame.annexB)
                self.handleAnnexB(combined, receivedAtUptime: receivedAtUptime, isUDP: true)
                let decodeMs = self.decodeWindow.last ?? self.latestDecodeMs
                session.updateReceiverTelemetry(
                    rttMs: self.lastRttMs,
                    decodeQueueMs: Int(decodeMs.rounded()),
                    renderFps: self.queueRenderedFps
                )
            }
        }
        session.onKeyframeNeeded = { [weak self, weak conn] gen, _ in
            guard let self else { return }
            self.queue.async { [weak self, weak conn] in
                guard let self, let conn,
                      self.running,
                      self.connection === conn,
                      self.inputSendBudget.generation == gen else { return }
                self.requestKeyframeIfNeeded()
            }
        }
        session.onCursor = { [weak self, weak conn] gen, cursor in
            guard let self, cursor.isValid else { return }
            self.queue.async { [weak self, weak conn] in
                guard let self, let conn,
                      self.running,
                      self.connection === conn,
                      self.inputSendBudget.generation == gen else { return }
                self.lastDataReceived = Date()
                guard cursor.sequence > self.lastCursorSequence else { return }
                self.lastCursorSequence = cursor.sequence
                let x = Double(cursor.normalizedX)
                let y = Double(cursor.normalizedY)
                let visible = cursor.visible
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.inputSendBudget.generation == gen else { return }
                    self.onCursor?(x, y, visible)
                }
            }
        }
        session.onAudio = { [weak self, weak conn] gen, audio in
            guard let self, audio.isValid,
                  audio.formatFlags == UDPMediaAudioPayload.formatPCM16LE
                    || audio.formatFlags == UDPMediaAudioPayload.formatOpus else { return }
            self.queue.async { [weak self, weak conn] in
                guard let self, let conn,
                      self.running,
                      self.connection === conn,
                      self.inputSendBudget.generation == gen else { return }
                self.handleIncomingAudio(audio, isUDP: true)
            }
        }
        udpMediaSession = session
        audioPlayer?.updateVideoPipelineDelay?(udpJitterActive: true, explicitDelayMs: -1)
        sendControl([
            "type": "udpMediaReady",
            "sessionEpoch": config.sessionEpoch,
            "udpPort": Int(session.localPort),
        ], on: conn)
    }

    private func handleIncomingAudio(_ audio: UDPMediaAudioPayload, isUDP: Bool) {
        guard audio.isValid,
              audio.formatFlags == UDPMediaAudioPayload.formatPCM16LE
                || audio.formatFlags == UDPMediaAudioPayload.formatOpus else { return }
        lastDataReceived = Date()
        if let prevSeq = lastAudioSequence {
            guard UDPMediaHeader.isFrameIdNewer(audio.audioSeq, than: prevSeq) else { return }
        }
        lastAudioSequence = audio.audioSeq
        let arrivalMonoMs = ProcessInfo.processInfo.systemUptime * 1_000.0
        if isUDP || udpMediaSession == nil {
            audioPlayer?.updateVideoPipelineDelay?(udpJitterActive: isUDP, explicitDelayMs: -1)
        }
        if let enqueueEncoded = audioPlayer?.enqueueEncodedAudio {
            enqueueEncoded(
                audio.pcmBytes,
                Int(audio.formatFlags),
                Int(audio.sampleRate),
                Int(audio.channels),
                audio.captureTimestampMs,
                arrivalMonoMs
            )
        } else if audio.formatFlags == UDPMediaAudioPayload.formatPCM16LE {
            audioPlayer?.enqueuePCM(
                audio.pcmBytes,
                sampleRate: Int(audio.sampleRate),
                channels: Int(audio.channels)
            )
        }
    }

    private func failVideo() {
        guard videoCodec == .hevc else {
            rejectVideo("视频解码失败，请重新连接"); return
        }
        guard videoFallback.failHEVC(now: ProcessInfo.processInfo.systemUptime),
              let conn = connection else { return }
        resetVideoDecoder()
        sendControl(["type": "codecFailure", "codec": "hevc", "message": "Apple HEVC decode failed"], on: conn)
        setStatus("HEVC 不可用，正在回退 H.264")
        queue.asyncAfter(deadline: .now() + 3) { [weak self, weak conn] in
            guard let self, let conn, self.connection === conn,
                  self.videoFallback.expired(now: ProcessInfo.processInfo.systemUptime) else { return }
            self.rejectVideo("HEVC 回退超时，请在发送端选择 H.264 后重连")
        }
    }

    private func enqueueFrame(_ nalus: [Data], isKeyframe: Bool = false,
                              captureMs: Double? = nil, sendMs: Double? = nil,
                              receivedAtUptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard let formatDesc else { return }

        // Build one AVCC buffer: each NALU prefixed with 4-byte big-endian length.
        var avcc = Data(capacity: nalus.reduce(0) { $0 + $1.count + 4 })
        for nalu in nalus {
            var len = UInt32(nalu.count).bigEndian
            avcc.append(Data(bytes: &len, count: 4))
            avcc.append(nalu)
        }

        // Allocate a block buffer that OWNS its memory and copy the bytes in —
        // referencing a transient Swift buffer here is a use-after-free.
        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,                   // let CoreMedia allocate
                blockLength: avcc.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil, offsetToData: 0,
                dataLength: avcc.count, flags: 0,
                blockBufferOut: &blockBuffer) == noErr,
              let blockBuffer else { return }
        let copyStatus = avcc.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(
                with: raw.baseAddress!, blockBuffer: blockBuffer,
                offsetIntoDestination: 0, dataLength: avcc.count)
        }
        guard copyStatus == noErr else { return }

        var sample: CMSampleBuffer?
        var sizeArr = [avcc.count]
        CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 0, sampleTimingArray: nil,
            sampleSizeEntryCount: 1, sampleSizeArray: &sizeArr,
            sampleBufferOut: &sample)

        guard let sample else { return }

        let metalActive = useMetalPath && onDecodedFrame != nil
        if loggedDisplayPath != metalActive {
            loggedDisplayPath = metalActive
            Log.info("display path: metal=\(useMetalPath) sink=\(onDecodedFrame != nil)")
            if let session = decompressionSession {
                VTDecompressionSessionInvalidate(session)
                decompressionSession = nil
            }
            decodeErrorCount = 0
            lastKeyframeRequest = .distantPast
            displayLayerNotReadySince = nil
            displayLayer.flushAndRemoveImage()
            if !isKeyframe {
                waitingForKeyframe = true
                requestKeyframeIfNeeded()
                return
            }
        }
        if metalActive {
            decodeAndRender(sample, captureMs: captureMs)
        } else {
            // Display immediately: low latency, no PTS scheduling.
            if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
               CFArrayGetCount(attachments) > 0 {
                let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
                CFDictionarySetValue(dict,
                    Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                    Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            }

            if displayLayer.status == .failed {
                Log.info("display layer failed (\(String(describing: displayLayer.error))) — flushing")
                decodeFlushes += 1
                displayLayerNotReadySince = nil
                displayLayer.flush()
            }
            displayLayer.enqueue(sample)

            let postEnqueueUptime = ProcessInfo.processInfo.systemUptime
            let localSubmitMs = max(0, (postEnqueueUptime - receivedAtUptime) * 1000)
            let occupancyMs = displayLayerNotReadySince.map { max(0, (postEnqueueUptime - $0) * 1000) } ?? 0
            let sampleDecodeMs = localSubmitMs + occupancyMs
            if sampleDecodeMs.isFinite, sampleDecodeMs >= 0, sampleDecodeMs < 5000 {
                latestDecodeMs = sampleDecodeMs
                decodeWindow.append(sampleDecodeMs)
                if decodeWindow.count > maxWindowSamples {
                    decodeWindow.removeFirst()
                }
            }
        }

        firstVideoDeadline.receivedFrame()

        // Per-frame timing for the performance overlay.
        let now = Date()
        if let last = lastFrameAt {
            let ms = now.timeIntervalSince(last) * 1000
            frameIntervals.append(ms)
            if frameIntervals.count > maxSamples { frameIntervals.removeFirst() }
            if ms > 50 { stallsThisWindow += 1 }
        }
        lastFrameAt = now

        // True end-to-end latency: Mac capture timestamp vs our clock mapped
        // onto the Mac's via the ping/pong offset.
        if let captureMs, let sendMs {
            let encodeMs = sendMs - captureMs
            if encodeMs.isFinite, encodeMs >= 0, encodeMs < 5000 {
                encodeWindow.append(encodeMs)
                if encodeWindow.count > maxWindowSamples { encodeWindow.removeFirst() }
            }
            if let offset = clockOffsetMs {
                let e2e = (nowMs + offset) - captureMs
                if e2e.isFinite, e2e > -50, e2e < 5000 {
                    e2eWindow.append(e2e)
                    if e2eWindow.count > maxWindowSamples { e2eWindow.removeFirst() }
                    e2eRing.append(max(e2e, 0))
                    if e2eRing.count > maxSamples { e2eRing.removeFirst() }
                }
            }
        }

        framesThisWindow += 1
        let elapsed = now.timeIntervalSince(fpsWindowStart)
        if elapsed >= 1.0 {
            let fps = Int(Double(framesThisWindow) / elapsed)
            queueRenderedFps = fps
            var stats = PerfStats()
            stats.fps = fps
            stats.mbps = Double(bytesThisWindow) * 8 / elapsed / 1_000_000
            stats.samples = frameIntervals
            if !frameIntervals.isEmpty {
                stats.avgFrameMs = frameIntervals.reduce(0, +) / Double(frameIntervals.count)
                stats.maxFrameMs = frameIntervals.max() ?? 0
            }
            stats.stalls = stallsThisWindow
            stats.decodeFlushes = decodeFlushes
            stats.e2eP50 = percentile(e2eWindow, 0.5)
            stats.e2eP95 = percentile(e2eWindow, 0.95)
            stats.encodeP50 = percentile(encodeWindow, 0.5)
            stats.rttMs = lastRttMs
            stats.e2eSamples = e2eRing
            stats.transport = transport
            stats.macDrops = macDrops
            stats.macPending = macPending
            stats.inputP50 = macInputP50
            stats.inputP95 = macInputP95
            stats.capFps = macCapFps
            stats.decodeP50 = percentile(decodeWindow, 0.5)
            stats.photonP50 = percentile(photonWindow, 0.5)
            stats.photonP95 = percentile(photonWindow, 0.95)
            framesThisWindow = 0
            bytesThisWindow = 0
            stallsThisWindow = 0
            fpsWindowStart = now

            // Every 1s, report the aggregate to the Mac so its log and adaptive
            // bitrate controller receive timely feedback aligned with Android.
            statsReportCounter += 1
            if statsReportCounter >= 1 {
                statsReportCounter = 0
                sendControl([
                    "type": "stats",
                    "transport": transport,
                    "fps": fps,
                    "mbps": (stats.mbps * 10).rounded() / 10,
                    "e2e50": stats.e2eP50.rounded(),
                    "e2e95": stats.e2eP95.rounded(),
                    "enc50": stats.encodeP50.rounded(),
                    "rtt": lastRttMs.rounded(),
                    "stalls": stats.stalls,
                    "inp50": macInputP50.rounded(),
                    "capFps": macCapFps,
                    "dec50": stats.decodeP50.rounded(),
                    "ph50": stats.photonP50.rounded(),
                    "ph95": stats.photonP95.rounded(),
                    "offsetKnown": clockOffsetMs != nil,
                ])
                e2eWindow.removeAll(keepingCapacity: true)
                encodeWindow.removeAll(keepingCapacity: true)
                decodeWindow.removeAll(keepingCapacity: true)
                photonWindow.removeAll(keepingCapacity: true)
            }

            let generation = inputSendBudget.generation
            DispatchQueue.main.async {
                guard self.inputSendBudget.generation == generation else { return }
                self.fps = fps
                self.perf = stats
            }
        }
    }

    // MARK: - Explicit decode (Metal renderer path)

    private func ensureDecompressionSession() {
        guard let formatDesc else { return }
        if let session = decompressionSession {
            if VTDecompressionSessionCanAcceptFormatDescription(session, formatDescription: formatDesc) {
                return
            }
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
        // NV12: the decoder's native output — BGRA would add a conversion
        // pass inside VideoToolbox (measured ~7ms); the YUV→RGB happens in
        // the renderer's fragment shader instead (~free).
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: nil, formatDescription: formatDesc, decoderSpecification: nil,
            imageBufferAttributes: attrs as CFDictionary, outputCallback: nil,
            decompressionSessionOut: &session)
        if status != noErr {
            Log.info("VTDecompressionSessionCreate failed: \(status)")
            failVideo()
        } else { decompressionSession = session }
    }

    /// Synchronous hardware decode — the handler runs before this returns,
    /// so blocking in the renderer (nextDrawable) is our frame pacing.
    private func decodeAndRender(_ sample: CMSampleBuffer, captureMs: Double?) {
        ensureDecompressionSession()
        guard let session = decompressionSession else { return }
        let t0 = nowMs
        let generation = inputSendBudget.generation
        let status = VTDecompressionSessionDecodeFrame(
            session, sampleBuffer: sample, flags: [], infoFlagsOut: nil
        ) { [weak self] status, _, imageBuffer, _, _ in
            guard let self, self.inputSendBudget.generation == generation else { return }
            if status == noErr, let imageBuffer {
                self.decodeErrorCount = 0
                let decodeMs = self.nowMs - t0
                if decodeMs.isFinite, decodeMs >= 0, decodeMs < 5000 {
                    self.latestDecodeMs = decodeMs
                    self.decodeWindow.append(decodeMs)
                    if self.decodeWindow.count > self.maxWindowSamples {
                        self.decodeWindow.removeFirst()
                    }
                }
                self.onDecodedFrame?(imageBuffer, captureMs)
            } else {
                if self.decodeErrorCount % 60 == 0 {
                    Log.info("decode output error: \(status) imageBuffer=\(imageBuffer != nil)")
                }
                self.decodeErrorCount += 1
                // Joined mid-GOP (e.g. the renderer attached after the
                // connect-time IDR, and periodic keyframes are off) — ask
                // the Mac for a fresh sync point.
                self.requestKeyframeIfNeeded()
            }
        }
        if status != noErr {
            decodeFlushes += 1
            decodeErrorCount += 1
            if decodeErrorCount % 60 == 1 {
                Log.info("decode call error: \(status) (\(decodeErrorCount) total)")
            }
            requestKeyframeIfNeeded()
        }
        if decodeErrorCount >= 3 { failVideo() }
    }

    private var lastKeyframeRequest = Date.distantPast
    private func requestKeyframeIfNeeded() {
        guard Date().timeIntervalSince(lastKeyframeRequest) > 1 else { return }
        lastKeyframeRequest = Date()
        Log.info("requesting keyframe (decoder needs sync)")
        sendControl(["type": "kf"])
    }

    private func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let idx = min(sorted.count - 1, Int(Double(sorted.count) * p))
        return sorted[idx]
    }

    // MARK: - Helpers

    private func setStatus(_ text: String) {
        Log.info("status: \(text)")
        let generation = inputSendBudget.generation
        DispatchQueue.main.async {
            guard self.inputSendBudget.generation == generation else { return }
            self.status = text
        }
    }

    private func setConnected(_ value: Bool, updateStatus: Bool = true) {
        let generation = inputSendBudget.generation
        DispatchQueue.main.async {
            guard self.inputSendBudget.generation == generation else { return }
            self.connected = value; if !value { self.encrypted = false }
        }
        if !value {
            if updateStatus {
                setStatus(security.encrypted ? "正在安全监听 :\(port)" : "旧版兼容（未加密） :\(port)")
            }
        } else {
            if updateStatus {
                setStatus(peerID == nil ? "已连接（未加密兼容）" : "已加密连接")
            }
            // Remember the first ever successful connection to a Mac so the
            // first-run onboarding hint never reappears (issue #49).
            if !UserDefaults.standard.bool(forKey: "hasConnectedBefore") {
                UserDefaults.standard.set(true, forKey: "hasConnectedBefore")
            }
        }
    }
}
