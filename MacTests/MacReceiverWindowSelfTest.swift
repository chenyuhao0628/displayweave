import AppKit
import Foundation

/// Opt-in AppKit integration test, outside the headless CI policy suite.
@main struct MacReceiverWindowSelfTest {
    @MainActor static func waitFor(_ detail: String, _ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ReceiverTestFailure(message: "window test timeout: \(detail)")
    }

    @MainActor static func run() async throws {
        let controller = MacReceiverController(port: 0, advertiseService: false)
        controller.fullscreen = false
        controller.start()
        let receiver = controller.receiver
        try await waitFor("listen") { receiver.listeningPort > 0 }
        let port = receiver.listeningPort
        let peer = try await Task.detached { () -> ReceiverTestPeer in
            let peer = try ReceiverTestPeer(port: port)
            _ = try peer.hello()
            try peer.write(ReceiverFrameDecoder.frame(try receiverTestH264Frame()))
            return peer
        }.value
        try await waitFor("video window") { NSApp.windows.contains { $0.isVisible && $0.contentView is ReceiverVideoView } }
        let window = NSApp.windows.first { $0.isVisible && $0.contentView is ReceiverVideoView }!
        precondition(receiver.connected)
        let keepalive = Task.detached {
            let ping = ReceiverFrameDecoder.frame(Data(#"{"type":"ping","t":0}"#.utf8))
            while !Task.isCancelled {
                try? peer.write(ping)
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        defer { keepalive.cancel() }
        var enteredFullscreen = false, exitedFullscreen = false
        let entered = NotificationCenter.default.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { _ in enteredFullscreen = true }
        let exited = NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { _ in exitedFullscreen = true }
        defer { NotificationCenter.default.removeObserver(entered); NotificationCenter.default.removeObserver(exited) }
        controller.fullscreen = true
        try await waitFor("enter fullscreen") { enteredFullscreen }
        controller.fullscreen = false
        try await waitFor("exit fullscreen") { exitedFullscreen }
        window.performClose(nil)
        try await waitFor("window close ends session") { !receiver.connected }
        precondition(receiver.listeningPort == port && controller.enabled)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await waitFor("sleep releases listener") { receiver.listeningPort == 0 }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await waitFor("wake listens") { receiver.listeningPort > 0 }
        await withCheckedContinuation { continuation in controller.stop { continuation.resume() } }
        precondition(!controller.enabled && !receiver.connected && receiver.listeningPort == 0)
        precondition(!NSApp.windows.contains { $0.isVisible && $0.contentView is ReceiverVideoView })
        withExtendedLifetime(peer) {}
        print("Mac AppKit window open/close, fullscreen, sleep/wake notifications, listener cleanup PASS")
    }

    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do { try await run(); exit(0) }
            catch { print("FAIL: \(error)"); exit(1) }
        }
        app.run()
    }
}
