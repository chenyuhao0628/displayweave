import AppKit
import AVFoundation
import Combine

@MainActor
final class MacReceiverController: NSObject, ObservableObject, NSWindowDelegate {
    let receiver: StreamReceiver
    @Published private(set) var enabled = false
    @Published private(set) var screens: [NSScreen] = []
    @Published var selectedDisplayID: UInt32 = UserDefaults.standard.object(forKey: "receiverDisplayID") as? UInt32 ?? 0
    @Published var fullscreen = UserDefaults.standard.bool(forKey: "receiverFullscreen")
    @Published var name = UserDefaults.standard.string(forKey: "receiverName") ?? (Host.current().localizedName ?? "DisplayWeave Mac")
    private let port: UInt16
    private let advertiseService: Bool
    private var window: NSWindow?
    private var videoView: ReceiverVideoView!
    private var subscriptions = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var activity: NSObjectProtocol?
    private var sleeping = false
    private var closingWindow = false
    private var movingFullscreenWindow = false

    init(port: UInt16 = 9000, advertiseService: Bool = true,
         securityProvider: @escaping () throws -> AppleReceiverSecurity = { try .live(localID: StreamReceiver.installID) }) {
        receiver = StreamReceiver(securityProvider: securityProvider)
        self.port = port
        self.advertiseService = advertiseService
        super.init()
        videoView = ReceiverVideoView(receiver: receiver)
        refreshScreens()
        receiver.$connected.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] connected in
            guard let self else { return }
            if connected && self.enabled && !self.sleeping {
                self.showVideo()
                self.activity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled], reason: "DisplayWeave 接收显示")
            } else {
                if let activity = self.activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
                self.hideVideo()
            }
        }.store(in: &subscriptions)
        $selectedDisplayID.dropFirst().removeDuplicates().sink { [weak self] value in
            UserDefaults.standard.set(value, forKey: "receiverDisplayID")
            DispatchQueue.main.async { self?.updatePanel(); self?.placeWindow() }
        }.store(in: &subscriptions)
        $name.dropFirst().debounce(for: .milliseconds(300), scheduler: DispatchQueue.main).sink { [weak self] value in
            UserDefaults.standard.set(value, forKey: "receiverName")
            self?.updatePanel()
        }.store(in: &subscriptions)
        $fullscreen.dropFirst().removeDuplicates().sink { [weak self] value in
            UserDefaults.standard.set(value, forKey: "receiverFullscreen")
            DispatchQueue.main.async { self?.applyFullscreen() }
        }.store(in: &subscriptions)
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refreshScreens(); self?.updatePanel(); self?.placeWindow() } })
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.sleeping = true
                self.receiver.stop(announcing: "sleeping")
                self.hideVideo()
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.sleeping = false
                if self.enabled { self.updatePanel(); self.receiver.start(port: self.port, advertiseService: self.advertiseService) }
            }
        })
    }

    static func id(_ screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private var selectedScreen: NSScreen? {
        screens.first { Self.id($0) == selectedDisplayID } ?? screens.first
    }

    private func refreshScreens() {
        screens = NSScreen.screens
        if !screens.contains(where: { Self.id($0) == selectedDisplayID }) {
            selectedDisplayID = screens.first.map(Self.id) ?? 0
        }
    }

    private func updatePanel() {
        guard let screen = selectedScreen else { return }
        let scale = screen.backingScaleFactor
        // Keep the notch outside the advertised usable desktop rectangle.
        let size = CGSize(width: screen.frame.width, height: screen.frame.height - screen.safeAreaInsets.top)
        receiver.configure(panel: PanelAnnouncement(pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            scale: scale, pointsWide: Int(size.width), pointsHigh: Int(size.height)), name: name,
            maxFps: AppleVideoPolicy.frameRate(maximum: screen.maximumFramesPerSecond))
    }

    func start() {
        guard !enabled else { return }
        enabled = true
        updatePanel()
        if !sleeping { receiver.start(port: port, advertiseService: advertiseService) }
    }

    func stop(completion: (() -> Void)? = nil) {
        enabled = false
        hideVideo()
        receiver.stop(completion: completion)
    }

    func showVideo() {
        guard enabled, !sleeping else { return }
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "DisplayWeave · 接收画面（在发送端操作）"
            window.contentView = videoView
            window.contentMinSize = NSSize(width: 320, height: 200)
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.fullScreenPrimary]
            window.delegate = self
            self.window = window
            placeWindow()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        applyFullscreen()
    }

    private func placeWindow() {
        guard let screen = selectedScreen, let window else { return }
        if window.styleMask.contains(.fullScreen) {
            guard window.screen.map(Self.id) != Self.id(screen), !movingFullscreenWindow else { return }
            movingFullscreenWindow = true
            window.toggleFullScreen(nil)
            return
        }
        let frame = screen.visibleFrame
        let width = min(960, frame.width * 0.85), height = min(600, frame.height * 0.85)
        window.setFrame(NSRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height), display: true)
    }

    private func applyFullscreen() {
        guard let window, window.isVisible else { return }
        if window.styleMask.contains(.fullScreen) != fullscreen { window.toggleFullScreen(nil) }
    }

    private func hideVideo() {
        guard let window else { return }
        closingWindow = true
        movingFullscreenWindow = false
        window.close()
        closingWindow = false
        self.window = nil
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        if !closingWindow { receiver.disconnect(); window = nil }
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === window, !closingWindow else { return }
        if !fullscreen { fullscreen = true }
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === window, !closingWindow else { return }
        if movingFullscreenWindow {
            movingFullscreenWindow = false
            placeWindow()
            applyFullscreen()
        } else if fullscreen { fullscreen = false }
    }
}
