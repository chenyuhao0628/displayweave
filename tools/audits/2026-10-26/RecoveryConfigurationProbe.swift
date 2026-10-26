// Snapshot reproducer: see docs/archive/audits/code-and-experience-audit-2026-10-26.md.
import Foundation
final class VirtualDisplay { let displayID: UInt32 = 1; let actualRefreshRate = 60 }
enum DisplayTopology { static func isOnline(_ id: UInt32) -> Bool { true } }
enum Log { static func info(_ value: String) {} }
final class RecoveryProbe {
    let queue = DispatchQueue(label: "review.recovery")
    let displayCoordinator: DisplayUnitCoordinator
    var stopped = false
    var stream: Int? = nil
    var releasedForRenumbering = false
    var consoleCanCapture = true
    var captureRecovery = CaptureRecoveryPolicy()
    var captureNeedsRebuild = false
    var virtualDisplay: VirtualDisplay? = VirtualDisplay()
    var activeStreamWidth = 1920
    var activeStreamHeight = 1080
    var requestedCaptureFps = 60
    var streamCodec = StreamCodec.h264
    var reattachedSize: (Int, Int)?
    var rebuilds = 0
    var failures = 0
    @MainActor init() { displayCoordinator = DisplayUnitCoordinator() }
    @MainActor func finishRetiredCapture() async {}
    func findSCDisplay(id: UInt32) async throws -> UInt32 { id }
    func startCapture(display: UInt32, pixelsWide: Int, pixelsHigh: Int, fps: Int,
                      virtualDisplayRefreshRate: Int, codec: StreamCodec) async throws {
        queue.sync { reattachedSize = (pixelsWide, pixelsHigh); stream = 1 }
    }
    func requestKeyframe(_ reason: FrameDropReason) -> Bool { true }
    func failPipeline(_ error: Error) { failures += 1 }
    @MainActor func reconfigureExclusive(_ info: PhoneInfo, recoveringCapture: Bool) async -> PhoneInfo? {
        rebuilds += 1; activeStreamWidth = info.pixelsWide; activeStreamHeight = info.pixelsHigh
        stream = 1; return info
    }
    @MainActor func recoverCapture(_ info: PhoneInfo) async -> PhoneInfo? {
        do {
            return try await displayCoordinator.exclusively {
                guard !self.stopped else { throw CancellationError() }
                await self.finishRetiredCapture()
                guard self.queue.sync(execute: { self.stream == nil && !self.releasedForRenumbering }) else { return info }
                guard self.consoleCanCapture else { return nil }
                self.queue.sync { self.captureRecovery.beginAttempt() }
                let existing = self.queue.sync { () -> (VirtualDisplay, Int, Int, Int, StreamCodec)? in
                    guard !self.captureNeedsRebuild, let vd = self.virtualDisplay, DisplayTopology.isOnline(vd.displayID),
                          self.activeStreamWidth > 0, self.activeStreamHeight > 0 else { return nil }
                    return (vd, self.activeStreamWidth, self.activeStreamHeight, self.requestedCaptureFps, self.streamCodec)
                }
                if let existing {
                    do {
                        Log.info("CAPTURE-RECOVERY reattaching to existing display; retaining negotiated raster/FPS")
                        let display = try await self.findSCDisplay(id: existing.0.displayID)
                        guard self.queue.sync(execute: { !self.stopped && self.virtualDisplay === existing.0 }) else { throw CancellationError() }
                        guard self.consoleCanCapture else { return nil }
                        try await self.startCapture(display: display, pixelsWide: existing.1, pixelsHigh: existing.2,
                            fps: existing.3, virtualDisplayRefreshRate: existing.0.actualRefreshRate, codec: existing.4)
                        self.queue.sync { _ = self.requestKeyframe(.streamReconfigure) }
                        return info
                    } catch {
                        if error is CancellationError || error is EncoderSessionFactory.Failure { throw error }
                        Log.info("CAPTURE-RECOVERY reattach failed: \(error); scheduling a display rebuild")
                        // Drop the local display reference before rebuilding.
                        // The next recovery round can release the owner safely.
                        self.queue.sync { self.captureNeedsRebuild = true }
                        return nil
                    }
                }
                return await self.reconfigureExclusive(info, recoveringCapture: true)
            }
        } catch {
            if !(error is CancellationError), !stopped { queue.async { self.failPipeline(error) } }
            return nil
        }
    }

}
@main struct RecoveryConfigurationProbe {
    @MainActor static func main() async throws {
        let hello = try JSONDecoder().decode(PhoneInfo.self, from: Data(#"{"pixelsWide":1080,"pixelsHigh":1920,"scale":2,"device":"iPhone","id":"review-fixture"}"#.utf8))
        let sender = RecoveryProbe()
        let applied = await sender.recoverCapture(hello)
        let matched = applied?.sameDisplayConfiguration(as: hello) ?? false
        let size = sender.reattachedSize!
        print("New hello: \(hello.pixelsWide)x\(hello.pixelsHigh)")
        print("Actual reattached capture: \(size.0)x\(size.1), display rebuilds: \(sender.rebuilds)")
        print("Completion considers latest configuration applied: \(matched)")
        precondition(matched && size.0 == 1920 && size.1 == 1080 && sender.rebuilds == 0)
    }
}
