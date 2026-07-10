import SwiftUI
import Network
import Combine
import Sparkle

/// How the app presents itself. One bundle, switched at runtime via the
/// activation policy — like Raycast/Hammerspoon style background agents.
enum AppPresentation: String, CaseIterable {
    case menuBar, dock, background

    var label: String {
        switch self {
        case .menuBar: return "菜单栏"
        case .dock: return "程序坞"
        case .background: return "仅后台运行"
        }
    }
}

@main
struct OpenSidecarMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = SenderController.shared

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(
            get: { controller.presentation == .menuBar },
            set: { _ in }
        )) {
            ContentView(controller: controller, updater: appDelegate.updater)
        } label: {
            Image(systemName: controller.running
                  ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Sparkle's standard updater. `startingUpdater: true` boots the updater
    // immediately so scheduled background checks (SUEnableAutomaticChecks)
    // run; the menu item drives manual "Check for Updates…". Held for the
    // app's lifetime here so every window (menu bar + control window) shares
    // one updater instance.
    let updater = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hand the updater to the control window, which is built outside the
        // SwiftUI App scene (NSHostingView), so it can offer the same button.
        MainWindow.updater = updater
        let presentation = SenderController.shared.presentation
        NSApp.setActivationPolicy(presentation == .dock ? .regular : .accessory)
        if presentation != .menuBar {
            MainWindow.show()
        }
    }

    // Background/Dock modes: opening the app again (Spotlight, Finder, Dock
    // click) brings up the control window — Hammerspoon-style.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows: Bool) -> Bool {
        MainWindow.show()
        return false
    }
}

/// The control panel as a regular window, for Dock/background presentation.
@MainActor
enum MainWindow {
    private static var window: NSWindow?
    // Set once at launch by AppDelegate so the control window can share the
    // app's single Sparkle updater.
    static var updater: SPUStandardUpdaterController?

    static func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 540),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            w.title = "DisplayWeave"
            w.contentView = NSHostingView(
                rootView: ContentView(controller: SenderController.shared,
                                      updater: updater))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum ConnectionTarget: Hashable {
    case usb(udid: String?)           // wired via built-in usbmuxd; nil = first device
    case androidAdbDevice(serial: String)
    case androidAdb(AndroidAdbForward)
    case wifi(NWBrowser.Result)       // discovered via Bonjour

    /// Stable identity for sessions and persistence — survives Bonjour
    /// re-discovery (fresh NWBrowser.Result) and USB replugs (new DeviceID).
    var sessionID: String {
        switch self {
        case .usb(let udid): return "usb:\(udid ?? "first")"
        case .androidAdbDevice(let serial): return "android-adb:\(serial)"
        case .androidAdb(let mapping): return "android-adb:\(mapping.serial)"
        case .wifi(let result):
            if case .service(let name, _, _, _) = result.endpoint { return "wifi:\(name)" }
            return "wifi:unknown"
        }
    }
}

/// One connected (or connecting) device: its target, its sender pipeline,
/// and the per-device status the UI shows. Each session owns a full pipeline
/// — virtual display, capture, encoder, socket — so devices are independent:
/// one disconnecting never stalls the others.
@MainActor
final class DeviceSession: ObservableObject, Identifiable {
    nonisolated let id: String
    let target: ConnectionTarget
    let name: String
    let sender: MacSender
    var androidForwardManager: AndroidAdbForwardManager?

    @Published var status = "正在启动…"
    @Published var framesSent = 0
    @Published var mbps = 0.0
    // Receiver's per-install identity (from hello) — the key for recognizing
    // the same physical device across USB and WiFi.
    var deviceID: String?
    // "iPhone" / "iPad" from hello — naming fallback while (or in case)
    // lockdown hasn't resolved the device's real name.
    var deviceKind: String?

    var transportLabel: String {
        switch target {
        case .usb, .androidAdb, .androidAdbDevice: return "USB"
        case .wifi: return "WiFi"
        }
    }

    init(id: String, target: ConnectionTarget, name: String, sender: MacSender) {
        self.id = id
        self.target = target
        self.name = name
        self.sender = sender
    }
}

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

    var running: Bool { !sessions.isEmpty }

    private var browser: NWBrowser?
    private var usbWatcher: UsbmuxDeviceWatcher?
    private var androidAdbClient: AndroidAdbClient?
    private var androidForwardManager: AndroidAdbForwardManager?
    private var androidConnectPending = Set<String>()
    private var androidRecoveryAttempt: [String: Int] = [:]
    private var androidRecoveryGeneration: [String: Int] = [:]

    // Connection policy — deliberately simple, no automatic transport
    // switching. One session per physical device; whichever transport
    // connected first keeps the device until the session ends. Unplugging
    // the cable ENDS the session (it does not migrate to WiFi), and a WiFi
    // drop does not migrate to the cable: silent transport handover
    // surprised users more than it helped (and every virtual-display
    // create/destroy flashes all screens).
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
    private let wifiAutoConnectDeadline = Date().addingTimeInterval(12)

    init() {
        startBrowsing()
        usbWatcher = UsbmuxDeviceWatcher { [weak self] devices in
            guard let self else { return }
            self.usbDevices = devices
            self.autoConnect()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            self.wifiAutoConnectArmed = true
            self.autoConnect()
        }
        Task { await pollAndroidAdb() }
    }

    private func pollAndroidAdb() async {
        while !Task.isCancelled {
            await refreshAndroidAdb()
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func refreshAndroidAdb() async {
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
            androidAdbClient = client
            androidForwardManager = AndroidAdbForwardManager(client: client)
        }
        guard let androidAdbClient else { return }
        do {
            let devices = try await androidAdbClient.devices()
            androidDevices = devices
            androidAdbStatus = AndroidAdbPresentation.make(
                executableFound: true, devices: devices).message
            autoConnect()
        } catch {
            androidDevices = []
            androidAdbStatus = error.localizedDescription
        }
    }

    private func startBrowsing() {
        // TXT records carry the receiver's install id (new receivers).
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_opensidecar._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.discovered = Array(results)
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
                guard let device = androidDevices.first(where: { $0.serial == mapping.serial })
                else { return false }
                return sameAndroidDevice(result, device)
            default:
                return false
            }
        }
    }

    // MARK: - Connection policy

    private func autoConnect() {
        guard autoConnectEnabled else { return }
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
        for device in androidDevices
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
        } || androidDevices.contains {
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
        sender.onStatus = { [weak session] text in
            session?.status = text
            Log.info("status[\(id)]: \(text)")
        }
        sender.onHello = { [weak self, weak session] info in
            guard let self, let session else { return }
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
        sender.onDisconnected = { [weak self, weak session] in
            guard let self, let session else { return }
            if case .androidAdb(let mapping) = session.target {
                self.recoverAndroidAdb(session: session, mapping: mapping)
            } else {
                Log.info("device disconnected — session \(session.id) stopped")
                self.end(session)
            }
        }
        sessions.append(session)
        Task {
            do {
                try await sender.start()
            } catch is CancellationError {
                // stopped by the user while waiting — nothing to report
            } catch {
                Log.info("sender failed to start: \(error)")
                session.status = "失败：\(error.localizedDescription)"
                if case .androidAdb = session.target {
                    self.androidAdbStatus = session.status
                    self.end(session)
                }
            }
        }
    }

    private func connectAndroidAdb(serial: String, userInitiated: Bool) {
        guard settings.transportMode != .wifi,
              !androidConnectPending.contains(serial),
              session(for: "android-adb:\(serial)") == nil,
              let device = androidDevices.first(where: { $0.serial == serial }) else { return }
        guard device.state == .device else {
            switch device.state {
            case .unauthorized: androidAdbStatus = AndroidAdbFailure.unauthorized(serial).localizedDescription
            case .offline: androidAdbStatus = AndroidAdbFailure.offline(serial).localizedDescription
            default: androidAdbStatus = "ADB 设备不可用：\(serial)"
            }
            return
        }
        guard let androidForwardManager else {
            androidAdbStatus = "ADB 尚未就绪"
            return
        }
        androidConnectPending.insert(serial)
        Task {
            defer { androidConnectPending.remove(serial) }
            do {
                let mapping = try await androidForwardManager.create(serial: serial)
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
                guard androidRecoveryGeneration[serial] == generation else { return }
                let delay = TransportSelectionPolicy.recoveryDelays[attempt]
                androidAdbStatus = "USB 已断开，\(delay.formatted()) 秒后尝试恢复（\(attempt + 1)/5）"
                try? await Task.sleep(for: .seconds(delay))
                guard androidRecoveryGeneration[serial] == generation else { return }

                do {
                    guard let client = androidAdbClient else { throw AndroidAdbFailure.noDevices }
                    let devices = try await client.devices()
                    androidDevices = devices
                    guard devices.contains(where: { $0.serial == serial && $0.state == .device }) else {
                        androidRecoveryAttempt[serial] = attempt + 1
                        continue
                    }
                    let replacement = try await manager.create(serial: serial)
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
        guard androidRecoveryGeneration[serial] == generation else { return }
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

    private func end(_ session: DeviceSession) {
        session.sender.stop()
        sessions.removeAll { $0.id == session.id }
        if case .androidAdb(let mapping) = session.target,
           let androidForwardManager = session.androidForwardManager {
            Task { await androidForwardManager.remove(sessionID: mapping.sessionID) }
        }
    }

    /// Mode/quality apply per-pipeline at construction — rebuild every session.
    func restartAll() {
        guard running else { return }
        let targets = sessions.map { session -> ConnectionTarget in
            if case .androidAdb(let mapping) = session.target {
                return .androidAdbDevice(serial: mapping.serial)
            }
            return session.target
        }
        sessions.forEach { end($0) }
        targets.forEach { connect(to: $0) }
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
            case (true, true): return "USB · WiFi"
            case (true, false): return "USB"
            case (false, true): return "WiFi"
            default: return ""
            }
        }
        /// Lowest latency first.
        var preferredTarget: ConnectionTarget? { usbTarget ?? wifiTarget }
    }

    var deviceEntries: [DeviceEntry] {
        var entries: [DeviceEntry] = []
        var mergedServices = Set<String>()
        var coveredSessionIDs = Set<String>()

        for device in androidDevices {
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
@MainActor
final class PermissionMonitor: ObservableObject {
    @Published var screenRecording = false
    @Published var accessibility = false
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    func refresh() {
        screenRecording = CGPreflightScreenCaptureAccess()
        accessibility = AXIsProcessTrusted()
    }

    /// Fire the system permission dialog on demand. macOS only shows each
    /// dialog once per reset — after that the call just (re)registers the
    /// app in System Settings, so the row exists to toggle manually.
    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        refresh()
    }

    func requestAccessibility() {
        _ = InputInjector.ensureAccessibilityPermission()
        refresh()
    }

    static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct ContentView: View {
    @ObservedObject var controller: SenderController
    @StateObject private var permissions = PermissionMonitor()
    // Optional so the view still compiles/previews without an updater (e.g.
    // if Sparkle ever fails to start); the button just disables itself then.
    let updater: SPUStandardUpdaterController?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DisplayWeave")
                        .font(.title3.bold())
                    Text("把 iPad、iPhone 和 Android 变成额外显示器")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if controller.running {
                    Button("全部断开") { controller.disconnectAll() }
                        .controlSize(.large)
                }
            }
            .padding(16)

            Divider()

            // Settings
            Form {
                Section("设备") {
                    if controller.deviceEntries.isEmpty {
                        Text("未发现设备。请用 USB 连接 iPhone 或 iPad，或在同一 WiFi 网络中的设备上打开 DisplayWeave。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(controller.deviceEntries) { entry in
                        if let session = controller.session(for: entry) {
                            // Title from the entry, not the session: the
                            // session name was snapshotted at connect time,
                            // often before lockdown resolved the real name.
                            SessionRow(title: entry.name, session: session,
                                       controller: controller)
                        } else {
                            HStack(alignment: .firstTextBaseline) {
                                Circle()
                                    .fill(.secondary.opacity(0.5))
                                    .frame(width: 9, height: 9)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name)
                                    if let detail = entry.detail {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(entry.transportLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let target = entry.preferredTarget {
                                    Button("连接") {
                                        controller.connect(to: target, userInitiated: true)
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }

                Picker("模式", selection: $controller.mode) {
                    Text("扩展").tag(CaptureMode.extend)
                    Text("镜像").tag(CaptureMode.mirror)
                }
                .pickerStyle(.segmented)
                .onChange(of: controller.mode) { controller.restartAll() }

                VStack(alignment: .leading, spacing: 4) {
                    Picker("FPS", selection: $controller.settings.fpsMode) {
                        ForEach(StreamFpsMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: controller.settings.fpsMode) { _, _ in controller.restartAll() }
                    Text("Auto 会根据接收端上报的 maxFps 选择 60/90/120，并在虚拟显示创建失败时回退。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Picker("Codec", selection: $controller.settings.codecMode) {
                        ForEach(StreamCodecMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: controller.settings.codecMode) { _, _ in controller.restartAll() }
                    Text("Auto 会优先采用接收端上报的首选 codec；HEVC 初始化失败会自动回退 H.264。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Picker("画质", selection: $controller.settings.quality) {
                        ForEach(StreamQuality.allCases, id: \.self) { q in
                            Text(q.label).tag(q)
                        }
                    }
                    .onChange(of: controller.settings.quality) { _, _ in controller.restartAll() }
                    Text(controller.settings.quality.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Picker("Transport", selection: $controller.settings.transportMode) {
                        ForEach(StreamTransportMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: controller.settings.transportMode) { _, _ in
                        controller.restartAll()
                    }
                    Text("Auto 优先 USB；Android USB 不可用时才尝试同一设备的 WiFi。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(controller.androidAdbStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DisclosureGroup("Android ADB 设置") {
                        TextField("ADB 路径（留空自动查找）",
                                  text: $controller.androidAdbPath)
                        Text("自动依次检查自定义路径、PATH、ANDROID_HOME、ANDROID_SDK_ROOT、用户 Android SDK 和 Homebrew。USB 调试授权代表设备信任当前 Mac。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Debug Stats", isOn: $controller.settings.enableDebugStats)
                    .onChange(of: controller.settings.enableDebugStats) { _, _ in controller.restartAll() }

                VStack(alignment: .leading, spacing: 4) {
                    Picker("显示位置", selection: $controller.presentation) {
                        ForEach(AppPresentation.allCases, id: \.self) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    if controller.presentation == .background {
                        Text("不会显示菜单栏或程序坞图标，串流会继续运行。需要打开此窗口时，请从 Spotlight 或 Finder 再次启动 DisplayWeave。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("显示器布局") {
                    Button("排列显示器…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
                .help("打开“系统设置”→“显示器”，你可以在那里调整扩展显示器相对 Mac 屏幕的位置。每台设备都会作为独立显示器出现，并使用设备名称。")

                Section("权限") {
                    permissionRow(
                        "屏幕录制",
                        granted: permissions.screenRecording,
                        help: "用于捕获显示器画面。",
                        anchor: "Privacy_ScreenCapture",
                        request: { permissions.requestScreenRecording() }
                    )
                    permissionRow(
                        "辅助功能",
                        granted: permissions.accessibility,
                        help: "用于接收设备上的触摸和滚动输入。",
                        anchor: "Privacy_Accessibility",
                        request: { permissions.requestAccessibility() }
                    )
                    // macOS offers no API to query Local Network access, so
                    // infer from discovery results and let the user check.
                    permissionRow(
                        "本地网络",
                        granted: !controller.discovered.isEmpty,
                        uncertain: controller.discovered.isEmpty,
                        help: "WiFi 模式需要此权限。如果设备列表为空，请在两端的“隐私与安全性”→“本地网络”中允许 DisplayWeave，并保持设备端 app 打开。",
                        anchor: "Privacy_LocalNetwork"
                    )
                }
            }
            .formStyle(.grouped)
            // Scrollable + fixed panel height: MenuBarExtra windows mis-measure
            // grouped Forms (clipping on small displays), so size explicitly
            // and let the form scroll when it doesn't fit.

            Divider()

            // Status bar
            HStack(spacing: 8) {
                Circle()
                    .fill(controller.running ? .green : .secondary.opacity(0.5))
                    .frame(width: 9, height: 9)
                Text(controller.running
                     ? "已连接 \(controller.sessions.count) 台设备"
                     : "空闲")
                    .font(.callout)
                    .lineLimit(1)
                Spacer()
                if let updater {
                    CheckForUpdatesView(updater: updater)
                }
                Button("退出") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 440, height: 540)
    }

    @ViewBuilder
    private func permissionRow(_ title: String, granted: Bool, uncertain: Bool = false,
                               help: String, anchor: String,
                               request: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: uncertain ? "questionmark.circle.fill"
                            : granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(uncertain ? .orange : granted ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if uncertain || !granted {
                    Text(help)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if uncertain || !granted {
                if let request {
                    Button("授权…") { request() }
                        .controlSize(.small)
                        .help("向 macOS 请求此权限。如果系统弹窗之前已被关闭，这会把 app 注册到系统设置里的对应权限项，请在那里打开开关。")
                }
                Button("打开设置") {
                    PermissionMonitor.openPrivacyPane(anchor)
                }
                .controlSize(.small)
            }
        }
    }
}

/// "Check for Updates…" button wired to Sparkle. Follows Sparkle 2's
/// documented SwiftUI pattern: a small view model publishes the updater's
/// `canCheckForUpdates` so the button disables itself while a check is
/// already running (or the updater isn't ready).
@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUStandardUpdaterController) {
        self.updater = updater.updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater.updater)
    }

    var body: some View {
        Button("检查更新…") { updater.checkForUpdates() }
            .controlSize(.small)
            .disabled(!viewModel.canCheckForUpdates)
    }
}

/// One connected device: live status, throughput, reconnect + disconnect.
struct SessionRow: View {
    let title: String
    @ObservedObject var session: DeviceSession
    let controller: SenderController

    private var statusColor: Color {
        if session.status.hasPrefix("正在扩展") || session.status.hasPrefix("正在镜像")
            || session.status.hasPrefix("已连接") {
            return .green
        }
        if session.status.hasPrefix("失败") || session.status.contains("已停止") {
            return .red
        }
        return .orange
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text("\(session.transportLabel) · \(session.status)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if session.mbps > 0 {
                Text("\(String(format: "%.1f", session.mbps)) Mbit/s")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Button {
                session.sender.forceReconnect()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.small)
            .help("断开当前连接并重新连接设备")
            Button("断开") { controller.disconnect(session) }
                .controlSize(.small)
        }
    }
}
