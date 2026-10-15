import Foundation
import Network

@main struct DirectCableSelfTest {
    static func main() {
        for address in ["169.254.0.1", "169.254.255.254", "fe80::1", "febf::1%en9"] {
            precondition(DirectCable.isLinkLocal(address))
        }
        for address in ["169.254.evil.test", "169.254.1.999", "fe80:not-an-ip", "fe80::1%", "fe80::1%en1%en2", "192.168.1.2", "127.0.0.1", "fd00::1", "fec0::1", "::1"] {
            precondition(!DirectCable.isLinkLocal(address), address)
        }
        precondition(DirectCable.isCandidate(name: "bridge0", wired: true, addresses: ["169.254.1.2", "fe80::1%bridge0"]))
        precondition(!DirectCable.isCandidate(name: "en0", wired: false, addresses: ["169.254.1.2"]))
        precondition(!DirectCable.isCandidate(name: "anpi0", wired: true, addresses: ["fe80::1"]))
        precondition(!DirectCable.isCandidate(name: "bridge0", wired: true, addresses: []))
        precondition(!DirectCable.isCandidate(name: "en5", wired: true, addresses: ["fe80::1", "192.168.1.2"]))
        var policy = DirectCableAutoConnectPolicy()
        precondition(policy.arrivals(present: ["A"], active: [], enabled: false).isEmpty)
        precondition(policy.arrivals(present: ["A"], active: [], enabled: true) == ["A"])
        precondition(policy.arrivals(present: ["A"], active: [], enabled: true).isEmpty)
        _ = policy.arrivals(present: [], active: [], enabled: true)
        precondition(policy.arrivals(present: ["A"], active: ["A"], enabled: true).isEmpty)
        policy.disconnect("A")
        _ = policy.arrivals(present: [], active: [], enabled: true)
        precondition(policy.arrivals(present: ["A"], active: [], enabled: true).isEmpty)
        policy.manualConnect("A")
        precondition(policy.arrivals(present: ["A"], active: [], enabled: true).isEmpty)
        _ = policy.arrivals(present: [], active: [], enabled: true)
        precondition(policy.arrivals(present: ["A", "B"], active: ["B"], enabled: true) == ["A"])
        print("Direct-link address/interface classification, opt-in, opt-out and bounded arrival attempts PASS")
    }
}
