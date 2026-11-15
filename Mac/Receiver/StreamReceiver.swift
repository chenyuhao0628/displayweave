// Adapted from peetzweg/opendisplay Shared/StreamReceiver.swift (GPL-3.0).
// Source: b9eec1f232fb5ea571c87e8392379a84f47b237f.
// DisplayWeave: Mac H.264/HEVC, bounded frames, exclusive sessions, deterministic
// shutdown, and queue-owned lifecycle. Upstream Annex B/CoreMedia path retained.
import Foundation
import Combine
import Network
import AVFoundation
import CoreGraphics
import CoreMedia
import VideoToolbox

// Connection state is confined to queue; published presentation and callbacks
// to main. InputSendBudget is the locked bridge between those two domains.
final class StreamReceiver: ObservableObject, @unchecked Sendable {
    @Published private(set) var status = "接收已停止"
    @Published private(set) var connected = false
    @Published private(set) var videoSize = CGSize.zero
    @Published private(set) var fps = 0
    @Published private(set) var listeningPort: UInt16 = 0
    @Published private(set) var encrypted = false
    @Published private(set) var codecLabel = "H.264"
    @Published private(set) var inputForwarding = false
    @Published private(set) var inputStatus = "键鼠回传已关闭"
    @Published private(set) var inputGrant: String?
    private var inputGeneration: UInt64 = 0 // main-thread projection of the queue's grant
    private let inputBudget: InputSendBudget
    private var wireInputGrant: String? // receiver queue only
    let displayLayer: AVSampleBufferDisplayLayer
    private let videoRenderer: any MacVideoRendering
    let audioPlayer: any MacAudioPlaying
    private let monotonicTime: () -> TimeInterval
    var onReset: (() -> Void)?
    var onCursor: ((Double, Double, Bool) -> Void)?
    var onCursorImage: ((CGImage, CGPoint, CGSize) -> Void)?

    static let installID = TransportInstallIdentity.value
    private static let maxH264LongEdge = 4096
    private static let maxH264ShortEdge = 2304
    private static let maxHEVC5KLongEdge = 5120
    private static let maxHEVC5KShortEdge = 2880
    private static let maxHEVC5KFrameRate = 60
    private static let maxHEVC5KPixelsPerSecond = 5120 * 2880 * 60

    private let queue = DispatchQueue(label: "displayweave.receiver", qos: .userInteractive)
    private let cursorDelivery = LatestValueRelay<(x: Double, y: Double, visible: Bool)>()
    private let diagnostic: ((String) -> Void)?
    private var diagnosticsStart = ProcessInfo.processInfo.systemUptime
    private var enqueuedFrames = 0
    private var backpressureFlushes = 0
    private var backpressureToleratedFrames = 0
    private var videoBackpressure = ReceiverVideoBackpressurePolicy()
    private var listener: NWListener?
    private lazy var admissionPool = AppleSecureAdmissionPool(queue: queue)
    private let securityProvider: () throws -> AppleReceiverSecurity
    private var security: AppleReceiverSecurity = .legacy
    private var peerID: String?
    private var securityObserver: NSObjectProtocol?
    private var connection: NWConnection?
    private var running = false
    private var generation: UInt64 = 0
    private var port: UInt16 = 9000
    private var advertiseService = true
    private var timer: DispatchSourceTimer?
    private var decoder = ReceiverFrameDecoder()
    private var panel = StreamReceiver.resolvedPanel(
        PanelAnnouncement(pixelsWide: 1920, pixelsHigh: 1080, scale: 1,
                          pointsWide: 1920, pointsHigh: 1080)
    )
    private var serviceName = "DisplayWeave Mac"
    private var maxFps = 60
    private let supportsHEVC: Bool
    private var videoCodec: ReceiverVideoCodec = .h264
    private var bitstream = ReceiverVideoBitstream(codec: .h264)
    private var configuredSize: CGSize?
    private var activeConfigVersion: Int64 = 0
    private var pendingKeyframeAfterStreamConfig = false
    private var hevcFailureSent = false
    private var fallbackDeadline: Date?
    private var firstVideoDeadline: TimeInterval?
    private var hasVideoFrame = false
    private var waitingForKeyframe = true
    private var lastKeyframeRequest = Date.distantPast
    private var lastReceived = Date()
    private var lastRttMs: Double = 0
    private var sampleCount = 0
    private var queueRenderedFps = 0
    private var statsStart = Date()
    private var lastCursorSequence: UInt64 = 0
    private var lastAudioSequence: UInt32?
    private var lastUdpMediaEpoch: Int64 = 0
    private var udpMediaSession: UDPMediaReceiverSession?

    init(displayLayer: AVSampleBufferDisplayLayer = AVSampleBufferDisplayLayer(),
         hardwareHEVCDecode: Bool? = nil,
         inputBudget: InputSendBudget = InputSendBudget(),
         diagnostic: ((String) -> Void)? = nil,
         videoRenderer: (any MacVideoRendering)? = nil,
         audioPlayer: (any MacAudioPlaying)? = nil,
         monotonicTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         securityProvider: @escaping () throws -> AppleReceiverSecurity = { try .live(localID: StreamReceiver.installID) }) {
        self.diagnostic = diagnostic
        self.inputBudget = inputBudget
        self.securityProvider = securityProvider
        self.supportsHEVC = hardwareHEVCDecode ?? VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        self.displayLayer = displayLayer
        self.videoRenderer = videoRenderer ?? MacSampleBufferVideoRenderer(renderer: displayLayer.sampleBufferRenderer)
        if let audioPlayer {
            self.audioPlayer = audioPlayer
        } else if let cls = NSClassFromString("DisplayWeaveMacAudioPlayer") as? NSObject.Type,
                  let live = cls.init() as? any MacAudioPlaying {
            self.audioPlayer = live
        } else {
            self.audioPlayer = NullMacAudioPlayer()
        }
        self.monotonicTime = monotonicTime
        displayLayer.videoGravity = .resizeAspect
        securityObserver = NotificationCenter.default.addObserver(forName: TransportSecurityChange.notification,
            object: nil, queue: nil) { [weak self] notification in
            let kind = notification.userInfo?["kind"] as? String, peer = notification.userInfo?["peer"] as? String
            self?.queue.async { [weak self] in self?.securityChanged(kind: kind, peer: peer) }
        }
    }

    deinit {
        audioPlayer.stop()
        if let securityObserver { NotificationCenter.default.removeObserver(securityObserver) }
    }

    /// Normalizes pixel dimensions to valid even bounds (`2...16384`) and populates
    /// `millimetersWide` / `millimetersHigh` from `CGDisplayScreenSize` when caller
    /// omitted physical dimensions and a valid hardware EDID size exists.
    static func resolvedPanel(_ base: PanelAnnouncement) -> PanelAnnouncement {
        let clampedWide = max(2, min(16384, base.pixelsWide & ~1))
        let clampedHigh = max(2, min(16384, base.pixelsHigh & ~1))
        let clampedScale = (base.scale.isFinite && base.scale > 0)
            ? min(4.0, max(0.5, base.scale))
            : 1.0
        let clampedPointsWide = base.pointsWide.map { max(2, min(16384, $0)) }
        let clampedPointsHigh = base.pointsHigh.map { max(2, min(16384, $0)) }
        let sanitized = PanelAnnouncement(
            pixelsWide: clampedWide,
            pixelsHigh: clampedHigh,
            scale: clampedScale,
            pointsWide: clampedPointsWide,
            pointsHigh: clampedPointsHigh,
            millimetersWide: base.millimetersWide,
            millimetersHigh: base.millimetersHigh
        )
        if sanitized.millimetersWide != nil && sanitized.millimetersHigh != nil {
            return sanitized
        }
        let mainID = CGMainDisplayID()
        guard mainID != 0 else { return sanitized }
        let raw = CGDisplayScreenSize(mainID)
        let bounds = CGDisplayBounds(mainID)
        guard raw.width.isFinite, raw.height.isFinite,
              raw.width >= 50, raw.height >= 50,
              raw.width <= 2000, raw.height <= 2000 else {
            return sanitized
        }
        if bounds.width > 0, bounds.height > 0 {
            let syntheticW = Double(bounds.width) * 25.4 / 72.0
            let syntheticH = Double(bounds.height) * 25.4 / 72.0
            if abs(syntheticW - Double(raw.width)) <= 1.5 && abs(syntheticH - Double(raw.height)) <= 1.5 {
                return sanitized
            }
        }
        let wantPortrait = sanitized.pixelsHigh > sanitized.pixelsWide
        let rawPortrait = raw.height > raw.width
        let widthMm = Int(((wantPortrait == rawPortrait) ? raw.width : raw.height).rounded())
        let heightMm = Int(((wantPortrait == rawPortrait) ? raw.height : raw.width).rounded())
        return PanelAnnouncement(
            pixelsWide: sanitized.pixelsWide,
            pixelsHigh: sanitized.pixelsHigh,
            scale: sanitized.scale,
            pointsWide: sanitized.pointsWide,
            pointsHigh: sanitized.pointsHigh,
            millimetersWide: sanitized.millimetersWide ?? widthMm,
            millimetersHigh: sanitized.millimetersHigh ?? heightMm
        )
    }

    private func securityChanged(kind: String?, peer: String?) {
        guard kind != "senderMode" else { return }
        admissionPool.cancelAll()
        if kind == "revoked", peerID == peer, let connection { drop(connection, status: "配对已撤销，等待重新配对") }
        if kind == "listenerMode" || kind == "identityReset" {
            generation &+= 1
            listener?.cancel(); listener = nil
            if let connection { drop(connection, status: "安全设置已改变，请重新连接") }
            if running { startListener() }
        }
    }

    func configure(panel: PanelAnnouncement, name: String, maxFps: Int = 60) {
        queue.async { [weak self] in
            guard let self else { return }
            let nextPanel = Self.resolvedPanel(panel)
            let nextMaxFps = AppleVideoPolicy.frameRate(maximum: maxFps)
            let nextServiceName = name.isEmpty ? "DisplayWeave Mac" : name
            let geometryChanged = self.panel != nextPanel || self.maxFps != nextMaxFps
            let nameChanged = self.serviceName != nextServiceName
            self.panel = nextPanel
            self.maxFps = nextMaxFps
            self.serviceName = nextServiceName
            if self.advertiseService, (geometryChanged || nameChanged) {
                self.listener?.service = self.service
            }
            // Announce updated geometry to a live sender without tearing down
            // configuredSize or failing in-flight Annex B frames.
            if geometryChanged, let connection = self.connection {
                self.sendHello(on: connection)
            }
        }
    }

    func setAudioMuted(_ muted: Bool) {
        queue.async { [weak self] in
            self?.audioPlayer.isMuted = muted
        }
    }

    private var service: NWListener.Service {
        var txt = NWTXTRecord()
        txt["id"] = Self.installID
        txt["pv"] = String(WireProtocol.version)
        txt["device"] = "Mac"
        if security.encrypted { txt["security"] = "tls-v1" }
        return NWListener.Service(name: serviceName, type: "_opensidecar._tcp", txtRecord: txt)
    }

    func start(port: UInt16 = 9000, advertiseService: Bool = true) {
        queue.async { [weak self] in
            guard let self, !self.running else { return }
            self.running = true
            self.generation &+= 1
            self.port = port
            self.advertiseService = advertiseService
            self.audioPlayer.isMuted = false
            self.startListener()
            self.armTimer()
        }
    }

    /// Cancel accepting immediately. A final control packet gets at most 250ms;
    /// its late completion can only cancel the captured old connection.
    func stop(announcing: String = "closing", completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion?() }
                return
            }
            self.running = false
            self.generation &+= 1
            self.listener?.cancel()
            self.listener = nil
            self.admissionPool.cancelAll()
            if case .tls(_, let state) = self.security { state.stopPairing() }
            self.timer?.cancel()
            self.timer = nil
            let old = self.connection
            self.connection = nil
            self.peerID = nil
            self.audioPlayer.stop()
            self.resetStream()
            self.publish(connected: false, status: "接收已停止", port: 0)
            var finished = false
            let finish = {
                guard !finished else { return }
                finished = true
                old?.cancel()
                DispatchQueue.main.async { completion?() }
            }
            if let old, old.state == .ready {
                self.send(["type": announcing], on: old) { finish() }
                self.queue.asyncAfter(deadline: .now() + 0.25, execute: finish)
            } else { finish() }
        }
    }

    /// Ending a visible session leaves the listener ready for a new sender.
    func disconnect() {
        queue.async { [weak self] in
            guard let self else { return }
            self.admissionPool.cancelAll()
            if let old = self.connection {
                self.send(["type": "closing"], on: old) { old.cancel() }
                self.queue.asyncAfter(deadline: .now() + 0.25) { old.cancel() }
            }
            self.connection = nil
            self.peerID = nil
            self.audioPlayer.stop()
            self.resetStream()
            self.publish(connected: false, status: "等待发送端连接")
        }
    }

    func retryListening() {
        queue.async { [weak self] in
            guard let self, self.running else { return }
            self.generation &+= 1
            self.listener?.cancel()
            self.listener = nil
            self.admissionPool.cancelAll()
            self.startListener()
        }
    }

    private func startListener() {
        guard running else { return }
        let token = generation
        do {
            security = try securityProvider()
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            let tls: NWProtocolTLS.Options?
            if case .tls(let identity, let state) = security {
                tls = try AppleTLS.options(identity: identity, peerIsServer: false, queue: queue,
                                           acceptedFingerprint: { state.acceptsTLS($0) })
            } else { tls = nil }
            let parameters = NWParameters(tls: tls, tcp: tcp)
            parameters.allowLocalEndpointReuse = true
            parameters.serviceClass = .interactiveVideo
            let active = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            listener = active
            if advertiseService { active.service = service }
            active.newConnectionHandler = { [weak self, weak active] conn in
                guard let self, self.running, self.listener === active,
                      self.connection == nil else { conn.cancel(); return }
                if case .tls(_, let state) = self.security {
                    self.admissionPool.accept(conn, pairing: state) { [weak self, weak active] result in
                        guard let self, self.running, self.generation == token, self.listener === active,
                              self.connection == nil else { conn.cancel(); return }
                        switch result {
                        case .success(let peer): self.adopt(conn, authenticatedPeer: peer)
                        case .failure(let error): self.publish(status: error.localizedDescription)
                        }
                    }
                } else { self.adopt(conn) }
            }
            active.stateUpdateHandler = { [weak self, weak active] state in
                guard let self, self.running, self.listener === active else { return }
                switch state {
                case .ready:
                    self.publish(status: self.connection == nil ? "等待发送端连接" : nil,
                                 port: active?.port?.rawValue ?? 0)
                case .failed(let error):
                    active?.cancel()
                    self.listener = nil
                    self.admissionPool.cancelAll()
                    self.publish(status: "监听失败：\(error.localizedDescription)；正在重试", port: 0)
                    self.queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                        guard let self, self.running, self.generation == token else { return }
                        self.startListener()
                    }
                default: break
                }
            }
            active.start(queue: queue)
        } catch {
            publish(status: "无法监听：\(error.localizedDescription)", port: 0)
            if error is TransportSecurityError { return }
            queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.running, self.generation == token else { return }
                self.startListener()
            }
        }
    }

    private func adopt(_ conn: NWConnection, authenticatedPeer: SecurePeerRecord? = nil) {
        connection?.cancel()
        connection = nil
        peerID = authenticatedPeer?.installID
        resetStream()
        connection = conn
        lastReceived = Date()
        let encrypted = authenticatedPeer != nil
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self, let conn, self.connection === conn else { return }
            switch state {
            case .ready:
                guard !encrypted else { return }
                self.expectFirstVideo()
                self.publish(connected: true, status: "已连接，等待画面")
                self.sendHello(on: conn)
            case .failed, .cancelled:
                self.drop(conn, status: "连接已结束，等待发送端")
            default: break
            }
        }
        DispatchQueue.main.async { [weak self] in self?.encrypted = encrypted }
        if encrypted {
            expectFirstVideo()
            publish(connected: true, status: "已加密连接，等待画面")
            sendHello(on: conn)
        } else { conn.start(queue: queue) }
        receive(on: conn)
    }

    private func drop(_ conn: NWConnection, status: String, announcing: String? = nil) {
        guard connection === conn else { return }
        connection = nil
        peerID = nil
        if let announcing {
            // End a video-less session explicitly so a healthy TCP link does
            // not start an endless reconnect/black-screen cycle. Both callbacks
            // own only the retired socket and have a bounded lifetime.
            send(["type": announcing], on: conn) { conn.cancel() }
            queue.asyncAfter(deadline: .now() + 0.25) { conn.cancel() }
        } else { conn.cancel() }
        resetStream()
        publish(connected: false, status: status)
    }

    func advertisedVideoCapabilities() -> [[String: Any]] {
        let codecs = supportsHEVC ? ["h264", "hevc"] : ["h264"]
        let isPortrait = panel.pixelsHigh > panel.pixelsWide
        let nativeEnvelope = AppleVideoPolicy.nativeHighRefreshEnvelope(
            width: panel.pixelsWide,
            height: panel.pixelsHigh,
            maxFps: maxFps
        )
        let swappedNativeEnvelope = (panel.pixelsWide != panel.pixelsHigh)
            ? AppleVideoPolicy.nativeHighRefreshEnvelope(
                width: panel.pixelsHigh,
                height: panel.pixelsWide,
                maxFps: maxFps
            )
            : nil
        var caps: [[String: Any]] = []
        for codec in codecs {
            let primary4K = isPortrait
                ? (width: Self.maxH264ShortEdge, height: Self.maxH264LongEdge)
                : (width: Self.maxH264LongEdge, height: Self.maxH264ShortEdge)
            let secondary4K = isPortrait
                ? (width: Self.maxH264LongEdge, height: Self.maxH264ShortEdge)
                : (width: Self.maxH264ShortEdge, height: Self.maxH264LongEdge)
            caps.append([
                "codec": codec,
                "maxWidth": primary4K.width,
                "maxHeight": primary4K.height,
                "maxFrameRate": maxFps,
                "maxPixelsPerSecond": AppleVideoPolicy.maxPixelsPerSecond
            ])
            caps.append([
                "codec": codec,
                "maxWidth": secondary4K.width,
                "maxHeight": secondary4K.height,
                "maxFrameRate": maxFps,
                "maxPixelsPerSecond": AppleVideoPolicy.maxPixelsPerSecond
            ])
            if let nativeEnvelope {
                caps.append(nativeEnvelope.capability(codec: codec))
            }
            if let swappedNativeEnvelope {
                caps.append(swappedNativeEnvelope.capability(codec: codec))
            }
        }
        if supportsHEVC {
            let fps5K = min(maxFps, Self.maxHEVC5KFrameRate)
            let primary5K = isPortrait
                ? (width: Self.maxHEVC5KShortEdge, height: Self.maxHEVC5KLongEdge)
                : (width: Self.maxHEVC5KLongEdge, height: Self.maxHEVC5KShortEdge)
            let secondary5K = isPortrait
                ? (width: Self.maxHEVC5KLongEdge, height: Self.maxHEVC5KShortEdge)
                : (width: Self.maxHEVC5KShortEdge, height: Self.maxHEVC5KLongEdge)
            caps.append([
                "codec": "hevc",
                "maxWidth": primary5K.width,
                "maxHeight": primary5K.height,
                "maxFrameRate": fps5K,
                "maxPixelsPerSecond": Self.maxHEVC5KPixelsPerSecond
            ])
            caps.append([
                "codec": "hevc",
                "maxWidth": secondary5K.width,
                "maxHeight": secondary5K.height,
                "maxFrameRate": fps5K,
                "maxPixelsPerSecond": Self.maxHEVC5KPixelsPerSecond
            ])
        }
        return caps
    }

    func acceptsStreamConfiguration(_ obj: [String: Any]) -> AppleVideoConfiguration? {
        let maxEdge = supportsHEVC ? Self.maxHEVC5KLongEdge : Self.maxH264LongEdge
        let nativeEnvelope = AppleVideoPolicy.nativeHighRefreshEnvelope(
            width: panel.pixelsWide,
            height: panel.pixelsHigh,
            maxFps: maxFps
        )
        let swappedNativeEnvelope = (panel.pixelsWide != panel.pixelsHigh)
            ? AppleVideoPolicy.nativeHighRefreshEnvelope(
                width: panel.pixelsHigh,
                height: panel.pixelsWide,
                maxFps: maxFps
            )
            : nil
        let parsed = AppleVideoConfiguration(
            obj,
            maxWidth: maxEdge,
            maxHeight: maxEdge,
            maxFps: maxFps,
            nativeEnvelope: nativeEnvelope,
            allowHEVC5K: supportsHEVC
        ) ?? AppleVideoConfiguration(
            obj,
            maxWidth: maxEdge,
            maxHeight: maxEdge,
            maxFps: maxFps,
            nativeEnvelope: swappedNativeEnvelope,
            allowHEVC5K: supportsHEVC
        )
        guard let config = parsed,
              fitsHardwareEnvelope(
                width: Int32(config.width),
                height: Int32(config.height),
                codec: config.codec
              ) else {
            return nil
        }
        return config
    }

    private func fitsHardwareEnvelope(width: Int32, height: Int32, codec: ReceiverVideoCodec) -> Bool {
        guard width > 0, height > 0 else { return false }
        let w = Int(width)
        let h = Int(height)
        let maxLong = (codec == .hevc && supportsHEVC) ? Self.maxHEVC5KLongEdge : Self.maxH264LongEdge
        let maxShort = (codec == .hevc && supportsHEVC) ? Self.maxHEVC5KShortEdge : Self.maxH264ShortEdge
        return (w <= maxLong && h <= maxShort) || (w <= maxShort && h <= maxLong)
    }

    private func sendHello(on conn: NWConnection) {
        let codecs = supportsHEVC ? ["h264", "hevc"] : ["h264"]
        let caps = advertisedVideoCapabilities()
        var capabilities = [
            AppleVideoPolicy.udpMediaCapability,
            AppleVideoPolicy.udpCursorCapability,
            AppleVideoPolicy.udpAudioCapability,
            AppleVideoPolicy.tcpAudioCapability,
            AppleVideoPolicy.audioOpusCapability,
            AppleVideoPolicy.displayP3Capability
        ]
        if supportsHEVC {
            capabilities.append(AppleVideoPolicy.hevc5kCapability)
        }
        let maxEdge = supportsHEVC ? Self.maxHEVC5KLongEdge : Self.maxH264LongEdge
        send(["type": "hello", "device": "Mac", "id": Self.installID,
              "pixelsWide": panel.pixelsWide, "pixelsHigh": panel.pixelsHigh, "scale": panel.scale,
              "panel": panel.json, "pv": WireProtocol.version,
              "supportedCodecs": codecs, "preferredCodec": supportsHEVC ? "hevc" : "h264",
              "refreshRate": maxFps, "maxFps": maxFps, "displayMaxFrameRate": maxFps,
              "maxEncodeWide": maxEdge, "maxEncodeHigh": maxEdge,
              "videoCaps": caps,
              "capabilities": capabilities,
              "udpMediaV1": true,
              "inputCaps": peerID != nil ? [DesktopInputProtocol.capability] : [],
              "transport": "lan"], on: conn)
    }

    @MainActor func setInputForwarding(_ enabled: Bool) {
        if !enabled { releaseDesktopInput() }
        inputForwarding = enabled
    }

    @MainActor func releaseDesktopInput() {
        sendDesktopInput(["kind": "releaseAll", "modifiers": 0])
    }

    /// Reserve before dispatch so high-frequency pointer events cannot create
    /// an unbounded queue of closures. Old projections cannot use a new socket.
    @MainActor func sendDesktopInput(_ fields: [String: Any]) {
        guard inputForwarding, let grant = inputGrant else { return }
        switch inputBudget.reserve(expectedGeneration: inputGeneration) {
        case .unavailable: return
        case .overflow(let epoch):
            queue.async { [weak self] in
                guard let self, self.inputBudget.generation == epoch, let conn = self.connection else { return }
                self.drop(conn, status: "键鼠发送队列已满，请重新连接")
            }
        case .accepted(let ticket):
            var object = fields
            object["type"] = "desktopInput"; object["inputSession"] = grant; object["sequence"] = ticket.sequence
            guard let data = try? JSONSerialization.data(withJSONObject: object), DesktopInputEvent.decode(data) != nil else {
                inputBudget.complete(ticket); return
            }
            let budget = inputBudget
            queue.async { [weak self] in
                guard let self, budget.generation == ticket.generation, self.wireInputGrant == grant,
                      self.peerID != nil, let conn = self.connection else { budget.complete(ticket); return }
                conn.send(content: ReceiverFrameDecoder.frame(data), completion: .contentProcessed { [weak self, weak conn] error in
                    budget.complete(ticket)
                    if error != nil, let self, let conn, self.connection === conn {
                        self.drop(conn, status: "键鼠发送失败，请重新连接")
                    }
                })
            }
        }
    }

    private func configureDesktopInput(_ object: [String: Any]) {
        let candidate = object["inputSession"] as? String
        let valid = peerID != nil && (object["inputCaps"] as? [String])?.contains(DesktopInputProtocol.capability) == true
            && candidate.flatMap(UUID.init(uuidString:)) != nil
        let grant = valid ? candidate : nil
        if grant == wireInputGrant, grant != nil { return }
        wireInputGrant = grant
        let epoch = inputBudget.reset(accepting: grant != nil)
        let labels = ["ready": "已获授权；聚焦接收画面后可操作", "secureRequired": "请先配对并使用加密连接",
                      "consentRequired": "请在发送端设置中允许 Mac 键鼠回传", "accessibilityRequired": "请在发送端授予辅助功能权限",
                      "targetPending": "等待发送端准备显示器"]
        let label = grant != nil ? labels["ready"]! : labels[object["inputStatus"] as? String ?? ""] ?? "发送端未授权键鼠回传，请检查双方设置"
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.inputGeneration = epoch; self.inputGrant = grant; self.inputStatus = label
        }
    }

    private func send(_ object: [String: Any], on conn: NWConnection? = nil,
                      completion: (() -> Void)? = nil) {
        guard let conn = conn ?? connection,
              let data = try? JSONSerialization.data(withJSONObject: object) else { completion?(); return }
        conn.send(content: ReceiverFrameDecoder.frame(data), completion: .contentProcessed { _ in completion?() })
    }

    private func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, ended, error in
            guard let self, self.running, self.connection === conn else { return }
            if let data, !data.isEmpty {
                self.lastReceived = Date()
                let receivedAtUptime = self.monotonicTime()
                do {
                    for frame in try self.decoder.append(data) {
                        guard self.connection === conn else { return }
                        self.handle(frame, on: conn, receivedAtUptime: receivedAtUptime)
                    }
                } catch {
                    self.drop(conn, status: "已拒绝无效数据，等待发送端")
                    return
                }
            }
            guard self.connection === conn else { return }
            if ended || error != nil {
                self.drop(conn, status: "连接已结束，等待发送端")
            } else { self.receive(on: conn) }
        }
    }

    private func armTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, let conn = self.connection else { return }
            if Date().timeIntervalSince(self.lastReceived) > 8 {
                self.drop(conn, status: "连接超时，等待发送端")
                return
            }
            if let deadline = self.fallbackDeadline, Date() >= deadline {
                self.drop(conn, status: "编码回退超时，请重新连接"); return
            }
            if self.videoRenderer.status == .failed {
                self.failVideo(on: conn)
                guard self.connection === conn else { return }
            }
            if let deadline = self.firstVideoDeadline, self.monotonicTime() >= deadline {
                self.diagnostic?("FIRST-VIDEO-TIMEOUT codec=\(self.videoCodec.rawValue) waitingForKeyframe=\(self.waitingForKeyframe)")
                self.drop(conn, status: "15 秒内未收到可用首帧。请检查发送端屏幕录制权限、编码设置和日志后重新连接。", announcing: "closing")
                return
            }
            self.send(["type": "ping", "t": Date().timeIntervalSince1970 * 1000])
            let elapsed = max(0.001, Date().timeIntervalSince(self.statsStart))
            let renderedFps = Int((Double(self.sampleCount) / elapsed).rounded())
            self.queueRenderedFps = renderedFps
            self.sampleCount = 0
            self.statsStart = Date()
            self.udpMediaSession?.updateReceiverTelemetry(
                rttMs: self.lastRttMs,
                decodeQueueMs: self.videoRenderer.isReadyForMoreMediaData ? 0 : 12,
                renderFps: self.queueRenderedFps
            )
            DispatchQueue.main.async { [weak self] in self?.fps = renderedFps }
            self.reportDiagnostics()
        }
        timer.resume()
        self.timer = timer
    }

    private func handle(_ data: Data, on conn: NWConnection, receivedAtUptime: TimeInterval? = nil) {
        if data.first == UInt8(ascii: "{"), !data.contains(0) {
            guard data.count <= 256 * 1024,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                drop(conn, status: "控制消息无效，等待发送端"); return
            }
            switch obj["type"] as? String {
            case "inputConfig":
                configureDesktopInput(obj)
            case "ping":
                send(["type": "pong", "t": obj["t"] ?? 0, "mt": Date().timeIntervalSince1970 * 1000])
            case "pong":
                if let sentMs = (obj["t"] as? NSNumber)?.doubleValue, sentMs.isFinite {
                    let nowMs = Date().timeIntervalSince1970 * 1000
                    let rtt = nowMs - sentMs
                    if rtt.isFinite, rtt >= 0, rtt <= 10_000 {
                        lastRttMs = rtt
                    }
                }
            case "streamConfig":
                guard let config = acceptsStreamConfiguration(obj) else {
                    drop(conn, status: "发送配置超出接收能力，请降低画质"); return
                }
                let codec = config.codec
                let size = CGSize(width: config.width, height: config.height)
                if codec == .hevc, hevcFailureSent {
                    drop(conn, status: "HEVC 回退失败，请选择 H.264 后重连"); return
                }
                if let explicitVer = (obj["configVersion"] as? NSNumber)?.int64Value, explicitVer > 0 {
                    activeConfigVersion = explicitVer
                } else {
                    activeConfigVersion &+= 1
                }
                if videoCodec != codec || configuredSize != size {
                    videoCodec = codec
                    DispatchQueue.main.async { [weak self] in
                        self?.codecLabel = codec == .hevc ? "HEVC" : "H.264"
                    }
                    resetVideo()
                    expectFirstVideo()
                }
                configuredSize = size
                if codec == .hevc, !supportsHEVC { failVideo(on: conn); return }
                fallbackDeadline = nil
                if pendingKeyframeAfterStreamConfig {
                    pendingKeyframeAfterStreamConfig = false
                    lastKeyframeRequest = .distantPast
                    requestKeyframe()
                }
            case "cursor":
                let x = obj["x"] as? Double ?? 0, y = obj["y"] as? Double ?? 0
                guard x.isFinite, y.isFinite, x >= 0, x <= 1, y >= 0, y <= 1 else { return }
                if let rawSeq = obj["s"] {
                    guard let signedSeq = (rawSeq as? NSNumber)?.int64Value,
                          signedSeq > 0,
                          let seq = UInt64(exactly: signedSeq),
                          seq > lastCursorSequence else { return }
                    lastCursorSequence = seq
                }
                let visible = (obj["v"] as? Int ?? 0) == 1
                if let token = cursorDelivery.offer((x, y, visible)) { deliverCursor(token) }
            case "cursorImg", "cursorImage":
                handleCursorImage(obj)
            case "udpMediaConfig":
                configureUDPMedia(obj, on: conn)
            case TCPAudioFrameMessage.messageType:
                guard data.count <= TCPAudioFrameMessage.maxControlBytes,
                      let audio = try? TCPAudioFrameMessage.decode(jsonObject: obj, rawByteCount: data.count) else {
                    return
                }
                handleIncomingAudio(audio, isUDP: false)
            default: break
            }
            return
        }
        handleAnnexB(data, on: conn, receivedAtUptime: receivedAtUptime)
    }

    private func handleCursorImage(_ obj: [String: Any]) {
        guard let cursor = ReceiverCursorImage.decode(obj) else { return }
        let epoch = cursorDelivery.generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.cursorDelivery.generation == epoch else { return }
            self.onCursorImage?(cursor.image, cursor.anchor, cursor.normalizedSize)
        }
    }

    private func configureUDPMedia(_ obj: [String: Any], on conn: NWConnection) {
        guard let config = UDPMediaConfigMessage(jsonObject: obj) else { return }
        if config.sessionEpoch < lastUdpMediaEpoch { return }
        if config.sessionEpoch == lastUdpMediaEpoch, let activeSession = udpMediaSession {
            send([
                "type": "udpMediaReady",
                "sessionEpoch": config.sessionEpoch,
                "udpPort": Int(activeSession.localPort),
            ], on: conn)
            return
        }
        let currentGen = cursorDelivery.generation
        let senderHost = UDPEndpointResolver.hostString(from: conn.currentPath?.remoteEndpoint)
            ?? UDPEndpointResolver.hostString(from: conn.endpoint)
        guard let session = UDPMediaReceiverSession(
            config: config,
            generation: currentGen,
            senderHost: senderHost
        ) else { return }
        udpMediaSession?.stop()
        udpMediaSession = nil
        lastUdpMediaEpoch = config.sessionEpoch
        audioPlayer.updateVideoPipelineDelay(udpJitterActive: true, explicitDelayMs: nil)
        session.onFrameReady = { [weak self, weak conn] gen, frame in
            guard let self else { return }
            let receivedAtUptime = self.monotonicTime()
            self.queue.async { [weak self, weak conn] in
                guard let self,
                      self.running,
                      let conn,
                      self.connection === conn,
                      self.cursorDelivery.generation == gen else { return }
                self.lastReceived = Date()
                guard self.configuredSize != nil else {
                    self.pendingKeyframeAfterStreamConfig = true
                    return
                }
                if self.activeConfigVersion > 0,
                   frame.configVersion > 0,
                   frame.configVersion != self.activeConfigVersion {
                    if frame.configVersion > self.activeConfigVersion {
                        self.pendingKeyframeAfterStreamConfig = true
                    } else if self.waitingForKeyframe {
                        self.requestKeyframe()
                    }
                    return
                }
                self.handleAnnexB(
                    frame.annexB,
                    on: conn,
                    receivedAtUptime: receivedAtUptime,
                    isUDP: true,
                    captureTimestampMs: frame.captureTimestampMs
                )
                self.udpMediaSession?.updateReceiverTelemetry(
                    rttMs: self.lastRttMs,
                    decodeQueueMs: self.videoRenderer.isReadyForMoreMediaData ? 0 : 12,
                    renderFps: self.queueRenderedFps
                )
            }
        }
        session.onKeyframeNeeded = { [weak self, weak conn] gen, _ in
            guard let self else { return }
            self.queue.async { [weak self, weak conn] in
                guard let self,
                      self.running,
                      let conn,
                      self.connection === conn,
                      self.cursorDelivery.generation == gen else { return }
                self.requestKeyframe()
            }
        }
        session.onCursor = { [weak self, weak conn] gen, cursor in
            guard let self else { return }
            self.queue.async { [weak self, weak conn] in
                guard let self,
                      self.running,
                      let conn,
                      self.connection === conn,
                      self.cursorDelivery.generation == gen,
                      cursor.isValid,
                      cursor.sequence > self.lastCursorSequence else { return }
                self.lastReceived = Date()
                self.lastCursorSequence = cursor.sequence
                let point = (Double(cursor.normalizedX), Double(cursor.normalizedY), cursor.visible)
                if let token = self.cursorDelivery.offer(point) {
                    self.deliverCursor(token)
                }
            }
        }
        session.onAudio = { [weak self, weak conn] gen, audio in
            guard let self else { return }
            self.queue.async { [weak self, weak conn] in
                guard let self,
                      self.running,
                      let conn,
                      self.connection === conn,
                      self.cursorDelivery.generation == gen else { return }
                self.handleIncomingAudio(audio, isUDP: true)
            }
        }
        udpMediaSession = session
        session.updateReceiverTelemetry(
            rttMs: lastRttMs,
            decodeQueueMs: videoRenderer.isReadyForMoreMediaData ? 0 : 12,
            renderFps: queueRenderedFps
        )
        send([
            "type": "udpMediaReady",
            "sessionEpoch": config.sessionEpoch,
            "udpPort": Int(session.localPort),
        ], on: conn)
    }

    private func deliverCursor(_ token: LatestValueRelay<(x: Double, y: Double, visible: Bool)>.Token) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let cursor = self.cursorDelivery.take(token) else { return }
            self.onCursor?(cursor.x, cursor.y, cursor.visible)
            if let next = self.cursorDelivery.complete(token) { self.deliverCursor(next) }
        }
    }

    private func reportDiagnostics() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - diagnosticsStart
        guard elapsed >= 2 else { return }
        let cursor = cursorDelivery.takeMetrics()
        // Optional control type: older peers ignore it. Do not call enqueue FPS
        // "rendered FPS", or use unrelated machine clocks for cursor latency.
        let object: [String: Any] = ["type": "macReceiverStats",
            "videoEnqueuedFps": Double(enqueuedFrames) / elapsed,
            "backpressureFlushes": backpressureFlushes,
            "backpressureToleratedFrames": backpressureToleratedFrames,
            "waitingForKeyframe": waitingForKeyframe,
            "cursorReceived": cursor.offered, "cursorApplied": cursor.completed,
            "cursorCoalesced": cursor.coalesced, "cursorDispatchMaxMs": cursor.maxWaitMs]
        send(object)
        if let data = try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys),
           let text = String(data: data, encoding: .utf8) { diagnostic?("MAC-RECEIVER-STATS \(text)") }
        diagnosticsStart = now
        enqueuedFrames = 0
        backpressureFlushes = 0
        backpressureToleratedFrames = 0
    }

    private func handleIncomingAudio(_ audio: UDPMediaAudioPayload, isUDP: Bool) {
        guard audio.isValid,
              audio.sampleRate == 48_000,
              (1...2).contains(audio.channels),
              (audio.formatFlags == UDPMediaAudioPayload.formatPCM16LE
               || audio.formatFlags == UDPMediaAudioPayload.formatOpus) else { return }
        if let prev = lastAudioSequence,
           !UDPMediaHeader.isFrameIdNewer(audio.audioSeq, than: prev) {
            return
        }
        if !isUDP, udpMediaSession == nil {
            audioPlayer.updateVideoPipelineDelay(udpJitterActive: false, explicitDelayMs: nil)
        }
        lastAudioSequence = audio.audioSeq
        lastReceived = Date()
        audioPlayer.enqueueEncodedAudio(
            formatFlags: audio.formatFlags,
            payload: audio.pcmBytes,
            sampleRate: Int(audio.sampleRate),
            channels: Int(audio.channels),
            captureTimestampMs: audio.captureTimestampMs,
            arrivalMonoMs: monotonicTime() * 1_000.0
        )
    }

    private func handleAnnexB(_ data: Data,
                              on conn: NWConnection,
                              receivedAtUptime: TimeInterval? = nil,
                              isUDP: Bool = false,
                              captureTimestampMs: Int64? = nil) {
        guard fallbackDeadline == nil else { return }
        let packet: ReceiverVideoBitstream.Packet
        do { packet = try bitstream.parse(data) }
        catch { failVideo(on: conn); return }
        if packet.formatChanged { waitingForKeyframe = true }
        guard let format = packet.format else { requestKeyframe(); return }
        if packet.formatChanged {
            let dims = CMVideoFormatDescriptionGetDimensions(format)
            let size = CGSize(width: Int(dims.width), height: Int(dims.height))
            let fitsEnvelope = fitsHardwareEnvelope(width: dims.width, height: dims.height, codec: videoCodec)
            let matchesConfigured = configuredSize == nil
                || configuredSize == size
                || (fitsEnvelope && configuredSize.map { CGSize(width: $0.height, height: $0.width) == size } == true)
            if !fitsEnvelope || !matchesConfigured {
                if isUDP && fitsEnvelope {
                    bitstream = ReceiverVideoBitstream(codec: videoCodec)
                    waitingForKeyframe = true
                    requestKeyframe()
                    return
                }
                drop(conn, status: "视频尺寸与配置不符，请重新连接")
                return
            }
            if configuredSize != nil && configuredSize != size {
                configuredSize = size
            }
            videoRenderer.flush(removingDisplayedImage: true)
            videoBackpressure = ReceiverVideoBackpressurePolicy()
        }
        guard !packet.slices.isEmpty else { return }
        if videoRenderer.status == .failed {
            failVideo(on: conn); return
        }
        if waitingForKeyframe && !packet.keyframe { requestKeyframe(); return }
        if let receivedAtUptime,
           ReceiverFrameAgePolicy.isExpired(
               receivedAtUptime: receivedAtUptime,
               nowUptime: monotonicTime(),
               isKeyframe: packet.keyframe
           ) {
            waitingForKeyframe = true
            requestKeyframe()
            return
        }
        let isReady = videoRenderer.isReadyForMoreMediaData
        switch videoBackpressure.action(isReady: isReady, now: monotonicTime()) {
        case .enqueue:
            if !isReady { backpressureToleratedFrames += 1 }
        case .flushAndWait:
            backpressureFlushes += 1
            videoRenderer.flush(removingDisplayedImage: false)
            waitingForKeyframe = true
            requestKeyframe()
            return
        case .wait:
            requestKeyframe()
            return
        }
        guard enqueue(packet.slices, format: format) else { requestKeyframe(); return }
        if videoRenderer.status == .failed { failVideo(on: conn); return }
        if !hasVideoFrame || packet.formatChanged {
            let dims = CMVideoFormatDescriptionGetDimensions(format)
            let size = CGSize(width: Int(dims.width), height: Int(dims.height))
            DispatchQueue.main.async { [weak self] in self?.videoSize = size }
            publish(status: "正在接收 \(dims.width) × \(dims.height) · \(videoCodec == .hevc ? "HEVC" : "H.264")")
        }
        waitingForKeyframe = false
        hasVideoFrame = true
        firstVideoDeadline = nil
        audioPlayer.updateVideoPipelineDelay(udpJitterActive: isUDP, explicitDelayMs: nil)
        let capMs: Int64 = captureTimestampMs ?? {
            guard let metaData = packet.metadata,
                  metaData.count <= 1_024,
                  let metaObj = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any],
                  let capNum = metaObj["cap"] as? NSNumber else {
                return 0
            }
            return capNum.int64Value
        }()
        if capMs > 0 {
            audioPlayer.recordVideoRender(
                captureTimestampMs: capMs,
                renderMonoMs: monotonicTime() * 1_000.0
            )
        }
    }

    private func failVideo(on conn: NWConnection) {
        guard videoCodec == .hevc else {
            drop(conn, status: "视频解码失败，请重新连接"); return
        }
        guard !hevcFailureSent else { return }
        hevcFailureSent = true
        resetVideo()
        expectFirstVideo()
        fallbackDeadline = Date().addingTimeInterval(3)
        send(["type": "codecFailure", "codec": "hevc", "message": "Mac HEVC decode failed"], on: conn)
        publish(status: "HEVC 不可用，正在回退 H.264")
    }

    private func requestKeyframe() {
        guard Date().timeIntervalSince(lastKeyframeRequest) > 0.5 else { return }
        lastKeyframeRequest = Date()
        send(["type": "kf"])
    }

    private func enqueue(_ nalus: [Data], format: CMVideoFormatDescription) -> Bool {
        var avcc = Data()
        for nalu in nalus { avcc.append(ReceiverFrameDecoder.frame(nalu)) }
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: avcc.count, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: avcc.count, flags: 0, blockBufferOut: &block) == noErr,
              let block else { return false }
        let result = avcc.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: avcc.count)
        }
        guard result == noErr else { return false }
        var sample: CMSampleBuffer?
        var size = avcc.count
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block,
            formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr,
              let sample else { return false }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                  Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        videoRenderer.enqueue(sample)
        sampleCount += 1
        enqueuedFrames += 1
        return true
    }

    private func expectFirstVideo() {
        // Heartbeats, parameter sets and repeated configuration must never
        // restart an unfulfilled deadline. Once a frame is submitted, a static
        // desktop may legitimately emit no more frames until it changes.
        guard !hasVideoFrame, firstVideoDeadline == nil else { return }
        firstVideoDeadline = monotonicTime() + 15
        publish(status: peerID == nil ? "已连接，等待画面" : "已加密连接，等待画面")
    }

    private func resetVideo() {
        hasVideoFrame = false
        videoBackpressure = ReceiverVideoBackpressurePolicy()
        bitstream = ReceiverVideoBitstream(codec: videoCodec)
        configuredSize = nil
        waitingForKeyframe = true
        lastKeyframeRequest = .distantPast
        videoRenderer.flush(removingDisplayedImage: true)
        DispatchQueue.main.async { [weak self] in self?.videoSize = .zero }
    }

    private func resetStream() {
        udpMediaSession?.stop()
        udpMediaSession = nil
        audioPlayer.stop()
        cursorDelivery.reset()
        diagnosticsStart = ProcessInfo.processInfo.systemUptime
        enqueuedFrames = 0
        backpressureFlushes = 0
        backpressureToleratedFrames = 0
        wireInputGrant = nil
        let epoch = inputBudget.reset(accepting: false)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.inputGeneration = epoch; self.inputGrant = nil; self.inputStatus = "请连接支持键鼠回传的加密发送端"
        }
        decoder = ReceiverFrameDecoder()
        videoCodec = .h264
        activeConfigVersion = 0
        pendingKeyframeAfterStreamConfig = false
        lastUdpMediaEpoch = 0
        hevcFailureSent = false
        fallbackDeadline = nil
        firstVideoDeadline = nil
        lastRttMs = 0
        resetVideo()
        lastCursorSequence = 0
        lastAudioSequence = nil
        sampleCount = 0
        queueRenderedFps = 0
        statsStart = Date()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.fps = 0; self.codecLabel = "H.264"; self.encrypted = false; self.onReset?(); self.onCursor?(0, 0, false)
        }
    }

    private func publish(connected: Bool? = nil, status: String? = nil, port: UInt16? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let connected { self.connected = connected }
            if let status { self.status = status }
            if let port { self.listeningPort = port }
        }
    }
}
