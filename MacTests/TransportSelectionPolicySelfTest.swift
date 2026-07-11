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

        let autoRecovery = AndroidUsbRecoveryMachine(mode: .auto)
        check(.waiting(attempt: 0, delay: 0.5),
              autoRecovery.reduce(state: .connected, event: .socketFailed),
              "socket failure should begin the first bounded delay")
        check(.reconnecting(attempt: 0),
              autoRecovery.reduce(state: .waiting(attempt: 0, delay: 0.5),
                                  event: .adbAvailable),
              "an available ADB device should recreate its mapping")
        check(.waiting(attempt: 1, delay: 1),
              autoRecovery.reduce(state: .waiting(attempt: 0, delay: 0.5),
                                  event: .adbUnavailable),
              "an unavailable device should advance the backoff")
        check(.awaitingWifi,
              autoRecovery.reduce(state: .waiting(attempt: 4, delay: 8),
                                  event: .adbUnavailable),
              "Auto should consider WiFi only after USB retries are exhausted")
        check(.fallbackWifi("wifi:pixel"),
              autoRecovery.reduce(state: .awaitingWifi,
                                  event: .wifiMatched("wifi:pixel")),
              "matching WiFi should become the Auto fallback")

        let usbRecovery = AndroidUsbRecoveryMachine(mode: .usb)
        check(.failed,
              usbRecovery.reduce(state: .waiting(attempt: 4, delay: 8),
                                 event: .adbUnavailable),
              "explicit USB mode should fail instead of using WiFi")
        check(.cancelled,
              autoRecovery.reduce(state: .waiting(attempt: 2, delay: 2), event: .cancelled),
              "user cancellation should stop all scheduled recovery")

        check([.sendStreamConfig, .forceKeyframe],
              ReconnectHandshakePolicy.actions(hasConfiguredStream: true),
              "a configured stream must resend config before its reconnect keyframe")
        check([.forceKeyframe],
              ReconnectHandshakePolicy.actions(hasConfiguredStream: false),
              "an initial connection has no stream config to resend yet")

        print("TransportSelectionPolicySelfTest PASS")
    }
}
