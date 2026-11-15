#!/usr/bin/env python3
"""Run the production MacSender load-update method with a controllable SCStream.

No screen capture, virtual displays, app preferences or real peers are used.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Mac/MacSender.swift').read_text()
start = source.index('    private func evaluateEncoderLoad(')
end = source.index('    private func logCaptureFpsIfLimited(', start)
method = source[start:end].replace('private func evaluateEncoderLoad', 'func evaluateEncoderLoad')

dec_start = source.index('    private static let decoderFpsAdjustmentTimeoutSeconds:')
dec_end = source.index('    private func scheduleProtocolTimeout(', dec_start)
decoder_methods = (
    source[dec_start:dec_end]
    .replace('private func clearDecoderFpsAdjustmentState', 'func clearDecoderFpsAdjustmentState')
    .replace('private func applySelectedDecoderFpsCap', 'func applySelectedDecoderFpsCap')
)
fixture = r'''
import Foundation
typealias SCStream = MockStream
typealias SCStreamConfiguration = EncoderLoadController.Configuration
final class MockStream: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    var failure = false
    func updateConfiguration(_ config: EncoderLoadController.Configuration) async throws {
        entered.signal()
        precondition(release.wait(timeout: .now() + 8) == .success)
        if failure { throw NSError(domain: "fixture", code: 1) }
    }
}
enum Log { static func info(_ s: String) {} }
enum DisplayUnitCoordinator { static func failure(_ s: String) -> Error { NSError(domain: s, code: 1) } }
final class Probe: @unchecked Sendable {
    let queue = DispatchQueue(label: "probe.state")
    var stopped = false, pipelineFailureReported = false, decoderFpsAdjustmentInFlight = false
    var decoderFpsAdjustmentID: UUID?
    var decoderFpsAdjustmentTask: Task<Void, Never>?
    var decoderFpsAdjustmentTimeoutWork: DispatchWorkItem?
    var decoderRecoveryEvent: String?
    var stream: MockStream? = MockStream()
    var settings = StreamSettings(fpsMode: .fps60, codecMode: .auto, quality: .high,
                                  transportMode: .auto, enableDebugStats: false)
    var encoderLoad: EncoderLoadController?
    var encoderLoadAdjustmentID: UUID?
    var encoderLoadAdjustmentTask: Task<Void, Never>?
    var pipelineEncodedFrames = 62, encoderDropsThisWindow = 28, encodeSubmissionCount = 62
    var encodeSubmissionMsTotal = 1550.0, pendingSends = 0, lastSendCompletionDelayMs = 0.2
    var captureFrames = CaptureFrameReplay<Int>()
    var activeStreamWidth = 4096, activeStreamHeight = 2304, requestedCaptureFps = 60
    var streamCodec = StreamCodec.hevc
    var setupFailure = false
    var setups: [EncoderLoadController.Configuration] = []
    var codecs: [StreamCodec] = []
    var configs = 0, keyframes = 0, failures = 0
    func cancelDropReplay() { captureFrames.submitted() }
    func makeCaptureConfiguration(width: Int, height: Int, fps: Int) -> EncoderLoadController.Configuration {
        .init(width: width, height: height, fps: fps)
    }
    func retireEncoder() {}
    func setupEncoder(width: Int, height: Int, fps: Int, preferredCodec: StreamCodec) throws {
        if setupFailure { throw NSError(domain: "encoder", code: 1) }
        setups.append(.init(width: width, height: height, fps: fps)); codecs.append(preferredCodec)
    }
    func sendStreamConfig(width: Int, height: Int) { configs += 1 }
    func requestKeyframe(_ reason: FrameDropReason) { keyframes += 1 }
    func failPipeline(_ error: Error) {
        clearDecoderFpsAdjustmentState()
        failures += 1
    }
    func begin() -> MockStream {
        queue.sync {
            var load = EncoderLoadController(configuration: .init(width: 4096, height: 2304, fps: 60), priority: .frameRate)
            let now = ProcessInfo.processInfo.systemUptime
            for time in [now - 4, now - 2] {
                _ = load.evaluate(.init(now: time, seconds: 2, captures: 88, outputs: 62, encoderDrops: 28,
                    submissions: 62, submissionMs: 25, pendingSends: 0, sendCompletionMs: 0.2))
            }
            encoderLoad = load
            _ = captureFrames.begin(); _ = captureFrames.offer(1, generation: captureFrames.generation)
            evaluateEncoderLoad(captures: 88, seconds: 2)
            return stream!
        }
    }
''' + method + '\n' + decoder_methods + r'''
}
@main struct Test {
    static func finish(_ probe: Probe) async {
        let task = probe.queue.sync { probe.encoderLoadAdjustmentTask }
        await task?.value
        probe.queue.sync {}
    }
    static func main() async {
        let success = Probe(), capture = success.begin()
        precondition(capture.entered.wait(timeout: .now() + 3) == .success)
        success.queue.sync {
            precondition(success.captureFrames.latest == nil, "old-size replay must be retired")
            success.streamCodec = .h264 // fallback while SCK suspends
        }
        capture.release.signal()
        await finish(success)
        success.queue.sync {
            precondition(success.setups == [.init(width: 3480, height: 1958, fps: 60)])
            precondition(success.codecs == [.h264] && success.configs == 1 && success.keyframes == 1)
            precondition(success.encoderLoadAdjustmentID == nil && success.failures == 0)
        }
        let stale = Probe(), old = stale.begin()
        precondition(old.entered.wait(timeout: .now() + 3) == .success)
        let replacement = UUID()
        stale.queue.sync {
            stale.stream = MockStream()
            stale.encoderLoadAdjustmentID = replacement
        }
        old.release.signal()
        await finish(stale)
        stale.queue.sync {
            precondition(stale.setups.isEmpty && stale.configs == 0 && stale.failures == 0)
            precondition(stale.encoderLoadAdjustmentID == replacement, "late completion cleared new owner")
        }
        for encoderFailure in [false, true] {
            let failure = Probe()
            failure.setupFailure = encoderFailure
            failure.stream!.failure = !encoderFailure
            let failing = failure.begin()
            precondition(failing.entered.wait(timeout: .now() + 3) == .success)
            failing.release.signal()
            await finish(failure)
            failure.queue.sync { precondition(failure.failures == 1 && failure.configs == 0) }
        }
        let stopped = Probe(), stoppedCapture = stopped.begin()
        precondition(stoppedCapture.entered.wait(timeout: .now() + 3) == .success)
        stopped.queue.sync { stopped.stopped = true }
        stoppedCapture.release.signal()
        await finish(stopped)
        stopped.queue.sync { precondition(stopped.setups.isEmpty && stopped.failures == 0) }
        let stalled = Probe(), stalledCapture = stalled.begin()
        let stalledTask = stalled.queue.sync { stalled.encoderLoadAdjustmentTask }
        precondition(stalledCapture.entered.wait(timeout: .now() + 3) == .success)
        let timeout = DispatchSemaphore(value: 0)
        stalled.queue.asyncAfter(deadline: .now() + 5.2) {
            precondition(stalled.failures == 1 && stalled.encoderLoadAdjustmentID == nil)
            timeout.signal()
        }
        precondition(timeout.wait(timeout: .now() + 7) == .success)
        stalledCapture.release.signal()
        await stalledTask?.value
        stalled.queue.sync { precondition(stalled.setups.isEmpty && stalled.failures == 1) }

        // Decoder FPS downgrade: normal success clears decoderFpsAdjustmentInFlight
        let decOk = Probe()
        let decStream = decOk.queue.sync { () -> MockStream in
            decOk.applySelectedDecoderFpsCap(30)
            precondition(decOk.decoderFpsAdjustmentInFlight && decOk.decoderFpsAdjustmentID != nil)
            return decOk.stream!
        }
        precondition(decStream.entered.wait(timeout: .now() + 3) == .success)
        decStream.release.signal()
        let decOkTask = decOk.queue.sync { decOk.decoderFpsAdjustmentTask }
        await decOkTask?.value
        decOk.queue.sync {}
        decOk.queue.sync {
            precondition(!decOk.decoderFpsAdjustmentInFlight && decOk.decoderFpsAdjustmentID == nil)
            precondition(decOk.requestedCaptureFps == 30 && decOk.configs == 1 && decOk.failures == 0)
        }

        // Decoder FPS downgrade: invalidateCapturePipeline / stop clears in-flight state & unblocks task immediately
        let decCancel = Probe()
        let decCancelStream = decCancel.queue.sync { () -> MockStream in
            decCancel.applySelectedDecoderFpsCap(30)
            precondition(decCancel.decoderFpsAdjustmentInFlight)
            return decCancel.stream!
        }
        precondition(decCancelStream.entered.wait(timeout: .now() + 3) == .success)
        let cancelTask = decCancel.queue.sync { () -> Task<Void, Never>? in
            let existing = decCancel.decoderFpsAdjustmentTask
            decCancel.stopped = true
            decCancel.clearDecoderFpsAdjustmentState()
            precondition(!decCancel.decoderFpsAdjustmentInFlight && decCancel.decoderFpsAdjustmentID == nil)
            return existing
        }
        await cancelTask?.value
        decCancelStream.release.signal()
        decCancel.queue.sync {
            precondition(!decCancel.decoderFpsAdjustmentInFlight && decCancel.failures == 0 && decCancel.configs == 0)
        }

        // Decoder FPS downgrade: 5-second timeout guard clears decoderFpsAdjustmentInFlight when SCStream hangs
        let decHung = Probe()
        let decHungStream = decHung.queue.sync { () -> MockStream in
            decHung.applySelectedDecoderFpsCap(30)
            precondition(decHung.decoderFpsAdjustmentInFlight)
            return decHung.stream!
        }
        let decHungTask = decHung.queue.sync { decHung.decoderFpsAdjustmentTask }
        precondition(decHungStream.entered.wait(timeout: .now() + 3) == .success)
        let decTimeout = DispatchSemaphore(value: 0)
        decHung.queue.asyncAfter(deadline: .now() + 5.2) {
            precondition(!decHung.decoderFpsAdjustmentInFlight && decHung.decoderFpsAdjustmentID == nil)
            precondition(decHung.failures == 1)
            decTimeout.signal()
        }
        precondition(decTimeout.wait(timeout: .now() + 7) == .success)
        await decHungTask?.value
        decHungStream.release.signal()

        print("Encoder load & decoder FPS cap integration PASS: current method, fallback, replacement, stop, SCK/encoder failures and 5s timeouts")
    }
}
'''
files = ['Mac/DesktopResolution.swift', 'Mac/FrameSizePolicy.swift', 'Mac/RefreshRatePolicy.swift',
         'Mac/StreamEncodingPolicy.swift', 'Mac/StreamSettings.swift', 'Mac/FrameDropPolicy.swift',
         'Mac/CaptureRecovery.swift', 'Mac/EncoderLoadController.swift']
with tempfile.TemporaryDirectory(prefix='displayweave-load-') as tmp:
    folder = Path(tmp)
    (folder / 'Fixture.swift').write_text(fixture)
    subprocess.run(['swiftc', *files, str(folder / 'Fixture.swift'), '-o', str(folder / 'test')], cwd=root, check=True)
    subprocess.run([str(folder / 'test')], check=True, timeout=30)
