// Compiled only by tools/test-secure-ios-receiver.py into a disposable simulator
// application. The production app contains no file-command or token-export hook.
import SwiftUI
import AVFoundation

let deviceKind = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
let macAppURL = URL(string: "https://github.com/chenyuhao0628/displayweave")!

@MainActor private final class PhoneFixture: ObservableObject {
    @Published var surface = "security"
    let receiver = PhoneReceiver(displayLayer: AVSampleBufferDisplayLayer())
    private let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private let port = UInt16(UserDefaults.standard.integer(forKey: "testPort"))
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        do { try checkPresentationReplacement() }
        catch {
            try? Data(error.localizedDescription.utf8).write(to: folder.appendingPathComponent("error.txt"))
            return
        }
        receiver.setNativePanel(long: 1920, short: 1080, scale: 1)
        receiver.start(port: port)
        AppleTransportSecurityModel.shared.openPairing()
        do {
            let invitation = Data(AppleTransportSecurityModel.shared.invitation.utf8)
            guard !invitation.isEmpty else { throw TransportSecurityError.failed("fixture identity unavailable") }
            let file = folder.appendingPathComponent("invitation.txt")
            try invitation.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch { try? Data(error.localizedDescription.utf8).write(to: folder.appendingPathComponent("error.txt")) }
    }

    private func checkPresentationReplacement() throws {
        func expect(_ value: Bool, _ message: String) throws {
            if !value { throw TransportSecurityError.failed(message) }
        }
        let layer = AVSampleBufferDisplayLayer()
        let old = VideoLayerView(displayLayer: layer, receiver: receiver, useMetal: false).makeVideoView()
        let replacement = VideoLayerView(displayLayer: layer, receiver: receiver, useMetal: false).makeVideoView()
        try expect(old.receiver == nil, "replaced view still owns input receiver")
        var resets = 0, tools = 0
        receiver.onInputReset = { resets += 1 }
        receiver.onPencilToolChange = { tools += 1 }
        VideoLayerView.dismantleUIView(old, coordinator: ())
        receiver.onInputReset?(); receiver.onPencilToolChange?()
        try expect(resets == 1 && tools == 1 && replacement.receiver === receiver,
                   "late old-view teardown cleared replacement callbacks")
        try expect(layer.superlayer === replacement.layer, "old teardown detached the new video layer")
        VideoLayerView.dismantleUIView(replacement, coordinator: ())
        try expect(receiver.onInputReset == nil && receiver.onPencilToolChange == nil &&
                   receiver.onCursor == nil && receiver.onCursorImage == nil && receiver.onDecodedFrame == nil,
                   "current view teardown retained callbacks")
        try expect(replacement.receiver == nil && layer.superlayer == nil, "current view retained its receiver/layer")
        try Data("iOS presentation replacement, late teardown and callback cleanup PASS".utf8)
            .write(to: folder.appendingPathComponent("presentation-result.txt"))
    }

    func tick() {
        let command = folder.appendingPathComponent("command.txt")
        if let data = try? Data(contentsOf: command), data.count < 64 {
            try? FileManager.default.removeItem(at: command)
            if String(decoding: data, as: UTF8.self).hasPrefix("ui-") {
                surface = String(String(decoding: data, as: UTF8.self).dropFirst(3))
            } else if String(decoding: data, as: UTF8.self) == "revoke" {
                AppleTransportSecurityModel.shared.refresh()
                for peer in AppleTransportSecurityModel.shared.peers { AppleTransportSecurityModel.shared.revoke(peer.installID) }
            } else if String(decoding: data, as: UTF8.self) == "pencil" {
                let generation = receiver.inputGeneration
                receiver.selectPencilTool(.eraser)
                let sample = PencilSample(phase: .down, x: 0.5, y: 0.5, pressure: 0.5,
                    azimuth: 0, altitude: .pi / 2, roll: .pi / 2, tool: .eraser)!
                receiver.sendPencil(sample, generation: generation)
                receiver.sendPencil(sample.cancelled, generation: generation)
                receiver.sendPencilAction(.undo, generation: generation)
                receiver.sendTouch(phase: "moved", x: 0.123, y: 0.456, generation: generation)
            }
        }
        let state: [String: Any] = ["connected": receiver.connected, "encrypted": receiver.encrypted,
                                   "width": receiver.videoSize.width, "height": receiver.videoSize.height,
                                   "pencil2": receiver.pencilExtendedAvailable, "shortcuts": receiver.pencilShortcutsAvailable]
        if let data = try? JSONSerialization.data(withJSONObject: state) {
            try? data.write(to: folder.appendingPathComponent("state.json"), options: .atomic)
        }
    }
    func phase(_ phase: ScenePhase) {
        let state: ReceiverSceneState = phase == .active ? .active : phase == .background ? .background : .inactive
        try? Data(String(describing: state).utf8).write(to: folder.appendingPathComponent("phase.txt"), options: .atomic)
        switch ReceiverSceneLifecyclePolicy.action(for: state) {
        case .startListening: receiver.ensureListening()
        case .stopListening: receiver.stop()
        case .none: break
        }
    }
}

@main struct SecurePhoneReceiverFixture: App {
    @StateObject private var fixture = PhoneFixture()
    var body: some Scene {
        WindowGroup { PhoneFixtureView(fixture: fixture) }
    }
}

private struct PhoneFixtureView: View {
    @ObservedObject var fixture: PhoneFixture
    @State private var showSettings = false
    @Environment(\.scenePhase) private var scenePhase
    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    var body: some View {
            Group {
                switch fixture.surface {
                case "idle": IdleView(receiver: fixture.receiver, showSettings: $showSettings)
                case "onboarding": OnboardingView(onClose: {})
                case "settings": SettingsView(receiver: fixture.receiver)
                default: Form { PencilSettingsSection(receiver: fixture.receiver); TransportSecuritySettings() }
                }
            }
                .sheet(isPresented: $showSettings) { SettingsView(receiver: fixture.receiver) }
                .onAppear { fixture.start() }
                .onReceive(timer) { _ in fixture.tick() }
                .onChange(of: scenePhase) { _, phase in fixture.phase(phase) }
    }
}
