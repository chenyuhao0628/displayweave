import SwiftUI
import Network
import Combine
import Sparkle

@MainActor
final class SenderController: ObservableObject {
    static let shared = SenderController()

    @Published var presentation = AppPresentation(
        rawValue: UserDefaults.standard.string(forKey: "presentation") ?? "") ?? .dock {
        didSet {
            UserDefaults.standard.set(presentation.rawValue, forKey: "presentation")
            NSApp.setActivationPolicy(presentation == .dock ? .regular : .accessory)
            // Never strand the user without UI: leaving menu-bar mode opens
            // the window immediately.
            if presentation != .menuBar { MainWindow.show() }
        }
    }

    @Published var sessions: [DeviceSession] = []
    @Published var discovered: [NWBrowser.Result] = []
    @Published var usbDevices: [UsbmuxDevice] = []
    @Published var androidDevices: [AndroidAdbDevice] = []
    @Published var androidAdbStatus = "正在查找 ADB…"
    @Published var androidAdbPath = UserDefaults.standard.string(forKey: "androidAdbPath") ?? "" {
        didSet {
            UserDefaults.standard.set(androidAdbPath, forKey: "androidAdbPath")
            Task { await refreshAndroidAdb() }
        }
    }
    // `-host x.x.x.x` / `-port n` bypass usbmuxd with a manual TCP endpoint
    // (debugging escape hatch, e.g. an iproxy or SSH tunnel).
    @Published var host = UserDefaults.standard.string(forKey: "host") ?? "127.0.0.1"
    @Published var port = UserDefaults.standard.string(forKey: "port") ?? "9000"
    // `-mode mirror` / `-mode extend` launch argument also works.
    @Published var mode = CaptureMode(rawValue: UserDefaults.standard.string(forKey: "mode") ?? "") ?? .extend
    @Published var settings = StreamSettings.load() {
        didSet {
            settings.save()
        }
    }
    var quality: StreamQuality { settings.quality }

    var running: Bool { sessions.contains { !$0.failed } }
    var androidUsbDevices: [AndroidAdbDevice] {
        AndroidAdbDeviceSelection.usbDevices(from: androidDevices)
    }

    private var browser: NWBrowser?
    private var usbWatcher: UsbmuxDeviceWatcher?
    private var androidAdbClient: AndroidAdbClient?
    private var androidForwardManager: AndroidAdbForwardManager?
    private var androidConnectPending = Set<String>()
    private var androidRecoveryAttempt: [String: Int] = [:]
    private var androidRecoveryGeneration: [String: Int] = [:]
    private let benchmarkLaunch = BenchmarkLaunchOptions.parse(ProcessInfo.processInfo.arguments)
    private var didAutoStartBenchmark = false

    // Connection policy keeps one session per physical device. Apple
    // transports retain the existing explicit/no-mid-session-handover
    // behavior. Android Auto is different by design: bounded USB recovery
    // may fall back only to the same install ID over App WiFi, and a later
    // wired attach upgrades that same WiFi session back to USB. The old
    // session must end before dialing the replacement because the Android
    // Receiver accepts one client.
    //
    //  - USB devices connect on attach ("plug in and go") unless the user
    //    explicitly disconnected them once (usbDisabled).
    //  - WiFi devices the user connected before (wifiRemembered) reconnect
    //    in a short window at LAUNCH only — never mid-session.
    // `-autostart NO` disables all auto-connecting.
    private var usbDisabled = Set(UserDefaults.standard.stringArray(forKey: "usbDisabled") ?? []) {
        didSet { UserDefaults.standard.set(Array(usbDisabled), forKey: "usbDisabled") }
    }
    private var wifiRemembered = Set(UserDefaults.standard.stringArray(forKey: "wifiRemembered") ?? []) {
        didSet { UserDefaults.standard.set(Array(wifiRemembered), forKey: "wifiRemembered") }
    }
    // Install id learned from each USB device's hello, persisted, so the
    // same hardware is recognized across transports even when the user
    // renamed the advertised service. @Published so the device list regroups
    // the moment an identity is learned.
    @Published private var installIDByUDID: [String: String] =
        UserDefaults.standard.dictionary(forKey: "installIDByUDID") as? [String: String] ?? [:] {
        didSet { UserDefaults.standard.set(installIDByUDID, forKey: "installIDByUDID") }
    }
    @Published private var installIDByAndroidSerial: [String: String] =
        UserDefaults.standard.dictionary(forKey: "installIDByAndroidSerial") as? [String: String] ?? [:] {
        didSet { UserDefaults.standard.set(installIDByAndroidSerial,
                                           forKey: "installIDByAndroidSerial") }
    }
    private let autoConnectEnabled = UserDefaults.standard.object(forKey: "autostart") == nil
        || UserDefaults.standard.bool(forKey: "autostart")

    // Bonjour usually reports devices before usbmuxd does — WiFi reconnects
    // wait out this window so a cabled device is dialed over USB first. The
    // deadline closes the window for good: a remembered WiFi device that
    // appears later was brought near the Mac mid-session, which is a user
    // action to confirm, not auto-grab.
    private var wifiAutoConnectArmed = false
    private var wifiAutoConnectDeadline = Date().addingTimeInterval(12)

    private(set) var roleEnabled = false
    private var roleGeneration = 0
    private var androidPollTask: Task<Void, Never>?
    private var autoConnectTask: Task<Void, Never>?
    private var cleanupTasks: [UUID: Task<Void, Never>] = [:]
    private var replacementTask: Task<Void, Never>?
    private var replacementTargets: [ConnectionTarget] = []
    private var replacementGeneration = 0
    @Published private(set) var replacingSessions = false

    init() {
        setRoleEnabled(UserDefaults.standard.string(forKey: "macRole") != "receiver")
    }

    @discardableResult
    func setRoleEnabled(_ enabled: Bool) -> Task<Void, Never>? {
        guard enabled != roleEnabled else { return nil }
        roleEnabled = enabled
        roleGeneration += 1
        androidPollTask?.cancel(); androidPollTask = nil
        autoConnectTask?.cancel(); autoConnectTask = nil
        browser?.cancel(); browser = nil
        usbWatcher?.stop(); usbWatcher = nil
        wifiAutoConnectArmed = false
        if !enabled {
            for serial in Array(androidRecoveryGeneration.keys) { androidRecoveryGeneration[serial, default: 0] += 1 }
            replacementTask?.cancel()
            replacementTask = nil
            replacementTargets = []
            replacingSessions = false
            replacementGeneration += 1
            sessions.forEach { end($0) }
            let cleanups = Array(cleanupTasks.values)
            discovered = []; usbDevices = []; androidDevices = []
            return Task { for cleanup in cleanups { await cleanup.value } }
        }
        let generation = roleGeneration
        wifiAutoConnectDeadline = Date().addingTimeInterval(12)
        startBrowsing()
        usbWatcher = UsbmuxDeviceWatcher { [weak self] devices in
            guard let self, self.roleEnabled, self.roleGeneration == generation else { return }
            self.usbDevices = devices
            self.autoConnect()
        }
        autoConnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled, self.roleEnabled, self.roleGeneration == generation else { return }
            self.wifiAutoConnectArmed = true
            self.autoConnect()
        }
        androidPollTask = Task { [weak self] in await self?.pollAndroidAdb() }
        return nil
    }

    private func pollAndroidAdb() async {
        while !Task.isCancelled {
            await refreshAndroidAdb()
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func refreshAndroidAdb() async {
        guard roleEnabled, !Task.isCancelled else { return }
        let generation = roleGeneration
        let configured = androidAdbPath.isEmpty ? nil : androidAdbPath
        guard let executable = AndroidAdbExecutableResolver.resolve(configuredPath: configured) else {
            androidDevices = []
            androidAdbStatus = AndroidAdbFailure.executableNotFound(
                AndroidAdbExecutableResolver.searchedPaths(configuredPath: configured))
                .localizedDescription
            return
        }
        if androidAdbClient?.executable != executable {
            let client = AndroidAdbClient(executable: executable,
                                          runner: FoundationAdbProcessRunner())
            let manager = AndroidAdbForwardManager(client: client)
            let hasActiveAndroidSession = sessions.contains {
                if case .androidAdb = $0.target { return true }
                return false
            }
            if !hasActiveAndroidSession {
                await manager.cleanupPersistedMappings()
            }
            guard roleEnabled, roleGeneration == generation, !Task.isCancelled else { return }
            androidAdbClient = client
            androidForwardManager = manager
        }
        guard let androidAdbClient else { return }
        do {
            let devices = try await androidAdbClient.devices()
            guard roleEnabled, roleGeneration == generation, !Task.isCancelled else { return }
            androidDevices = devices
            androidAdbStatus = AndroidAdbPresentation.make(
                executableFound: true, devices: devices).message
            autoConnect()
        } catch {
            guard roleEnabled, roleGeneration == generation, !Task.isCancelled else { return }
            androidDevices = []
            androidAdbStatus = error.localizedDescription
        }
    }

    private func startBrowsing() {
        // TXT records carry the receiver's install id (new receivers).
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_opensidecar._tcp", domain: nil), using: .tcp)
        let generation = roleGeneration
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                guard let self, self.roleEnabled, self.roleGeneration == generation else { return }
                self.discovered = results.filter { self.txtID(of: $0) != StreamReceiver.installID }
                self.autoConnect()
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    // MARK: - Physical-device identity

    private func serviceName(of result: NWBrowser.Result) -> String? {
        if case .service(let name, _, _, _) = result.endpoint { return name }
        return nil
    }

    private func txtID(of result: NWBrowser.Result) -> String? {
        if case .bonjour(let txt) = result.metadata { return txt["id"] }
        return nil
    }

    /// Same hardware? Strong match: the service's install id equals the id
    /// this USB device announced in a (past or present) hello. Fallback for
    /// old receivers: lockdown device name equals the service name.
    private func sameDevice(_ result: NWBrowser.Result, _ device: UsbmuxDevice) -> Bool {
        if let id = txtID(of: result), installIDByUDID[device.udid] == id { return true }
        if let name = serviceName(of: result), let usbName = device.name,
           usbName == name { return true }
        return false
    }

    private func sameAndroidDevice(_ result: NWBrowser.Result,
                                   _ device: AndroidAdbDevice) -> Bool {
        guard let installID = installIDByAndroidSerial[device.serial] else { return false }
        return txtID(of: result) == installID
    }

    /// The session (over either transport) already serving this USB device.
    private func activeSession(coveringUSB device: UsbmuxDevice) -> DeviceSession? {
        if let direct = session(for: "usb:\(device.udid)") { return direct }
        return sessions.first { s in
            guard case .wifi(let result) = s.target else { return false }
            if let id = installIDByUDID[device.udid],
               s.deviceID == id || txtID(of: result) == id { return true }
            return serviceName(of: result) != nil && device.name == serviceName(of: result)
        }
    }

    /// The session (over either transport) already serving this WiFi service.
    private func activeSession(coveringWiFi result: NWBrowser.Result) -> DeviceSession? {
        if let name = serviceName(of: result), let direct = session(for: "wifi:\(name)") {
            return direct
        }
        return sessions.first { s in
            if let id = txtID(of: result), s.deviceID == id { return true }
            switch s.target {
            case .usb(let udid):
                guard let udid, let device = usbDevices.first(where: { $0.udid == udid })
                else { return false }
                return sameDevice(result, device)
            case .androidAdb(let mapping):
                guard let device = androidUsbDevices.first(where: { $0.serial == mapping.serial })
                else { return false }
                return sameAndroidDevice(result, device)
            default:
                return false
            }
        }
    }

    /// Existing session for this physical Android, including its App WiFi
    /// twin learned from the Receiver install ID.
    private func activeSession(coveringAndroidUSB device: AndroidAdbDevice) -> DeviceSession? {
        if let direct = session(for: "android-adb:\(device.serial)") { return direct }
        guard let installID = installIDByAndroidSerial[device.serial] else { return nil }
        return sessions.first { session in
            guard case .wifi(let result) = session.target else { return false }
            return session.deviceID == installID || txtID(of: result) == installID
        }
    }

    // MARK: - Connection policy

    private func autoConnect() {
        guard !replacingSessions else { return }
        guard roleEnabled, autoConnectEnabled else { return }
        dedupeSessions()
        let permitsUSB = settings.transportMode != .wifi
        let permitsWiFi = settings.transportMode != .usb
        // The -host/-port escape hatch is an explicit choice — dial it like
        // the wired devices (it joins them, not replaces them).
        if permitsUSB, UserDefaults.standard.object(forKey: "host") != nil,
           !usbDisabled.contains("usb:first"), session(for: "usb:first") == nil {
            connect(to: .usb(udid: nil))
        }
        for device in usbDevices
            where permitsUSB
            && !usbDisabled.contains("usb:\(device.udid)")
            && activeSession(coveringUSB: device) == nil {
            connect(to: .usb(udid: device.udid))
        }
        for device in androidUsbDevices
            where permitsUSB
            && device.state == .device
            && !usbDisabled.contains("android-adb:\(device.serial)")
            && session(for: "android-adb:\(device.serial)") == nil
            && !androidConnectPending.contains(device.serial) {
            connect(to: .androidAdbDevice(serial: device.serial))
        }
        guard permitsWiFi, wifiAutoConnectArmed, Date() < wifiAutoConnectDeadline else { return }
        for result in discovered {
            let target = ConnectionTarget.wifi(result)
            if wifiRemembered.contains(target.sessionID),
               activeSession(coveringWiFi: result) == nil,
               !cabled(result) {
                connect(to: target)
            }
        }
    }

    /// An attached, auto-connectable USB device is (about to be) dialed over
    /// the cable — its WiFi service must not be grabbed in the launch race.
    private func cabled(_ result: NWBrowser.Result) -> Bool {
        usbDevices.contains {
            sameDevice(result, $0) && !usbDisabled.contains("usb:\($0.udid)")
        } || androidUsbDevices.contains {
            sameAndroidDevice(result, $0)
                && !usbDisabled.contains("android-adb:\($0.serial)")
                && $0.state == .device
        }
    }

    /// Safety net, not a feature: if identity was learned too late (old
    /// receiver, renamed service) and one physical device ended up with two
    /// sessions, the transports steal the receiver's single connection from
    /// each other forever. Keep the cable, drop the WiFi twin.
    private func dedupeSessions() {
        let usbSessionIDs = Set(sessions.compactMap { s -> String? in
            switch s.target {
            case .usb, .androidAdb: return s.deviceID
            default: return nil
            }
        })
        let cabledNames = Set(usbDevices.compactMap { device in
            session(for: "usb:\(device.udid)") != nil ? device.name : nil
        })
        for s in sessions {
            guard case .wifi(let result) = s.target else { continue }
            let duplicate = (s.deviceID.map { usbSessionIDs.contains($0) } ?? false)
                || (txtID(of: result).map { usbSessionIDs.contains($0) } ?? false)
                || (serviceName(of: result).map { cabledNames.contains($0) } ?? false)
            if duplicate {
                Log.info("two sessions for one device — keeping the cable, dropping \(s.id)")
                end(s)
            }
        }
    }

    /// Human-readable device name for a target (no transport suffix — the
    /// UI shows transports separately).
    func label(for target: ConnectionTarget) -> String {
        switch target {
        case .usb(let udid):
            if let device = usbDevices.first(where: { $0.udid == udid }), let name = device.name {
                return name
            }
            return udid == nil ? "手动连接（\(host):\(port)）" : "iPhone / iPad"
        case .androidAdbDevice(let serial):
            return androidDevices.first(where: { $0.serial == serial })?.model ?? "Android"
        case .androidAdb(let mapping):
            return androidDevices.first(where: { $0.serial == mapping.serial })?.model ?? "Android"
        case .wifi(let result):
            return serviceName(of: result) ?? "WiFi 设备"
        }
    }

    func session(for id: String) -> DeviceSession? {
        sessions.first { $0.id == id }
    }

    /// Derive a stable, per-device display serial from the session identity.
    /// FNV-1a over the id string; macOS keys saved display arrangement on
    /// vendor/product/serial, so each device keeps its screen position.
    private static func displaySerial(for id: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in id.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return hash == 0 ? 1 : hash
    }

    func connect(to target: ConnectionTarget, userInitiated: Bool = false) {
        guard roleEnabled, !replacingSessions else { return }
        if case .wifi(let result) = target, txtID(of: result) == StreamReceiver.installID { return }
        if case .androidAdbDevice(let serial) = target {
            connectAndroidAdb(serial: serial, userInitiated: userInitiated)
            return
        }
        let id = target.sessionID
        guard session(for: id) == nil else { return }

        // Never create a second session for the same physical device — the
        // receiver holds one connection, so a twin would steal it. But an
        // explicit user click overrides: e.g. right after unplugging the
        // cable, the dying USB session sits in its 10s reconnect grace and
        // would otherwise swallow the tap on the WiFi row.
        let covering: DeviceSession?
        switch target {
        case .usb(let udid?):
            covering = usbDevices.first(where: { $0.udid == udid })
                .flatMap { activeSession(coveringUSB: $0) }
        case .wifi(let result):
            covering = activeSession(coveringWiFi: result)
        default:
            covering = nil
        }
        if let covering {
            guard userInitiated else { return }
            Log.info("user chose \(id) — taking over from \(covering.id)")
            end(covering)
        }

        // Connecting a device clears its "don't auto-connect" state.
        switch target {
        case .usb: usbDisabled.remove(id)
        case .androidAdb: usbDisabled.remove(id)
        case .androidAdbDevice: break
        case .wifi: wifiRemembered.insert(id)
        }

        let transport: SenderTransport
        switch target {
        case .usb(let udid):
            guard let portNum = UInt16(port) else { return }
            if UserDefaults.standard.object(forKey: "host") != nil, udid == nil {
                // Manual override: dial a plain TCP endpoint instead of usbmuxd.
                transport = .tcp(.hostPort(host: NWEndpoint.Host(host),
                                           port: NWEndpoint.Port(rawValue: portNum)!))
            } else {
                transport = .usb(udid: udid, port: portNum)
            }
        case .androidAdb(let mapping):
            transport = .androidAdb(port: mapping.localPort)
        case .androidAdbDevice:
            return
        case .wifi(let result):
            transport = .tcp(result.endpoint)
        }

        let name = label(for: target)
        let sender = MacSender(transport: transport, name: name, mode: mode,
                               settings: settings, displaySerial: Self.displaySerial(for: id))
        let session = DeviceSession(id: id, target: target, name: name, sender: sender)
        if case .androidAdb = target {
            session.androidForwardManager = androidForwardManager
        }
        sender.onStatus = { [weak self, weak session] text in
            guard let self, let session, !session.failed, self.sessions.contains(where: { $0 === session }) else { return }
            session.status = text
            Log.info("status[\(id)]: \(text)")
            if text.hasPrefix("已连接") {
                self.autoStartBenchmarkIfRequested()
            }
        }
        sender.onHello = { [weak self, weak session] info in
            guard let self, let session, self.roleEnabled, !session.failed,
                  self.sessions.contains(where: { $0 === session }) else { return }
            guard info.id != StreamReceiver.installID else { self.end(session); return }
            session.deviceID = info.id
            session.deviceKind = info.device
            if case .usb(let udid?) = session.target, let installID = info.id {
                self.installIDByUDID[udid] = installID
            }
            if case .androidAdb(let mapping) = session.target, let installID = info.id {
                self.installIDByAndroidSerial[mapping.serial] = installID
                self.androidRecoveryAttempt.removeValue(forKey: mapping.serial)
                self.androidRecoveryGeneration[mapping.serial, default: 0] += 1
            }
            self.dedupeSessions()
        }
        sender.onStats = { [weak session] frames, mbps in
            session?.framesSent = frames
            session?.mbps = mbps
        }
        sender.onTargetBitrate = { [weak session] mbps in
            session?.targetMbps = mbps
        }
        sender.onBenchmarkStatus = { [weak session] status in
            session?.benchmarkStatus = status
        }
        sender.onDisconnected = { [weak self, weak session] in
            guard let self, let session, self.roleEnabled, self.sessions.contains(where: { $0 === session }) else { return }
            if case .androidAdb(let mapping) = session.target {
                self.recoverAndroidAdb(session: session, mapping: mapping)
            } else {
                Log.info("device disconnected — session \(session.id) stopped")
                self.end(session)
            }
        }
        for existing in sessions where existing.sender.isBenchmarkActive {
            existing.sender.stopBenchmark()
            existing.benchmarkStatus = "Benchmark stopped: another session connected"
        }
        // Adapted from upstream 87b000b / c27e538: retain the error row, free
        // a partially built pipeline and retry by creating a fresh sender.
        let forwardManager = session.androidForwardManager
        session.lifetime = SessionLifetime(start: { try await sender.start() }, stop: {
            let cleanup = sender.stop()
            return Task {
                await cleanup.value
                if case .androidAdb(let mapping) = target, let forwardManager {
                    await forwardManager.remove(sessionID: mapping.sessionID)
                }
            }
        }) { [weak self, weak session] error in
            guard let self, let session, self.sessions.contains(where: { $0 === session }) else { return }
            Log.info("sender failed to start: \(error)")
            session.failed = true
            session.status = "失败：\(error.localizedDescription)"
            if case .androidAdb = session.target { self.androidAdbStatus = session.status }
        }
        sessions.append(session)
        session.lifetime.start()
    }

    func startBenchmark(scene: BenchmarkScene, duration: BenchmarkDuration) {
        guard sessions.count == 1, let session = sessions.first else { return }
        do {
            try session.sender.startBenchmark(scene: scene, duration: duration)
        } catch {
            session.benchmarkStatus = "Benchmark failed: \(error.localizedDescription)"
        }
    }

    private func autoStartBenchmarkIfRequested() {
        guard benchmarkLaunch.autoStart, !didAutoStartBenchmark,
              sessions.count == 1 else { return }
        didAutoStartBenchmark = true
        startBenchmark(scene: benchmarkLaunch.scene, duration: benchmarkLaunch.duration)
        Log.info("benchmark auto-start scene=\(benchmarkLaunch.scene.rawValue) duration=\(benchmarkLaunch.duration.rawValue)s")
    }

    func stopBenchmark() {
        sessions.first?.sender.stopBenchmark()
    }

    private func connectAndroidAdb(serial: String, userInitiated: Bool) {
        guard settings.transportMode != .wifi,
              !androidConnectPending.contains(serial),
              session(for: "android-adb:\(serial)") == nil,
              let device = androidUsbDevices.first(where: { $0.serial == serial }) else { return }
        guard device.state == .device else {
            switch device.state {
            case .unauthorized: androidAdbStatus = AndroidAdbFailure.unauthorized(serial).localizedDescription
            case .offline: androidAdbStatus = AndroidAdbFailure.offline(serial).localizedDescription
            default: androidAdbStatus = "ADB 设备不可用：\(serial)"
            }
            return
        }
        if let covering = activeSession(coveringAndroidUSB: device) {
            let existingInstallID: String?
            if case .wifi(let result) = covering.target {
                existingInstallID = covering.deviceID ?? txtID(of: result)
            } else {
                existingInstallID = nil
            }
            let decision = AndroidTransportHandoverPolicy.decision(
                mode: settings.transportMode,
                existing: .wifi(installID: existingInstallID),
                arrivingUSBInstallID: installIDByAndroidSerial[serial])
            guard decision == .replaceWiFiWithUSB else { return }
            Log.info("Android USB available — upgrading same-install-ID session from \(covering.id)")
            end(covering)
        }
        guard let androidForwardManager else {
            androidAdbStatus = "ADB 尚未就绪"
            return
        }
        guard roleEnabled else { return }
        let generation = roleGeneration
        androidConnectPending.insert(serial)
        Task {
            defer { androidConnectPending.remove(serial) }
            do {
                let mapping = try await androidForwardManager.create(serial: serial)
                guard roleEnabled, roleGeneration == generation else {
                    await androidForwardManager.remove(sessionID: mapping.sessionID)
                    return
                }
                connect(to: .androidAdb(mapping), userInitiated: userInitiated)
            } catch {
                androidAdbStatus = "无法创建 USB 端口映射：\(error.localizedDescription)"
            }
        }
    }

    private func recoverAndroidAdb(session: DeviceSession, mapping: AndroidAdbForward) {
        let serial = mapping.serial
        let installID = session.deviceID ?? installIDByAndroidSerial[serial]
        let manager = session.androidForwardManager
        Log.info("Android USB disconnected — beginning bounded recovery for \(serial)")
        end(session)

        guard settings.transportMode != .wifi, let manager else { return }
        let startAttempt = androidRecoveryAttempt[serial, default: 0]
        androidRecoveryGeneration[serial, default: 0] += 1
        let generation = androidRecoveryGeneration[serial, default: 0]

        Task {
            for attempt in startAttempt..<TransportSelectionPolicy.recoveryDelays.count {
                guard roleEnabled, androidRecoveryGeneration[serial] == generation else { return }
                let delay = TransportSelectionPolicy.recoveryDelays[attempt]
                androidAdbStatus = "USB 已断开，\(delay.formatted()) 秒后尝试恢复（\(attempt + 1)/5）"
                try? await Task.sleep(for: .seconds(delay))
                guard roleEnabled, androidRecoveryGeneration[serial] == generation else { return }

                do {
                    guard let client = androidAdbClient else { throw AndroidAdbFailure.noDevices }
                    let devices = try await client.devices()
                    guard roleEnabled, androidRecoveryGeneration[serial] == generation else { return }
                    androidDevices = devices
                    let usbDevices = AndroidAdbDeviceSelection.usbDevices(from: devices)
                    guard usbDevices.contains(where: {
                        $0.serial == serial && $0.state == .device
                    }) else {
                        androidRecoveryAttempt[serial] = attempt + 1
                        continue
                    }
                    let replacement = try await manager.create(serial: serial)
                    guard roleEnabled, androidRecoveryGeneration[serial] == generation else {
                        await manager.remove(sessionID: replacement.sessionID)
                        return
                    }
                    androidRecoveryAttempt[serial] = attempt + 1
                    androidAdbStatus = "USB 映射已恢复，正在重新连接 Android Receiver…"
                    connect(to: .androidAdb(replacement))
                    return
                } catch {
                    androidRecoveryAttempt[serial] = attempt + 1
                    androidAdbStatus = "USB 恢复失败：\(error.localizedDescription)"
                }
            }
            finishAndroidRecovery(serial: serial, installID: installID,
                                  generation: generation)
        }
    }

    private func finishAndroidRecovery(serial: String, installID: String?, generation: Int) {
        guard roleEnabled, androidRecoveryGeneration[serial] == generation else { return }
        androidRecoveryAttempt.removeValue(forKey: serial)
        guard settings.transportMode == .auto else {
            androidAdbStatus = "USB 恢复失败，请检查数据线、USB 调试授权和 Android Receiver"
            return
        }
        guard let installID,
              let receiver = discovered.first(where: { txtID(of: $0) == installID }) else {
            androidAdbStatus = "USB 恢复失败，且未发现同一设备的 WiFi Receiver"
            return
        }
        androidAdbStatus = "USB 恢复失败，正在切换同一设备的 WiFi…"
        connect(to: .wifi(receiver))
    }

    /// User-initiated disconnect: also opt the device out of auto-connect.
    func disconnect(_ session: DeviceSession) {
        switch session.target {
        case .usb: usbDisabled.insert(session.id)
        case .androidAdb(let mapping):
            usbDisabled.insert(session.id)
            androidRecoveryGeneration[mapping.serial, default: 0] += 1
            androidRecoveryAttempt.removeValue(forKey: mapping.serial)
        case .androidAdbDevice: break
        case .wifi: wifiRemembered.remove(session.id)
        }
        end(session)
    }

    func disconnectAll() {
        sessions.forEach { disconnect($0) }
    }

    @discardableResult
    private func end(_ session: DeviceSession) -> Task<Void, Never> {
        let captureCleanup = session.lifetime.stop()
        sessions.removeAll { $0 === session }
        let token = UUID()
        let task = Task { [weak self] in
            await captureCleanup.value
            self?.cleanupTasks.removeValue(forKey: token)
        }
        cleanupTasks[token] = task
        return task
    }

    private func freshTarget(_ target: ConnectionTarget) -> ConnectionTarget {
        if case .androidAdb(let mapping) = target { return .androidAdbDevice(serial: mapping.serial) }
        return target
    }

    func retry(_ session: DeviceSession) {
        guard session.failed, !replacingSessions, sessions.contains(where: { $0 === session }) else { return }
        replace([session], targets: [freshTarget(session.target)])
    }

    /// Rebuild only after old capture, startup and ADB-forward cleanup finish.
    /// Rapid edits retain the latest target set and cannot resurrect a receive role.
    func restartAll() {
        let targets = replacementTargets + sessions.map { freshTarget($0.target) }
        guard !targets.isEmpty, roleEnabled else { return }
        replace(sessions, targets: targets)
    }

    private func replace(_ old: [DeviceSession], targets: [ConnectionTarget]) {
        replacementTask?.cancel()
        replacementGeneration += 1
        let token = replacementGeneration, role = roleGeneration
        var seen = Set<String>()
        replacementTargets = targets.filter { seen.insert($0.sessionID).inserted }
        replacingSessions = true
        old.forEach { end($0) }
        let cleanup = Array(cleanupTasks.values)
        replacementTask = Task {
            for task in cleanup { await task.value }
            guard !Task.isCancelled, roleEnabled, roleGeneration == role,
                  replacementGeneration == token else { return }
            let next = replacementTargets
            replacementTargets = []
            replacingSessions = false
            replacementTask = nil
            next.forEach { connect(to: $0, userInitiated: true) }
        }
    }

    // MARK: - Device list (one row per physical device)

    struct DeviceEntry: Identifiable {
        let id: String
        let name: String
        let detail: String?
        let usbTarget: ConnectionTarget?
        let wifiTarget: ConnectionTarget?

        var transportLabel: String {
            switch (usbTarget != nil, wifiTarget != nil) {
            case (true, true): return "USB · 局域网"
            case (true, false): return "USB"
            case (false, true): return "局域网"
            default: return ""
            }
        }
        func preferredTarget(for mode: StreamTransportMode) -> ConnectionTarget? {
            switch mode {
            case .auto: return usbTarget ?? wifiTarget
            case .usb: return usbTarget
            case .wifi: return wifiTarget
            }
        }
    }

    var deviceEntries: [DeviceEntry] {
        var entries: [DeviceEntry] = []
        var mergedServices = Set<String>()
        var coveredSessionIDs = Set<String>()

        for device in androidUsbDevices {
            let twin = discovered.first { sameAndroidDevice($0, device) }
            if let twin, let name = serviceName(of: twin) { mergedServices.insert(name) }
            let adbTarget = ConnectionTarget.androidAdbDevice(serial: device.serial)
            coveredSessionIDs.insert(adbTarget.sessionID)
            if let twin { coveredSessionIDs.insert(ConnectionTarget.wifi(twin).sessionID) }
            entries.append(DeviceEntry(
                id: "android-device:\(device.serial)",
                name: device.model ?? "Android（\(device.serial)）",
                detail: androidDeviceDetail(device),
                usbTarget: device.state == .device ? adbTarget : nil,
                wifiTarget: twin.map { .wifi($0) }))
        }

        for device in usbDevices {
            // A discovered WiFi service for the same hardware folds into
            // this row instead of appearing as a second device.
            let twin = discovered.first { sameDevice($0, device) }
            if let twin, let name = serviceName(of: twin) { mergedServices.insert(name) }
            let usbTarget = ConnectionTarget.usb(udid: device.udid)
            coveredSessionIDs.insert(usbTarget.sessionID)
            if let twin { coveredSessionIDs.insert(ConnectionTarget.wifi(twin).sessionID) }
            entries.append(DeviceEntry(
                id: "device:\(device.udid)",
                name: device.name
                    ?? twin.flatMap(serviceName)
                    ?? session(for: usbTarget.sessionID)?.deviceKind
                    ?? "iPhone / iPad",
                detail: nil,
                usbTarget: usbTarget,
                wifiTarget: twin.map { .wifi($0) }))
        }
        if UserDefaults.standard.object(forKey: "host") != nil {
            let target = ConnectionTarget.usb(udid: nil)
            coveredSessionIDs.insert(target.sessionID)
            entries.append(DeviceEntry(id: target.sessionID, name: label(for: target),
                                       detail: nil,
                                       usbTarget: target, wifiTarget: nil))
        }
        for result in discovered {
            guard let name = serviceName(of: result), !mergedServices.contains(name)
            else { continue }
            let target = ConnectionTarget.wifi(result)
            coveredSessionIDs.insert(target.sessionID)
            entries.append(DeviceEntry(id: "service:\(name)", name: name,
                                       detail: nil,
                                       usbTarget: nil, wifiTarget: target))
        }
        // Sessions whose device vanished from discovery (e.g. Bonjour record
        // gone while the stream is still alive) keep a row to disconnect.
        for session in sessions where !coveredSessionIDs.contains(session.id) {
            entries.append(DeviceEntry(id: session.id, name: session.name,
                                       detail: nil,
                                       usbTarget: nil, wifiTarget: nil))
        }
        return entries
    }

    private func androidDeviceDetail(_ device: AndroidAdbDevice) -> String {
        let shortSerial = device.serial.count > 12
            ? "…" + device.serial.suffix(8)
            : device.serial
        switch device.state {
        case .device: return "USB 已授权 · \(shortSerial)"
        case .unauthorized: return "尚未授权 USB 调试，请在设备上允许当前 Mac · \(shortSerial)"
        case .offline: return "ADB 设备离线 · \(shortSerial)"
        case .unknown(let state): return "ADB 状态：\(state) · \(shortSerial)"
        }
    }

    func session(for entry: DeviceEntry) -> DeviceSession? {
        if let target = entry.usbTarget, let s = session(for: target.sessionID) { return s }
        if let target = entry.wifiTarget, let s = session(for: target.sessionID) { return s }
        return session(for: entry.id)   // dangling-session rows
    }
}

/// Polls the permission states the app depends on so the UI can surface
/// exactly what's missing instead of failing silently.
