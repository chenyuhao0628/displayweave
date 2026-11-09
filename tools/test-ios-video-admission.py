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

with tempfile.TemporaryDirectory(prefix="displayweave-ios-admission-") as tmp:
    path = Path(tmp)
    (path / "Fixture.swift").write_text(fixture)
    subprocess.run(["swiftc", "Shared/ReceiverVideoFlowPolicy.swift", str(path / "Fixture.swift"),
                    "-o", str(path / "test")], cwd=root, check=True)
    subprocess.run([str(path / "test")], check=True)
