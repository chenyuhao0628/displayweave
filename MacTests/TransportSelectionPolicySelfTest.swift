import Foundation

private func check<T: Equatable>(_ expected: T, _ actual: T, _ message: String) {
    if expected != actual {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

@main
struct TransportSelectionPolicySelfTest {
    static func main() {
        let policy = TransportSelectionPolicy()
        let receiver = WifiTransportCandidate(id: "wifi:pixel", installID: "install-1")

        check(.androidUSB("A"),
              policy.preferred(mode: .auto, androidUSB: "A", wifi: receiver),
              "Auto should prefer an authorized Android USB device")
        check(.wifi(receiver.id),
              policy.preferred(mode: .wifi, androidUSB: "A", wifi: receiver),
              "WiFi mode should ignore an attached USB device")
        check(nil,
              policy.preferred(mode: .usb, androidUSB: nil, wifi: receiver),
              "USB mode should never silently choose WiFi")
        check(receiver.id,
              policy.fallbackWifi(usbInstallID: "install-1", receivers: [receiver])?.id,
              "Auto fallback should choose the same install ID")
        check(nil,
              policy.fallbackWifi(usbInstallID: nil, receivers: [receiver]),
              "unknown USB identity should not fall back to an arbitrary receiver")
        check(nil,
              policy.fallbackWifi(
                usbInstallID: "install-1",
                receivers: [WifiTransportCandidate(id: "wifi:other", installID: "install-2")]),
              "different physical devices must not be merged")
        check([0.5, 1, 2, 4, 8], TransportSelectionPolicy.recoveryDelays,
              "USB recovery should use finite exponential backoff")

        print("TransportSelectionPolicySelfTest PASS")
    }
}
