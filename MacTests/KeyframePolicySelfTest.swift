import Foundation

@main
enum KeyframePolicySelfTest {
    static func main() {
        precondition(KeyframePolicy.candidateSeconds(transport: .wifi) == [1, 2, 3])
        precondition(KeyframePolicy.candidateSeconds(transport: .usb) == [1, 2])
        precondition(KeyframePolicy.defaultSeconds(transport: .wifi) == 2)
        precondition(KeyframePolicy.defaultSeconds(transport: .usb) == 1)
        precondition(KeyframePolicy.frameInterval(fps: 60, transport: .wifi) == 120)
        precondition(KeyframePolicy.frameInterval(fps: 120, transport: .usb) == 120)
        print("KeyframePolicySelfTest PASS")
    }
}
