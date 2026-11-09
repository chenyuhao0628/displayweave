#!/usr/bin/env python3
"""Execute current iOS admission with a stub layer; no driver performance claim."""
from pathlib import Path
import argparse
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--source-ref")
args = parser.parse_args()
source = (subprocess.check_output(["git", "show", f"{args.source_ref}:iOS/PhoneReceiver.swift"], cwd=root).decode()
          if args.source_ref else (root / "iOS/PhoneReceiver.swift").read_text())
start = source.index("        if displayLayer.status == .failed { failVideo(); return }")
end = source.index("        let metadata = packet.metadata", start)
snapshot = (root / "tools/audits/2026-10-26/IOSBackpressureProbe.swift").read_text()
fixture = snapshot[:snapshot.index("    func offer(_ packet: PacketStub) {")]
fixture += """
    var videoBackpressure = ReceiverVideoBackpressurePolicy()
    var decodeFlushes = 0
    var onDecodedFrame: (() -> Void)?
    func offer(_ packet: PacketStub) {
""" + source[start:end] + "        admitted += 1\n    }\n}\n"
fixture += """
@main struct AdmissionTest {
    static func main() {
        let receiver = IOSBackpressureProbe()
        receiver.displayLayer.isReadyForMoreMediaData = false
        receiver.offer(PacketStub(keyframe: false))
        receiver.displayLayer.isReadyForMoreMediaData = true
        for _ in 0..<30 { receiver.offer(PacketStub(keyframe: false)) }
        precondition(receiver.admitted == 31 && receiver.displayLayer.flushes == 0,
                     "a transient occupancy signal must preserve references")
        receiver.displayLayer.isReadyForMoreMediaData = false
        for _ in 0..<200 { receiver.offer(PacketStub(keyframe: false)) }
        precondition(receiver.admitted <= 33 && receiver.displayLayer.flushes == 1)
        receiver.displayLayer.isReadyForMoreMediaData = true
        let admitted = receiver.admitted
        receiver.offer(PacketStub(keyframe: false))
        precondition(receiver.admitted == admitted, "flush invalidates predictive references")
        receiver.offer(PacketStub(keyframe: true))
        receiver.offer(PacketStub(keyframe: false))
        precondition(receiver.admitted == admitted + 2)
        print("iOS current admission: transient continuity and bounded recovery PASS")
    }
}
"""
if not args.source_ref:
    assert "let withinUnconfiguredLimits =" in source, "handleAnnexB must enforce videoLimits when configuredVideo is nil"
    assert "(configuredVideo == nil && withinUnconfiguredLimits)" in source, "unconfigured Annex-B stream must not bypass videoLimits"
    adopt_idx = source.index("private func adopt(")
    reset_call_idx = source.index("self.resetStreamState(acceptingInput: true)", adopt_idx)
    conn_assign_idx = source.index("self.connection = conn", adopt_idx)
    assert reset_call_idx < conn_assign_idx, "adopt must resetStreamState before assigning self.connection = conn"
    assert "self.decodeErrorCount = 0" in source[source.index("private func decodeAndRender("):], (
        "decodeAndRender must reset decodeErrorCount on successful frame decode"
    )
    reset_decoder_section = source[source.index("private func resetVideoDecoder()"):source.index("private func configureVideo(")]
    assert "lastKeyframeRequest = .distantPast" in reset_decoder_section, (
        "resetVideoDecoder must reset lastKeyframeRequest so immediate recovery is not throttled"
    )
    enqueue_section = source[source.index("private func enqueueFrame("):source.index("private func decodeAndRender(")]
    assert "lastKeyframeRequest = .distantPast" in enqueue_section and "if !isKeyframe {" in enqueue_section, (
        "display-path toggle must reset lastKeyframeRequest and allow keyframes through immediately"
    )
    metal_source = (root / "iOS/MetalVideoRenderer.swift").read_text()
    draw_section = metal_source[metal_source.index("private func draw("):]
    resize_return_idx = draw_section.index("return")
    next_drawable_idx = draw_section.index("metalLayer.nextDrawable()")
    assert resize_return_idx < next_drawable_idx, (
        "MetalVideoRenderer.draw must return and wait for main-thread drawableSize resize before calling nextDrawable()"
    )
    assert "resetGeneration" in metal_source and "latestGeneration" in metal_source, (
        "MetalVideoRenderer must track resetGeneration and latestGeneration across async boundaries"
    )

    limits_start = source.index("    private var videoLimits: (width: Int, height: Int) {")
    limits_end = source.index("    private func sendHello(on conn: NWConnection) {", limits_start)
    config_start = source.index("    private func configureVideo(_ object: [String: Any]) {")
    config_end = source.index("    private func rejectVideo(_ message: String) {", config_start)
    configure_video_probe = f"""
import CoreVideo
import QuartzCore

enum Log {{ static func info(_ message: String) {{}} }}

final class ConfigureVideoProbe {{
    var devicePixelsWide = 2064
    var devicePixelsHigh = 2752
    var nativeLong = 2752
    var nativeShort = 2064
    var displayMaxFps = 120
    var nativeHighRefreshTrialForConnection = false
    var videoFallback = AppleVideoFallbackPolicy()
    var configuredVideo: AppleVideoConfiguration?
    var videoCodec: ReceiverVideoCodec = .h264
    var supportsHEVC = true
    var inputSendBudget = InputSendBudget()
    var requestedFps = 60
    var codecLabel = "H.264"
    var rejectedMessages: [String] = []
    var decoderResets = 0
    var videoFailures = 0

    func rejectVideo(_ message: String) {{ rejectedMessages.append(message) }}
    func resetVideoDecoder() {{ decoderResets += 1 }}
    func failVideo() {{ videoFailures += 1 }}

{source[limits_start:limits_end]}
{source[config_start:config_end]}
    func apply(_ object: [String: Any]) {{ configureVideo(object) }}
}}

func makeNV12Buffer(width: Int, height: Int) -> CVPixelBuffer {{
    var pb: CVPixelBuffer?
    let attrs: [CFString: Any] = [
        kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        kCVPixelBufferMetalCompatibilityKey: true,
    ]
    let status = CVPixelBufferCreate(
        nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        attrs as CFDictionary, &pb)
    precondition(status == kCVReturnSuccess && pb != nil, "failed to create NV12 CVPixelBuffer")
    return pb!
}}

func runConfigureVideoAndMetalTests() {{
    let probe = ConfigureVideoProbe()
    // 1. Portrait device limits (2304x4096) accept a landscape 3840x2160@60 streamConfig via orientation-swap fallback.
    probe.apply(["codec": "hevc", "width": 3840, "height": 2160, "fps": 60])
    precondition(probe.rejectedMessages.isEmpty, "orientation-swapped standard streamConfig should be admitted")
    precondition(probe.configuredVideo?.width == 3840 && probe.configuredVideo?.height == 2160 && probe.configuredVideo?.fps == 60)
    precondition(probe.decoderResets == 1)

    // 2. Without nativeHighRefreshTrialForConnection, native 2752x2064@120 exceeds standard pixel budget and must be rejected.
    probe.apply(["codec": "hevc", "width": 2752, "height": 2064, "fps": 120])
    precondition(probe.rejectedMessages.count == 1, "native 120fps without trial must be rejected")

    // 3. With nativeHighRefreshTrialForConnection enabled while device is in portrait (2064x2752),
    //    a landscape native 2752x2064@120 streamConfig is admitted via swappedEnvelope fallback.
    probe.rejectedMessages.removeAll()
    probe.nativeHighRefreshTrialForConnection = true
    probe.apply(["codec": "hevc", "width": 2752, "height": 2064, "fps": 120])
    precondition(probe.rejectedMessages.isEmpty, "swappedEnvelope must admit landscape native 120fps while device is portrait")
    precondition(probe.configuredVideo?.width == 2752 && probe.configuredVideo?.height == 2064 && probe.configuredVideo?.fps == 120)
    precondition(probe.decoderResets == 2)

    // 4. Portrait native 2064x2752@120 is admitted directly via nativeVideoEnvelope.
    probe.apply(["codec": "hevc", "width": 2064, "height": 2752, "fps": 120])
    precondition(probe.rejectedMessages.isEmpty, "direct nativeVideoEnvelope must admit portrait native 120fps")
    precondition(probe.configuredVideo?.width == 2064 && probe.configuredVideo?.height == 2752 && probe.configuredVideo?.fps == 120)
    precondition(probe.decoderResets == 3)

    // 5. MetalVideoRenderer reset generation & stale generation guards.
    if let renderer = MetalVideoRenderer() {{
        let pb1 = makeNV12Buffer(width: 128, height: 64)
        let pb2 = makeNV12Buffer(width: 256, height: 128)
        let initialSize = renderer.metalLayer.drawableSize

        // Queue a frame that requires main-thread drawableSize resize, then call reset() before pumping RunLoop.main.
        renderer.render(pb1, captureMs: 10, generation: 1)
        Thread.sleep(forTimeInterval: 0.05)
        renderer.reset()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        precondition(renderer.metalLayer.drawableSize == initialSize,
                     "stale main-thread resize block must not mutate drawableSize after reset()")

        // Stale generation (< latestGeneration) must be ignored.
        renderer.render(pb2, captureMs: 20, generation: 2)
        Thread.sleep(forTimeInterval: 0.05)
        renderer.render(pb1, captureMs: 15, generation: 1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        Thread.sleep(forTimeInterval: 0.05)
        precondition(renderer.metalLayer.drawableSize == CGSize(width: 256, height: 128),
                     "current generation 2 must resize drawableSize to 256x128 while ignoring stale generation 1")

        // reset(forGeneration:) when latestGeneration == 2 must not clobber generation 2,
        // whereas reset(forGeneration: 3) must advance latestGeneration and reject generation 2.
        let pb3 = makeNV12Buffer(width: 320, height: 180)
        renderer.render(pb3, captureMs: 30, generation: 2)
        Thread.sleep(forTimeInterval: 0.05)
        renderer.reset(forGeneration: 2)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        precondition(renderer.metalLayer.drawableSize == CGSize(width: 320, height: 180),
                     "reset(forGeneration: 2) after generation 2 frame arrived must preserve generation 2 resize")

        let pb4 = makeNV12Buffer(width: 512, height: 288)
        renderer.render(pb4, captureMs: 40, generation: 2)
        Thread.sleep(forTimeInterval: 0.05)
        renderer.reset(forGeneration: 3)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        precondition(renderer.metalLayer.drawableSize == CGSize(width: 320, height: 180),
                     "reset(forGeneration: 3) must cancel pending generation 2 main-thread resize")
    }}
}}
"""
    fixture = fixture.replace(
        '        print("iOS current admission: transient continuity and bounded recovery PASS")',
        '        runConfigureVideoAndMetalTests()\n        print("iOS current admission: transient continuity and bounded recovery PASS")',
    ) + configure_video_probe

with tempfile.TemporaryDirectory(prefix="displayweave-ios-admission-") as tmp:
    path = Path(tmp)
    (path / "Fixture.swift").write_text(fixture)
    extra_sources = (
        [
            "Shared/ReceiverVideoBitstream.swift",
            "Shared/AppleVideoPolicy.swift",
            "Shared/InputSendBudget.swift",
            "iOS/MetalVideoRenderer.swift",
        ]
        if not args.source_ref else []
    )
    subprocess.run(["swiftc", "Shared/ReceiverVideoFlowPolicy.swift", *extra_sources, str(path / "Fixture.swift"),
                    "-o", str(path / "test")], cwd=root, check=True)
    subprocess.run([str(path / "test")], check=True)

