// Exact admission excerpt from PhoneReceiver.handleAnnexB; rendering is stubbed.
// No iOS driver, display, or hardware performance claim is involved.
import Foundation

final class LayerStub {
    enum Status { case rendering, failed }
    var status = Status.rendering
    var isReadyForMoreMediaData = true
    var flushes = 0
    func flush() { flushes += 1 }
}
struct PacketStub { var keyframe: Bool }
final class IOSBackpressureProbe {
    let displayLayer = LayerStub()
    var useMetalPath = false
    var waitingForKeyframe = false
    var admitted = 0
    var recoveryChecks = 0
    func failVideo() { preconditionFailure("not part of this fixture") }
    func requestKeyframeIfNeeded() { recoveryChecks += 1 }
    func offer(_ packet: PacketStub) {
        if displayLayer.status == .failed { failVideo(); return }
        if !useMetalPath, !displayLayer.isReadyForMoreMediaData {
            displayLayer.flush()
            waitingForKeyframe = true
        }
        if waitingForKeyframe, !packet.keyframe { requestKeyframeIfNeeded(); return }
        waitingForKeyframe = false
        admitted += 1
    }
}
@main struct IOSBackpressureMain {
    static func main() {
        let probe = IOSBackpressureProbe()
        probe.displayLayer.isReadyForMoreMediaData = false
        probe.offer(PacketStub(keyframe: false))
        probe.displayLayer.isReadyForMoreMediaData = true
        for _ in 0..<30 { probe.offer(PacketStub(keyframe: false)) }
        precondition(probe.admitted == 0 && probe.displayLayer.flushes == 1)
        print("iOS admission: one not-ready P-frame -> 1 flush; next 30 ready P-frames -> 0 admitted")
        probe.offer(PacketStub(keyframe: true))
        precondition(probe.admitted == 1 && !probe.waitingForKeyframe)
        print("iOS admission: a subsequent keyframe resumes admission")
    }
}
