import SwiftUI
import Network

/// How the app presents itself. One bundle, switched at runtime via the
/// activation policy — like Raycast/Hammerspoon style background agents.
enum AppPresentation: String, CaseIterable {
    case menuBar, dock, background

    var label: String {
        switch self {
        case .menuBar: return "Menu bar"
        case .dock: return "Dock"
        case .background: return "Background only"
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
            ContentView(controller: controller)
        } label: {
            Image(systemName: controller.running
                  ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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

    static func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 540),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            w.title = "OpenSidecar"
            w.contentView = NSHostingView(
                rootView: ContentView(controller: SenderController.shared))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum ConnectionTarget: Hashable {
    case usb                          // iproxy tunnel on localhost
    case wifi(NWBrowser.Result)       // discovered via Bonjour

    var label: String {
        switch self {
        case .usb:
            return "USB (wired)"
        case .wifi(let result):
            if case .service(let name, _, _, _) = result.endpoint { return "\(name) (WiFi)" }
            return "WiFi device"
        }
    }
}

@MainActor
final class SenderController: ObservableObject {
    static let shared = SenderController()

    @Published var presentation = AppPresentation(
        rawValue: UserDefaults.standard.string(forKey: "presentation") ?? "") ?? .menuBar {
        didSet {
            UserDefaults.standard.set(presentation.rawValue, forKey: "presentation")
            NSApp.setActivationPolicy(presentation == .dock ? .regular : .accessory)
            // Never strand the user without UI: leaving menu-bar mode opens
            // the window immediately.
            if presentation != .menuBar { MainWindow.show() }
        }
    }

    @Published var status = "Idle"
    @Published var framesSent = 0
    @Published var mbps = 0.0
    @Published var running = false
    @Published var discovered: [NWBrowser.Result] = []
    @Published var target: ConnectionTarget = .usb
    // `-host x.x.x.x` / `-port n` override the USB tunnel endpoint.
    @Published var host = UserDefaults.standard.string(forKey: "host") ?? "127.0.0.1"
    @Published var port = UserDefaults.standard.string(forKey: "port") ?? "9000"
    // `-mode mirror` / `-mode extend` launch argument also works.
    @Published var mode = CaptureMode(rawValue: UserDefaults.standard.string(forKey: "mode") ?? "") ?? .extend
    @Published var quality = StreamQuality(rawValue: UserDefaults.standard.string(forKey: "quality") ?? "") ?? .best {
        didSet { UserDefaults.standard.set(quality.rawValue, forKey: "quality") }
    }

    private var sender: MacSender?
    private var browser: NWBrowser?

    init() {
        startBrowsing()
        // Auto-start unless explicitly disabled (`-autostart NO`).
        if UserDefaults.standard.object(forKey: "autostart") == nil
            || UserDefaults.standard.bool(forKey: "autostart") {
            start()
        }
    }

    private func startBrowsing() {
        let browser = NWBrowser(for: .bonjour(type: "_opensidecar._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.discovered = Array(results)
                self.reselectSavedTarget()
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    /// The connection choice survives relaunches: if the user last used a
    /// WiFi device, re-select it as soon as discovery finds it again.
    private func reselectSavedTarget() {
        guard case .usb = target,
              let saved = UserDefaults.standard.string(forKey: "lastTarget"),
              saved != "usb" else { return }
        for result in discovered {
            if case .service(let name, _, _, _) = result.endpoint, name == saved {
                target = .wifi(result)
                restartIfRunning()
                return
            }
        }
    }

    func rememberTarget() {
        switch target {
        case .usb:
            UserDefaults.standard.set("usb", forKey: "lastTarget")
        case .wifi(let result):
            if case .service(let name, _, _, _) = result.endpoint {
                UserDefaults.standard.set(name, forKey: "lastTarget")
            }
        }
    }

    func start() {
        guard !running else { return }
        let endpoint: NWEndpoint
        switch target {
        case .usb:
            guard let portNum = UInt16(port) else { return }
            endpoint = .hostPort(host: NWEndpoint.Host(host),
                                 port: NWEndpoint.Port(rawValue: portNum)!)
        case .wifi(let result):
            endpoint = result.endpoint
        }

        running = true
        status = "Starting…"
        let sender = MacSender(endpoint: endpoint, name: target.label, mode: mode, quality: quality)
        sender.onStatus = { [weak self] text in
            self?.status = text
            Log.info("status: \(text)")
        }
        sender.onStats = { [weak self] frames, mbps in
            self?.framesSent = frames
            self?.mbps = mbps
        }
        sender.onDisconnected = { [weak self] in
            // Device unplugged / left the network and stayed gone: end the
            // session fully (virtual display + capture + indicator) rather
            // than dialing forever or silently switching transports.
            Log.info("device disconnected — session stopped")
            self?.stop()
            self?.status = "Disconnected — session stopped"
        }
        self.sender = sender
        Task {
            do {
                try await sender.start()
            } catch is CancellationError {
                // stopped by the user while waiting — nothing to report
            } catch {
                Log.info("sender failed to start: \(error)")
                self.status = "Failed: \(error.localizedDescription)"
                self.running = false
            }
        }
    }

    func stop() {
        sender?.stop()
        sender = nil
        running = false
        status = "Stopped"
    }

    func reconnect() {
        sender?.forceReconnect()
    }

    func restartIfRunning() {
        if running {
            stop()
            start()
        }
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

    static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct ContentView: View {
    @ObservedObject var controller: SenderController
    @StateObject private var permissions = PermissionMonitor()

    private var statusColor: Color {
        if !controller.running { return .secondary.opacity(0.5) }
        if controller.status.hasPrefix("Extending") || controller.status.hasPrefix("Mirroring") {
            return .green
        }
        if controller.status.hasPrefix("Failed") || controller.status.contains("stopped") {
            return .red
        }
        return .orange
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenSidecar")
                        .font(.title3.bold())
                    Text("Your iPad or iPhone as a second display")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if controller.running {
                    Button {
                        controller.reconnect()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .controlSize(.large)
                    .help("Drop the connection and pair with the device again")
                }
                Button(controller.running ? "Stop" : "Start") {
                    controller.running ? controller.stop() : controller.start()
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            // Settings
            Form {
                Picker("Connection", selection: $controller.target) {
                    Text(ConnectionTarget.usb.label).tag(ConnectionTarget.usb)
                    ForEach(controller.discovered, id: \.self) { result in
                        Text(ConnectionTarget.wifi(result).label)
                            .tag(ConnectionTarget.wifi(result))
                    }
                }
                .onChange(of: controller.target) {
                    controller.rememberTarget()
                    controller.restartIfRunning()
                }

                Picker("Mode", selection: $controller.mode) {
                    Text("Extend").tag(CaptureMode.extend)
                    Text("Mirror").tag(CaptureMode.mirror)
                }
                .pickerStyle(.segmented)
                .onChange(of: controller.mode) { controller.restartIfRunning() }

                VStack(alignment: .leading, spacing: 4) {
                    Picker("Quality", selection: $controller.quality) {
                        ForEach(StreamQuality.allCases, id: \.self) { q in
                            Text(q.label).tag(q)
                        }
                    }
                    .onChange(of: controller.quality) { controller.restartIfRunning() }
                    Text(controller.quality.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Picker("Show app in", selection: $controller.presentation) {
                        ForEach(AppPresentation.allCases, id: \.self) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    if controller.presentation == .background {
                        Text("No menu bar or Dock icon — streaming keeps running. Open the OpenSidecar app again (Spotlight/Finder) to show this window.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Display layout") {
                    Button("Arrange Displays…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
                .help("Opens System Settings → Displays, where you can position the extended display relative to your Mac screen (Arrange…).")

                Section("Permissions") {
                    permissionRow(
                        "Screen Recording",
                        granted: permissions.screenRecording,
                        help: "Required to capture the display.",
                        anchor: "Privacy_ScreenCapture"
                    )
                    permissionRow(
                        "Accessibility",
                        granted: permissions.accessibility,
                        help: "Required for touch input from the device.",
                        anchor: "Privacy_Accessibility"
                    )
                    // macOS offers no API to query Local Network access, so
                    // infer from discovery results and let the user check.
                    permissionRow(
                        "Local Network",
                        granted: !controller.discovered.isEmpty,
                        uncertain: controller.discovered.isEmpty,
                        help: "Required for WiFi mode. If no device appears in the Connection menu, allow OpenSidecar under Privacy & Security → Local Network on this Mac AND on the device — and keep the OpenSidecar app open there.",
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
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                Text(controller.status)
                    .font(.callout)
                    .lineLimit(1)
                Spacer()
                if controller.running, controller.mbps > 0 {
                    Text("\(String(format: "%.1f", controller.mbps)) Mbit/s")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Button("Quit") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 440, height: 540)
    }

    @ViewBuilder
    private func permissionRow(_ title: String, granted: Bool, uncertain: Bool = false,
                               help: String, anchor: String) -> some View {
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
                Button("Open Settings") {
                    PermissionMonitor.openPrivacyPane(anchor)
                }
                .controlSize(.small)
            }
        }
    }
}
