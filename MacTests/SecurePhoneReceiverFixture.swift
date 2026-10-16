// Compiled only by tools/test-secure-ios-receiver.py into a disposable simulator
// application. The production app contains no file-command or token-export hook.
import SwiftUI
import AVFoundation

@MainActor private final class PhoneFixture: ObservableObject {
    let receiver = PhoneReceiver(displayLayer: AVSampleBufferDisplayLayer())
    private let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private let port = UInt16(UserDefaults.standard.integer(forKey: "testPort"))
    private var started = false

    func start() {
        guard !started else { return }
        started = true
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

    func tick() {
        let command = folder.appendingPathComponent("command.txt")
        if let data = try? Data(contentsOf: command), data.count < 64 {
            try? FileManager.default.removeItem(at: command)
            if String(decoding: data, as: UTF8.self) == "revoke" {
                AppleTransportSecurityModel.shared.refresh()
                for peer in AppleTransportSecurityModel.shared.peers { AppleTransportSecurityModel.shared.revoke(peer.installID) }
            }
        }
        let state: [String: Any] = ["connected": receiver.connected, "encrypted": receiver.encrypted,
                                   "width": receiver.videoSize.width, "height": receiver.videoSize.height]
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
    @Environment(\.scenePhase) private var scenePhase
    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    var body: some View {
            Form { TransportSecuritySettings() }
                .onAppear { fixture.start() }
                .onReceive(timer) { _ in fixture.tick() }
                .onChange(of: scenePhase) { _, phase in fixture.phase(phase) }
    }
}
