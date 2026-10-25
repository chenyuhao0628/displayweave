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
    // Metal renderer path only:
    var decodeP50 = 0.0          // VTDecompressionSession decode, ms
    var photonP50 = 0.0          // Mac capture → frame actually on glass, ms
    var photonP95 = 0.0
}

final class PhoneReceiver: ObservableObject {

    @Published var status = "正在启动…"
    @Published var fps = 0
    @Published var connected = false
    @Published private(set) var encrypted = false
    @Published var videoSize = CGSize.zero   // for touch coordinate mapping
    @Published var perf = PerfStats()
    @Published private(set) var pencilAvailable = false
    @Published private(set) var pencilExtendedAvailable = false
    @Published private(set) var pencilShortcutsAvailable = false
    @Published private(set) var selectedPencilTool = PencilTool.pen
    private var pencilActionGrant: String? // main-thread projection
    var onPencilToolChange: (() -> Void)?
    @Published private(set) var pencilActionStatus = "等待高级 Pencil 协商"
    var onInputReset: (() -> Void)?
    private let inputSendBudget = InputSendBudget()
    private var pencilNegotiated = false
    private var pencilExtendedNegotiated = false
    private var pencilActionSession: String?
    private var pencilActionSequence: UInt64 = 0
    private var pencilForwarder = PencilInputForwarder()
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
    private var firstVideoDeadline = ReceiverFirstVideoDeadline()
    private var displayMaxFps = 60
    @Published private(set) var requestedFps = 60
    @Published private(set) var codecLabel = "H.264"

    // Liveness: the Mac streams video and pings every 2s; if nothing arrives
    // for 5s the connection is half-open (Mac killed, tunnel died) — drop it
    // so the listener can accept a fresh one.
    private var lastDataReceived = Date()
    private var port: UInt16 = 9000
    private var monitorsStarted = false

    private var framesThisWindow = 0
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
        onInputReset = nil; onPencilToolChange = nil
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
    private var photonWindow: [Double] = []
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
            if photon > -50, photon < 5000 {
                self.photonWindow.append(max(photon, 0))
            }
        }
    }

    let displayLayer: AVSampleBufferDisplayLayer

    /// Native panel size in pixels + scale, announced to the Mac in a "hello"
    /// message so it can size the virtual display. Orientation-dependent:
    /// rotating the phone re-announces with swapped dimensions and the Mac
    /// rebuilds the virtual display as a portrait/landscape monitor.
    private var nativeLong = 0
    private var nativeShort = 0
    private(set) var devicePixelsWide = 0
    private(set) var devicePixelsHigh = 0
    var deviceScale: Double = 2
    // Name advertised over Bonjour for the Mac's WiFi picker. iOS 16+ returns
    // a generic "iPhone" from UIDevice.current.name (the user-assigned name
    // needs an entitlement Apple gates behind approval and personal teams
    // can't get), so this is user-editable in Settings. The USB picker gets
    // the real name host-side via lockdownd regardless.
    var serviceName = "DisplayWeave"

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
        displayMaxFps = AppleVideoPolicy.frameRate(maximum: maxFps)
        nativeLong = long
        nativeShort = short
        deviceScale = scale
        if devicePixelsWide == 0 {   // default landscape until the view reports
            devicePixelsWide = long
            devicePixelsHigh = short
        }
    }

    func setOrientation(portrait: Bool) {
        queue.async {
            let w = portrait ? self.nativeShort : self.nativeLong
            let h = portrait ? self.nativeLong : self.nativeShort
            guard w > 0, w != self.devicePixelsWide else { return }
            self.devicePixelsWide = w
            self.devicePixelsHigh = h
            Log.info("orientation changed -> \(w)x\(h)")
            if let connection = self.connection { self.sendHello(on: connection) }
        }
    }

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        displayLayer.videoGravity = .resizeAspect
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
            if !self.monitorsStarted {
                self.monitorsStarted = true
                self.schedulePing()
                self.scheduleWatchdog()
            }
        }
    }

    func ensureListening() {
        queue.async {
            if !self.running { self.listenerGeneration &+= 1 }
            self.running = true
            guard !self.listenerHealthy else { return }
            self.restartListener()
        }
    }

    func stop() {
        queue.async {
            self.running = false
            self.listenerGeneration &+= 1
            let oldListener = self.listener
            self.listener = nil
            oldListener?.cancel()
            self.admissionPool.cancelAll()
            if case .tls(_, let state) = self.security { state.stopPairing() }
            self.listenerHealthy = false
            let old = self.connection
            self.connection = nil
            self.peerID = nil
            self.resetStreamState()
            self.setConnected(false)
            self.setStatus("已在后台断开")
            if let old {
                let payload = Data("{\"type\":\"goodbye\"}".utf8)
                old.send(content: ReceiverFrameDecoder.frame(payload), completion: .contentProcessed { _ in old.cancel() })
                self.queue.asyncAfter(deadline: .now() + 0.25) { old.cancel() }
            }
        }
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
            // usbmux-forwarded (cable) connections arrive from loopback;
            // anything else came over the network.
            let peer = String(describing: conn.endpoint)
            self.transport = (peer.hasPrefix("127.0.0.1") || peer.hasPrefix("::1")
                              || peer.hasPrefix("localhost")) ? "USB" : "WiFi"
            // Replace any existing connection and reset decoder state.
            self.connection?.cancel()
            self.connection = conn
            self.peerID = authenticatedPeer?.installID
            self.resetStreamState()
            conn.stateUpdateHandler = { [weak self, weak conn] state in
                guard let self, let conn, self.running, self.connection === conn else { return }
                switch state {
                case .ready:
                    self.lastDataReceived = Date()
                    self.firstVideoDeadline.begin(at: ProcessInfo.processInfo.systemUptime)
                    self.setStatus("已连接，正在等待 Mac 画面…")
                    self.setConnected(true)
                    self.sendHello(on: conn)
                case .failed, .cancelled:
                    self.connection = nil
                    self.resetStreamState()
                    self.setConnected(false)
                default: break
                }
            }
            let encrypted = authenticatedPeer != nil
            let generation = self.inputSendBudget.generation
            DispatchQueue.main.async {
                guard self.inputSendBudget.generation == generation else { return }
                self.encrypted = encrypted
            }
            if encrypted {
                self.lastDataReceived = Date()
                self.firstVideoDeadline.begin(at: ProcessInfo.processInfo.systemUptime)
                self.setStatus("安全连接已建立，正在等待 Mac 画面…")
                self.setConnected(true)
                self.sendHello(on: conn)
            } else { conn.start(queue: self.queue) }
            self.receive(on: conn)
    }

    // MARK: - Liveness (ping + watchdog)

    private func schedulePing() {
        queue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            if self.connection?.state == .ready {
                self.sendControl(["type": "ping", "t": self.nowMs])
            }
            self.schedulePing()
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
            pencilNegotiated = PencilProtocol.supports(obj["inputCaps"] as? [String])
            pencilExtendedNegotiated = pencilNegotiated && peerID != nil && (obj["inputCaps"] as? [String])?.contains(PencilProtocol.extendedCapability) == true
            let candidate = obj["pencilActionSession"] as? String
            let session = pencilExtendedNegotiated && candidate.flatMap(UUID.init(uuidString:)) != nil ? candidate : nil
            if session != pencilActionSession { pencilActionSequence = 0 }
            pencilActionSession = session
            let enabled = pencilNegotiated, generation = inputSendBudget.generation
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
            let visible = (obj["v"] as? Int ?? 0) == 1
            let x = obj["x"] as? Double ?? 0
            let y = obj["y"] as? Double ?? 0
            guard x.isFinite, y.isFinite else { return }
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
        default:
            break
        }
    }

    private func scheduleWatchdog() {
        queue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
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
            self.scheduleWatchdog()
        }
    }

    private func resetStreamState() {
        let generation = inputSendBudget.reset(accepting: connection != nil)
        pencilNegotiated = false
        pencilExtendedNegotiated = false
        pencilActionSession = nil; pencilActionSequence = 0
        pencilForwarder = PencilInputForwarder()
        DispatchQueue.main.async {
            guard self.inputSendBudget.generation == generation else { return }
            self.pencilAvailable = false
            self.pencilExtendedAvailable = false; self.pencilShortcutsAvailable = false
            self.pencilActionGrant = nil; self.selectedPencilTool = .pen
            self.pencilActionStatus = "等待高级 Pencil 协商"
            self.onInputReset?()
        }
        firstVideoDeadline = ReceiverFirstVideoDeadline()
        macDrops = 0; macPending = 0; macInputP50 = 0; macInputP95 = 0; macCapFps = 0
        frameDecoder = ReceiverFrameDecoder()
        videoCodec = .h264
        videoFallback = AppleVideoFallbackPolicy()
        configuredVideo = nil
        resetVideoDecoder()
        DispatchQueue.main.async {
            guard self.inputSendBudget.generation == generation else { return }
            self.requestedFps = 60
            self.codecLabel = "H.264"
        }
        lastFrameAt = nil
        frameIntervals.removeAll()
        decodeFlushes = 0
        displayLayer.flushAndRemoveImage()
        framesThisWindow = 0; bytesThisWindow = 0; stallsThisWindow = 0
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
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
        decodeWindow.removeAll(keepingCapacity: true)
        photonWindow.removeAll(keepingCapacity: true)
    }

    // MARK: - Control messages (phone -> Mac)

    private var videoLimits: (width: Int, height: Int) {
        devicePixelsHigh > devicePixelsWide ? (2304, 4096) : (4096, 2304)
    }

    private func sendHello(on conn: NWConnection) {
        let codecs = supportsHEVC ? ["h264", "hevc"] : ["h264"]
        sendControl([
            "type": "hello",
            "pixelsWide": devicePixelsWide,
            "pixelsHigh": devicePixelsHigh,
            "scale": deviceScale,
            "device": UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone",
            "id": Self.installID,
            "inputCaps": peerID != nil ? [PencilProtocol.capability, PencilProtocol.extendedCapability] : [PencilProtocol.capability],
            "capabilities": [AppleVideoPolicy.capability],
            "refreshRate": displayMaxFps, "maxFps": displayMaxFps,
            "displayMaxFrameRate": displayMaxFps,
            "supportedCodecs": codecs, "preferredCodec": supportsHEVC ? "hevc" : "h264",
            "maxEncodeWide": videoLimits.width, "maxEncodeHigh": videoLimits.height,
            "videoCaps": codecs.map { ["codec": $0, "maxWidth": videoLimits.width,
                "maxHeight": videoLimits.height, "maxFrameRate": displayMaxFps,
                "maxPixelsPerSecond": AppleVideoPolicy.maxPixelsPerSecond] as [String: Any] },
        ], on: conn)
        Log.info("hello sent")
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
        setConnected(false)
        setStatus(status)
    }

    /// Reserve before dispatch: a slow video queue cannot accumulate unlimited input closures.
    private func enqueueControl(expectedGeneration: UInt64? = nil, on selected: NWConnection? = nil,
                                messages: @escaping () -> [[String: Any]]) {
        switch inputSendBudget.reserve(expectedGeneration: expectedGeneration) {
        case .unavailable: return
        case .overflow(let generation):
            queue.async { self.dropInputConnection(generation: generation, status: "输入发送拥堵，请在 Mac 重新连接") }
        case .accepted(let ticket):
            queue.async {
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
                    self.queue.async {
                        guard self.connection === conn, self.inputSendBudget.complete(ticket) else { return }
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
            [weak self] data, _, isComplete, error in
            guard let self, self.running, self.connection === conn else { return }
            if let data, !data.isEmpty {
                self.lastDataReceived = Date()
                self.bytesThisWindow += data.count
                do {
                    for frame in try self.frameDecoder.append(data) {
                        guard self.connection === conn else { return }
                        self.handleAnnexB(frame)
                    }
                } catch {
                    self.connection = nil
                    conn.cancel()
                    self.resetStreamState()
                    self.setConnected(false)
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

    private func handleAnnexB(_ data: Data) {
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
            guard dims.width > 0, dims.height > 0, dims.width <= 8192, dims.height <= 8192,
                  Int64(dims.width) * Int64(dims.height) <= 33_554_432,
                  configuredVideo == nil || (Int(dims.width) == configuredVideo?.width
                    && Int(dims.height) == configuredVideo?.height) else {
                rejectVideo("视频尺寸与配置不符，请重新连接"); return
            }
            displayLayer.flush()
            videoBackpressure = ReceiverVideoBackpressurePolicy()
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
            case .wait: return
            }
        }
        waitingForKeyframe = false
        let metadata = packet.metadata.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        enqueueFrame(packet.slices, captureMs: metadata?["cap"] as? Double,
                     sendMs: metadata?["snd"] as? Double)
    }

    private func resetVideoDecoder() {
        videoBackpressure = ReceiverVideoBackpressurePolicy()
        formatDesc = nil
        bitstream = ReceiverVideoBitstream(codec: videoCodec)
        waitingForKeyframe = true
        decodeErrorCount = 0
        displayLayer.flushAndRemoveImage()
        if let session = decompressionSession { VTDecompressionSessionInvalidate(session) }
        decompressionSession = nil
    }

    private func configureVideo(_ object: [String: Any]) {
        guard let config = AppleVideoConfiguration(object, maxWidth: videoLimits.width,
                maxHeight: videoLimits.height, maxFps: displayMaxFps) else {
            rejectVideo("视频配置超出能力，请降低画质后重连"); return
        }
        guard videoFallback.accepts(config.codec) else {
            rejectVideo("HEVC 回退失败，请选择 H.264 后重连"); return
        }
        let changed = configuredVideo?.codec != config.codec
            || configuredVideo?.width != config.width || configuredVideo?.height != config.height
        videoCodec = config.codec
        configuredVideo = config
        if changed { resetVideoDecoder() }
        if config.codec == .hevc, !supportsHEVC { failVideo(); return }
        if config.codec == .h264 { videoFallback.receivedH264() }
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

    private func enqueueFrame(_ nalus: [Data], captureMs: Double? = nil, sendMs: Double? = nil) {
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

        if loggedDisplayPath != (useMetalPath && onDecodedFrame != nil) {
            loggedDisplayPath = useMetalPath && onDecodedFrame != nil
            Log.info("display path: metal=\(useMetalPath) sink=\(onDecodedFrame != nil)")
        }
        if useMetalPath, onDecodedFrame != nil {
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
                displayLayer.flush()
            }
            displayLayer.enqueue(sample)
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
            encodeWindow.append(sendMs - captureMs)
            if let offset = clockOffsetMs {
                let e2e = (nowMs + offset) - captureMs
                if e2e > -50, e2e < 5000 {
                    e2eWindow.append(e2e)
                    e2eRing.append(max(e2e, 0))
                    if e2eRing.count > maxSamples { e2eRing.removeFirst() }
                }
            }
        }

        framesThisWindow += 1
        let elapsed = now.timeIntervalSince(fpsWindowStart)
        if elapsed >= 1.0 {
            let fps = Int(Double(framesThisWindow) / elapsed)
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

            // Every 5s, report the aggregate to the Mac so its log holds the
            // full pipeline picture for offline analysis.
            statsReportCounter += 1
            if statsReportCounter >= 5 {
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
                self.decodeWindow.append(self.nowMs - t0)
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

    private func setConnected(_ value: Bool) {
        let generation = inputSendBudget.generation
        DispatchQueue.main.async {
            guard self.inputSendBudget.generation == generation else { return }
            self.connected = value; if !value { self.encrypted = false }
        }
        if !value { setStatus(security.encrypted ? "正在安全监听 :9000" : "旧版兼容（未加密） :9000") }
        else {
            setStatus(peerID == nil ? "已连接（未加密兼容）" : "已加密连接")
            // Remember the first ever successful connection to a Mac so the
            // first-run onboarding hint never reappears (issue #49).
            if !UserDefaults.standard.bool(forKey: "hasConnectedBefore") {
                UserDefaults.standard.set(true, forKey: "hasConnectedBefore")
            }
        }
    }
}
