// Adapted from peetzweg/opendisplay Shared/StreamReceiver.swift (GPL-3.0).
// Source: b9eec1f232fb5ea571c87e8392379a84f47b237f.
// DisplayWeave: Mac H.264/HEVC, bounded frames, exclusive sessions, deterministic
// shutdown, and queue-owned lifecycle. Upstream Annex B/CoreMedia path retained.
import Foundation
import Combine
import Network
import AVFoundation
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
    private let monotonicTime: () -> TimeInterval
    var onReset: (() -> Void)?
    var onCursor: ((Double, Double, Bool) -> Void)?
    var onCursorImage: ((CGImage, CGPoint, CGSize) -> Void)?

    static let installID = TransportInstallIdentity.value

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
    private var panel = PanelAnnouncement(pixelsWide: 1920, pixelsHigh: 1080, scale: 1,
                                           pointsWide: 1920, pointsHigh: 1080)
    private var serviceName = "DisplayWeave Mac"
    private var maxFps = 60
    private let supportsHEVC: Bool
    private var videoCodec: ReceiverVideoCodec = .h264
    private var bitstream = ReceiverVideoBitstream(codec: .h264)
    private var configuredSize: CGSize?
    private var hevcFailureSent = false
    private var fallbackDeadline: Date?
    private var firstVideoDeadline: TimeInterval?
    private var hasVideoFrame = false
    private var waitingForKeyframe = true
    private var lastKeyframeRequest = Date.distantPast
    private var lastReceived = Date()
    private var sampleCount = 0
    private var statsStart = Date()
    private var lastCursorSequence: UInt64 = 0

    init(displayLayer: AVSampleBufferDisplayLayer = AVSampleBufferDisplayLayer(),
         hardwareHEVCDecode: Bool? = nil,
         inputBudget: InputSendBudget = InputSendBudget(),
         diagnostic: ((String) -> Void)? = nil,
         videoRenderer: (any MacVideoRendering)? = nil,
         monotonicTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         securityProvider: @escaping () throws -> AppleReceiverSecurity = { try .live(localID: StreamReceiver.installID) }) {
        self.diagnostic = diagnostic
        self.inputBudget = inputBudget
        self.securityProvider = securityProvider
        self.supportsHEVC = hardwareHEVCDecode ?? VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        self.displayLayer = displayLayer
        self.videoRenderer = videoRenderer ?? MacSampleBufferVideoRenderer(renderer: displayLayer.sampleBufferRenderer)
        self.monotonicTime = monotonicTime
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
        if kind == "revoked", peerID == peer, let connection { drop(connection, status: "配对已撤销，等待重新配对") }
        if kind == "listenerMode" || kind == "identityReset" {
            generation &+= 1
            listener?.cancel(); listener = nil
            if let connection { drop(connection, status: "安全设置已改变，请重新连接") }
            if running { startListener() }
        }
    }

    func configure(panel: PanelAnnouncement, name: String, maxFps: Int = 60) {
        queue.async {
            self.panel = panel
            self.maxFps = AppleVideoPolicy.frameRate(maximum: maxFps)
            self.serviceName = name.isEmpty ? "DisplayWeave Mac" : name
            if self.advertiseService { self.listener?.service = self.service }
            if let connection = self.connection { self.sendHello(on: connection) }
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
        queue.async {
            guard !self.running else { return }
            self.running = true
            self.generation &+= 1
            self.port = port
            self.advertiseService = advertiseService
            self.startListener()
            self.armTimer()
        }
    }

    /// Cancel accepting immediately. A final control packet gets at most 250ms;
    /// its late completion can only cancel the captured old connection.
    func stop(announcing: String = "closing", completion: (() -> Void)? = nil) {
        queue.async {
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
        queue.async {
            self.admissionPool.cancelAll()
            if let old = self.connection {
                self.send(["type": "closing"], on: old) { old.cancel() }
                self.queue.asyncAfter(deadline: .now() + 0.25) { old.cancel() }
            }
            self.connection = nil
            self.peerID = nil
            self.resetStream()
            self.publish(connected: false, status: "等待发送端连接")
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
        connection = conn
        peerID = authenticatedPeer?.installID
        resetStream()
        lastReceived = Date()
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self, let conn, self.connection === conn else { return }
            switch state {
            case .ready:
                self.expectFirstVideo()
                self.publish(connected: true, status: "已连接，等待画面")
                self.sendHello(on: conn)
            case .failed, .cancelled:
                self.drop(conn, status: "连接已结束，等待发送端")
            default: break
            }
        }
        let encrypted = authenticatedPeer != nil
        DispatchQueue.main.async { self.encrypted = encrypted }
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

    private var limits: (width: Int, height: Int) {
        panel.pixelsHigh > panel.pixelsWide ? (2304, 4096) : (4096, 2304)
    }

    private func sendHello(on conn: NWConnection) {
        let codecs = supportsHEVC ? ["h264", "hevc"] : ["h264"]
        let caps: [[String: Any]] = codecs.map {
            ["codec": $0, "maxWidth": limits.width, "maxHeight": limits.height, "maxFrameRate": maxFps,
             "maxPixelsPerSecond": AppleVideoPolicy.maxPixelsPerSecond]
        }
        send(["type": "hello", "device": "Mac", "id": Self.installID,
              "pixelsWide": panel.pixelsWide, "pixelsHigh": panel.pixelsHigh, "scale": panel.scale,
              "panel": panel.json, "pv": WireProtocol.version,
              "supportedCodecs": codecs, "preferredCodec": supportsHEVC ? "hevc" : "h264",
              "refreshRate": maxFps, "maxFps": maxFps, "displayMaxFrameRate": maxFps,
              "maxEncodeWide": limits.width, "maxEncodeHigh": limits.height,
              "videoCaps": caps,
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
            queue.async {
                guard self.inputBudget.generation == epoch, let conn = self.connection else { return }
                self.drop(conn, status: "键鼠发送队列已满，请重新连接")
            }
        case .accepted(let ticket):
            var object = fields
            object["type"] = "desktopInput"; object["inputSession"] = grant; object["sequence"] = ticket.sequence
            guard let data = try? JSONSerialization.data(withJSONObject: object), DesktopInputEvent.decode(data) != nil else {
                inputBudget.complete(ticket); return
            }
            queue.async {
                guard self.inputBudget.generation == ticket.generation, self.wireInputGrant == grant,
                      self.peerID != nil, let conn = self.connection else { self.inputBudget.complete(ticket); return }
                conn.send(content: ReceiverFrameDecoder.frame(data), completion: .contentProcessed { error in
                    self.inputBudget.complete(ticket)
                    if error != nil, self.connection === conn { self.drop(conn, status: "键鼠发送失败，请重新连接") }
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
        DispatchQueue.main.async {
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
                do {
                    for frame in try self.decoder.append(data) {
                        guard self.connection === conn else { return }
                        self.handle(frame, on: conn)
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
            let fps = Int((Double(self.sampleCount) / elapsed).rounded())
            self.sampleCount = 0
            self.statsStart = Date()
            DispatchQueue.main.async { self.fps = fps }
            self.reportDiagnostics()
        }
        timer.resume()
        self.timer = timer
    }

    private func handle(_ data: Data, on conn: NWConnection) {
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
            case "streamConfig":
                guard let config = AppleVideoConfiguration(obj, maxWidth: limits.width,
                        maxHeight: limits.height, maxFps: maxFps) else {
                    drop(conn, status: "发送配置超出接收能力，请降低画质"); return
                }
                let codec = config.codec
                let size = CGSize(width: config.width, height: config.height)
                if codec == .hevc, hevcFailureSent {
                    drop(conn, status: "HEVC 回退失败，请选择 H.264 后重连"); return
                }
                if videoCodec != codec || configuredSize != size {
                    videoCodec = codec
                    DispatchQueue.main.async { self.codecLabel = codec == .hevc ? "HEVC" : "H.264" }
                    resetVideo()
                    expectFirstVideo()
                }
                configuredSize = size
                if codec == .hevc, !supportsHEVC { failVideo(on: conn); return }
                fallbackDeadline = nil
            case "cursor":
                if let seq = (obj["s"] as? NSNumber)?.uint64Value {
                    guard seq > lastCursorSequence else { return }; lastCursorSequence = seq
                }
                let x = obj["x"] as? Double ?? 0, y = obj["y"] as? Double ?? 0
                guard x.isFinite, y.isFinite else { return }
                let visible = (obj["v"] as? Int ?? 0) == 1
                if let token = cursorDelivery.offer((x, y, visible)) { deliverCursor(token) }
            case "cursorImg", "cursorImage":
                handleCursorImage(obj)
            default: break
            }
            return
        }
        handleAnnexB(data, on: conn)
    }

    private func handleCursorImage(_ obj: [String: Any]) {
        guard let cursor = ReceiverCursorImage.decode(obj) else { return }
        let epoch = cursorDelivery.generation
        DispatchQueue.main.async {
            guard self.cursorDelivery.generation == epoch else { return }
            self.onCursorImage?(cursor.image, cursor.anchor, cursor.normalizedSize)
        }
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

    private func handleAnnexB(_ data: Data, on conn: NWConnection) {
        guard fallbackDeadline == nil else { return }
        let packet: ReceiverVideoBitstream.Packet
        do { packet = try bitstream.parse(data) }
        catch { failVideo(on: conn); return }
        if packet.formatChanged { waitingForKeyframe = true }
        guard let format = packet.format else { requestKeyframe(); return }
        if packet.formatChanged {
            let dims = CMVideoFormatDescriptionGetDimensions(format)
            let size = CGSize(width: Int(dims.width), height: Int(dims.height))
            guard dims.width > 0, dims.height > 0, dims.width <= limits.width, dims.height <= limits.height,
                  configuredSize == nil || configuredSize == size else {
                drop(conn, status: "视频尺寸与配置不符，请重新连接"); return
            }
            videoRenderer.flush(removingDisplayedImage: true)
            videoBackpressure = ReceiverVideoBackpressurePolicy()
        }
        guard !packet.slices.isEmpty else { return }
        if videoRenderer.status == .failed {
            failVideo(on: conn); return
        }
        if waitingForKeyframe && !packet.keyframe { requestKeyframe(); return }
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
            DispatchQueue.main.async { self.videoSize = size }
            publish(status: "正在接收 \(dims.width) × \(dims.height) · \(videoCodec == .hevc ? "HEVC" : "H.264")")
        }
        waitingForKeyframe = false
        hasVideoFrame = true
        firstVideoDeadline = nil
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
        DispatchQueue.main.async { self.videoSize = .zero }
    }

    private func resetStream() {
        cursorDelivery.reset()
        diagnosticsStart = ProcessInfo.processInfo.systemUptime
        enqueuedFrames = 0
        backpressureFlushes = 0
        backpressureToleratedFrames = 0
        wireInputGrant = nil
        let epoch = inputBudget.reset(accepting: false)
        DispatchQueue.main.async {
            self.inputGeneration = epoch; self.inputGrant = nil; self.inputStatus = "请连接支持键鼠回传的加密发送端"
        }
        decoder = ReceiverFrameDecoder()
        videoCodec = .h264
        hevcFailureSent = false
        fallbackDeadline = nil
        firstVideoDeadline = nil
        resetVideo()
        lastCursorSequence = 0
        sampleCount = 0
        statsStart = Date()
        DispatchQueue.main.async { self.fps = 0; self.codecLabel = "H.264"; self.encrypted = false; self.onReset?(); self.onCursor?(0, 0, false) }
    }

    private func publish(connected: Bool? = nil, status: String? = nil, port: UInt16? = nil) {
        DispatchQueue.main.async {
            if let connected { self.connected = connected }
            if let status { self.status = status }
            if let port { self.listeningPort = port }
        }
    }
}
