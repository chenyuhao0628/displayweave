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
        check(.replaceWiFiWithUSB,
              AndroidTransportHandoverPolicy.decision(
                mode: .auto,
                existing: .wifi(installID: "install-1"),
                arrivingUSBInstallID: "install-1"),
              "Auto must release the same Receiver's WiFi session before USB connects")
        check(.keepExisting,
              AndroidTransportHandoverPolicy.decision(
                mode: .auto,
                existing: .wifi(installID: "install-2"),
                arrivingUSBInstallID: "install-1"),
              "Auto must not end an unrelated WiFi Receiver")
        check(.keepExisting,
              AndroidTransportHandoverPolicy.decision(
                mode: .wifi,
                existing: .wifi(installID: "install-1"),
                arrivingUSBInstallID: "install-1"),
              "WiFi-only mode must not upgrade to USB")
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
        check(false,
              ReconnectPeerReadinessPolicy.clearsDisconnectGrace(for: .socketReady),
              "ADB loopback readiness must not prove the Android Receiver is alive")
        check(true,
              ReconnectPeerReadinessPolicy.clearsDisconnectGrace(for: .peerMessage),
              "a protocol message proves the Receiver is alive")
        let lastPeerMessage = Date(timeIntervalSince1970: 100)
        let watchdogDetection = Date(timeIntervalSince1970: 106)
        let graceStart = DisconnectGracePolicy.startedAt(
            existing: nil, failureObservedAt: lastPeerMessage)
        check(lastPeerMessage, graceStart,
              "a silent disconnect grace must start at the last peer message")
        check(4,
              DisconnectGracePolicy.remainingSeconds(
                startedAt: graceStart, now: watchdogDetection, graceSeconds: 10),
              "watchdog detection time must not add a second full grace period")
        check(false,
              DisconnectGracePolicy.hasExpired(
                startedAt: graceStart,
                now: Date(timeIntervalSince1970: 109.999), graceSeconds: 10),
              "disconnect grace must remain active before its deadline")
        check(true,
              DisconnectGracePolicy.hasExpired(
                startedAt: graceStart,
                now: Date(timeIntervalSince1970: 110), graceSeconds: 10),
              "disconnect grace must expire exactly ten seconds after peer activity")
        check(lastPeerMessage,
              DisconnectGracePolicy.startedAt(
                existing: lastPeerMessage,
                failureObservedAt: Date(timeIntervalSince1970: 108)),
              "reconnect attempts must preserve the original disconnect deadline")
        check(true,
              ConnectionGenerationPolicy.accepts(
                callbackGeneration: 2, currentGeneration: 2,
                isCurrentObject: true, stopped: false),
              "the current connection callback must be accepted")
        check(false,
              ConnectionGenerationPolicy.accepts(
                callbackGeneration: 1, currentGeneration: 2,
                isCurrentObject: false, stopped: false),
              "an old connection callback must not mutate current state")
        check(false,
              ConnectionGenerationPolicy.accepts(
                callbackGeneration: 2, currentGeneration: 2,
                isCurrentObject: false, stopped: false),
              "generation equality cannot replace current-object identity")
        check(false,
              ConnectionGenerationPolicy.accepts(
                callbackGeneration: 2, currentGeneration: 2,
                isCurrentObject: true, stopped: true),
              "callbacks after stop must be rejected")
        check(true,
              ConnectionGenerationPolicy.acceptsReconnectTask(
                taskGeneration: 4, currentGeneration: 4, stopped: false),
              "the current reconnect task must run")
        check(false,
              ConnectionGenerationPolicy.acceptsReconnectTask(
                taskGeneration: 3, currentGeneration: 4, stopped: false),
              "an expired reconnect task must not dial")
        check(.endSession,
              ConnectionClosurePolicy.action(for: .cleanEnd, peer: .legacyApple),
              "a legacy Apple receiver that cleanly closes must end its session")
        check(.retryWithinGrace,
              ConnectionClosurePolicy.action(for: .cleanEnd, peer: .android),
              "an Android clean close must retain bounded background/surface recovery")
        check(.retryWithinGrace,
              ConnectionClosurePolicy.action(for: .cleanEnd, peer: .unknown),
              "a close before hello must fail safe to bounded retry")
        check(.retryWithinGrace,
              ConnectionClosurePolicy.action(for: .failure, peer: .legacyApple),
              "a transport failure should retain bounded reconnect recovery")
        check(.endSession,
              ReceiverControlPolicy.closureAction(
                messageType: "goodbye", peer: .legacyApple),
              "an explicit legacy Apple goodbye must end the session")
        check(.retryWithinGrace,
              ReceiverControlPolicy.closureAction(
                messageType: "goodbye", peer: .android),
              "an Android goodbye must retain bounded foreground recovery")
        check(nil,
              ReceiverControlPolicy.closureAction(
                messageType: "ping", peer: .android),
              "normal control traffic must keep the session alive")

        print("TransportSelectionPolicySelfTest PASS")
    }
}
