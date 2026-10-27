#!/usr/bin/env python3
"""Exercise the current sender display-change method with controlled OS state."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "Mac/MacSender.swift").read_text()
begin = source.index("    @MainActor\n    private func updateAutomaticDesktop() -> Bool {")
end = source.index("    @MainActor\n    private func reconfigure(", begin)
method = source[begin:end].replace("private func updateAutomaticDesktop()", "func updateAutomaticDesktop()")
begin = source.index("    private func scheduleReconfiguration(")
end = source.index("    // MARK: - Connection (with retry)", begin)
completion_method = source[begin:end].replace("private func scheduleReconfiguration(", "func scheduleReconfiguration(")
fixture = r'''
import Foundation
import CoreGraphics

enum CaptureMode { case mirror, extend }
enum Log { static func info(_ value: String) {} }
final class VirtualDisplay {
    let pointsWide: Int
    let pointsHigh: Int
    let backingScale: Int
    init(_ width: Int, _ height: Int, _ scale: Int) {
        pointsWide = width; pointsHigh = height; backingScale = scale
    }
}
@MainActor enum DesktopMatchDisplays {
    static var selected: DesktopMatchReference?
    static var duringLookup: (() -> Void)?
    static func reference(for device: String) -> DesktopMatchReference? {
        duringLookup?()
        return selected
    }
}
final class Probe {
    let queue = DispatchQueue(label: "desktop-match-test")
    let displaySerial: UInt32 = 1
    var stopped = false
    var mode = CaptureMode.extend
    var pipelineFailureReported = false
    var releasedForRenumbering = false
    var stream: Int? = 1
    var reconfigurationTask: Int?
    var consoleCanCapture = true
    var lastHello: PhoneInfo?
    var virtualDisplay: VirtualDisplay?
    var settings = StreamSettings(fpsMode: .auto, codecMode: .auto, quality: .high,
                                  transportMode: .auto, enableDebugStats: false)
    var onDesktopGeometry: ((DesktopGeometry, String?) -> Void)?
    var rebuilds = 0
    init(_ info: PhoneInfo) {
        lastHello = info
        virtualDisplay = VirtualDisplay(2048, 1152, 2)
        settings.desktopResolutions.set(.automatic, for: "A")
    }
    static func automaticMatchNote(_ match: DesktopMatchResult?, reference: DesktopMatchReference?) -> String {
        "updated"
    }
    func scheduleReconfiguration() { rebuilds += 1; reconfigurationTask = rebuilds }
'''
fixture += method + r'''
}

@MainActor final class CompletionMonitor {
    var checks = 0
    func reconsider() { checks += 1 }
}
struct CompletionRecovery {
    func finished(succeeded: Bool, consoleAvailable: Bool) {}
}
final class CompletionProbe: @unchecked Sendable {
    let queue = DispatchQueue(label: "desktop-match-completion-test")
    var stopped = false
    var pipelineFailureReported = false
    var releasedForRenumbering = false
    var reconfigurationTask: Task<Void, Never>?
    var reconfigurationID: UUID?
    var lastHello: PhoneInfo?
    var stream: Int? = 1
    var captureNeedsRebuild = true
    var captureRecovery = CompletionRecovery()
    var consoleCanCapture = true
    @MainActor var desktopMatchMonitor: CompletionMonitor?

    init(_ info: PhoneInfo) { lastHello = info }
    @MainActor func reconfigure(_ info: PhoneInfo) async -> PhoneInfo? {
        try? await Task.sleep(for: .milliseconds(50))
        return info
    }
    @MainActor func recoverCapture(_ info: PhoneInfo) async -> PhoneInfo? { await reconfigure(info) }
    func scheduleCaptureRecovery() {}
'''
fixture += completion_method + r'''
}

@main struct DesktopUpdateRegression {
    @MainActor static func main() async throws {
        func hello(_ id: String, _ width: Int = 5120, _ height: Int = 2880) throws -> PhoneInfo {
            let json = #"{"pixelsWide":\#(width),"pixelsHigh":\#(height),"scale":2,"device":"Mac","id":"\#(id)"}"#
            return try JSONDecoder().decode(PhoneInfo.self, from: Data(json.utf8))
        }
        func reference(_ width: Int) -> DesktopMatchReference {
            DesktopMatchReference(id: 1, bounds: CGRect(x: 0, y: 0, width: width, height: width * 9 / 16),
                isMain: true, isBuiltIn: true, eligible: true, physicalSize: nil)
        }
        let info = try hello("A")
        let stable = Probe(info)
        DesktopMatchDisplays.selected = reference(2048)
        var notes = 0
        stable.onDesktopGeometry = { _, _ in notes += 1 }
        precondition(!stable.updateAutomaticDesktop() && stable.rebuilds == 0 && notes == 1)
        DesktopMatchDisplays.selected = nil
        precondition(!stable.updateAutomaticDesktop() && stable.rebuilds == 0,
                     "a temporarily missing reference must not rebuild the desktop")
        DesktopMatchDisplays.selected = reference(2560)
        let other = Probe(info)
        precondition(stable.updateAutomaticDesktop() && stable.rebuilds == 1 && other.rebuilds == 0)
        precondition(!stable.updateAutomaticDesktop() && stable.rebuilds == 1,
                     "an in-flight rebuild must not be duplicated")
        let stopped = Probe(info)
        stopped.stopped = true
        precondition(!stopped.updateAutomaticDesktop() && stopped.rebuilds == 0)
        let sleeping = Probe(info)
        sleeping.consoleCanCapture = false
        precondition(!sleeping.updateAutomaticDesktop() && sleeping.rebuilds == 0)
        let native = Probe(info)
        native.settings.desktopResolutions.set(.native, for: "A")
        precondition(!native.updateAutomaticDesktop() && native.rebuilds == 0)
        let replaced = Probe(info)
        DesktopMatchDisplays.duringLookup = {
            replaced.queue.sync { replaced.virtualDisplay = VirtualDisplay(2048, 1152, 2) }
        }
        precondition(!replaced.updateAutomaticDesktop() && replaced.rebuilds == 0,
                     "a stale callback must not rebuild a replacement display")
        let staleNote = Probe(info)
        var staleNotes = 0
        staleNote.onDesktopGeometry = { _, _ in staleNotes += 1 }
        DesktopMatchDisplays.selected = reference(2048)
        DesktopMatchDisplays.duringLookup = {
            staleNote.queue.sync { staleNote.virtualDisplay = VirtualDisplay(2048, 1152, 2) }
        }
        precondition(!staleNote.updateAutomaticDesktop() && staleNotes == 0,
                     "a stale unchanged-geometry callback must not publish state")
        DesktopMatchDisplays.selected = reference(2560)
        let changedHello = Probe(info)
        let rotated = try hello("A", 2880, 5120)
        DesktopMatchDisplays.duringLookup = { changedHello.queue.sync { changedHello.lastHello = rotated } }
        precondition(!changedHello.updateAutomaticDesktop() && changedHello.rebuilds == 0,
                     "a stale callback must not rebuild after a new receiver configuration")
        DesktopMatchDisplays.duringLookup = nil

        let completed = CompletionProbe(info)
        let monitor = CompletionMonitor()
        completed.desktopMatchMonitor = monitor
        completed.queue.sync { completed.scheduleReconfiguration() }
        for _ in 0..<100 {
            if monitor.checks == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(monitor.checks == 1, "a completed rebuild must reconsider screen changes received while busy")
        let retired = CompletionProbe(info)
        let retiredMonitor = CompletionMonitor()
        retired.desktopMatchMonitor = retiredMonitor
        retired.queue.sync {
            retired.scheduleReconfiguration()
            retired.stopped = true
        }
        try await Task.sleep(for: .milliseconds(150))
        precondition(retiredMonitor.checks == 0, "a retired session must not schedule matching")
        print("Desktop match update PASS: no-op, missing display, isolation, stale state and rebuild completion")
    }
}
'''
files = [
    "Mac/DesktopResolution.swift", "Mac/FrameSizePolicy.swift", "Mac/RefreshRatePolicy.swift",
    "Mac/StreamEncodingPolicy.swift", "Mac/StreamSettings.swift", "Mac/DeviceCapabilities.swift",
    "Mac/Receiver/ReceiverWireProtocol.swift", "Mac/MacReceiverPolicy.swift",
]
with tempfile.TemporaryDirectory(prefix="displayweave-desktop-update-") as temporary:
    path = Path(temporary)
    (path / "Fixture.swift").write_text(fixture)
    subprocess.run(["swiftc", *files, str(path / "Fixture.swift"), "-o", str(path / "test")],
                   cwd=root, check=True)
    subprocess.run([str(path / "test")], check=True, timeout=10)
