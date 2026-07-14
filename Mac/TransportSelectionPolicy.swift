import Foundation

struct WifiTransportCandidate: Equatable, Sendable {
    let id: String
    let installID: String?
}

enum AndroidExistingTransport: Equatable, Sendable {
    case wifi(installID: String?)
    case usb
}

enum AndroidTransportHandoverDecision: Equatable, Sendable {
    case keepExisting
    case replaceWiFiWithUSB
}

enum AndroidTransportHandoverPolicy {
    static func decision(mode: StreamTransportMode,
                         existing: AndroidExistingTransport,
                         arrivingUSBInstallID: String?) -> AndroidTransportHandoverDecision {
        guard mode != .wifi,
              case .wifi(let wifiInstallID) = existing,
              let wifiInstallID,
              wifiInstallID == arrivingUSBInstallID else {
            return .keepExisting
        }
        return .replaceWiFiWithUSB
    }
}

enum TransportCandidate: Equatable, Sendable {
    case androidUSB(String)
    case wifi(String)
}

struct TransportSelectionPolicy: Sendable {
    static let recoveryDelays: [Double] = [0.5, 1, 2, 4, 8]

    func preferred(mode: StreamTransportMode,
                   androidUSB: String?,
                   wifi: WifiTransportCandidate?) -> TransportCandidate? {
        switch mode {
        case .auto:
            if let androidUSB { return .androidUSB(androidUSB) }
            return wifi.map { .wifi($0.id) }
        case .usb:
            return androidUSB.map(TransportCandidate.androidUSB)
        case .wifi:
            return wifi.map { .wifi($0.id) }
        }
    }

    func fallbackWifi(usbInstallID: String?,
                      receivers: [WifiTransportCandidate]) -> WifiTransportCandidate? {
        guard let usbInstallID else { return nil }
        return receivers.first { $0.installID == usbInstallID }
    }
}

enum ReconnectHandshakeAction: Equatable, Sendable {
    case sendStreamConfig
    case forceKeyframe
}

enum ReconnectHandshakePolicy {
    static func actions(hasConfiguredStream: Bool) -> [ReconnectHandshakeAction] {
        hasConfiguredStream ? [.sendStreamConfig, .forceKeyframe] : [.forceKeyframe]
    }
}

enum ReconnectPeerReadinessEvent: Equatable, Sendable {
    case socketReady
    case peerMessage
}

enum ReconnectPeerReadinessPolicy {
    static func clearsDisconnectGrace(for event: ReconnectPeerReadinessEvent) -> Bool {
        event == .peerMessage
    }
}

enum ConnectionClosureEvent: Equatable, Sendable {
    case cleanEnd
    case failure
}

enum ConnectionClosureAction: Equatable, Sendable {
    case endSession
    case retryWithinGrace
}

enum ReceiverPeerKind: Equatable, Sendable {
    case android
    case legacyApple
    case unknown
}

enum ConnectionClosurePolicy {
    static func action(for event: ConnectionClosureEvent,
                       peer: ReceiverPeerKind) -> ConnectionClosureAction {
        guard event == .cleanEnd, peer == .legacyApple else {
            return .retryWithinGrace
        }
        return .endSession
    }
}

enum ReceiverControlPolicy {
    static func closureAction(messageType: String,
                              peer: ReceiverPeerKind) -> ConnectionClosureAction? {
        guard messageType == "goodbye" else { return nil }
        return peer == .legacyApple ? .endSession : .retryWithinGrace
    }
}

enum AndroidUsbRecoveryState: Equatable, Sendable {
    case connected
    case waiting(attempt: Int, delay: Double)
    case reconnecting(attempt: Int)
    case awaitingWifi
    case fallbackWifi(String)
    case failed
    case cancelled
}

enum AndroidUsbRecoveryEvent: Equatable, Sendable {
    case socketFailed
    case adbAvailable
    case adbUnavailable
    case reconnectSucceeded
    case retriesExhausted
    case wifiMatched(String)
    case cancelled
}

struct AndroidUsbRecoveryMachine: Sendable {
    let mode: StreamTransportMode

    func reduce(state: AndroidUsbRecoveryState,
                event: AndroidUsbRecoveryEvent) -> AndroidUsbRecoveryState {
        if event == .cancelled { return .cancelled }
        switch (state, event) {
        case (.connected, .socketFailed):
            return .waiting(attempt: 0, delay: TransportSelectionPolicy.recoveryDelays[0])
        case (.waiting(let attempt, _), .adbAvailable):
            return .reconnecting(attempt: attempt)
        case (.waiting(let attempt, _), .adbUnavailable),
             (.reconnecting(let attempt), .socketFailed):
            return nextAfterFailure(attempt: attempt)
        case (.reconnecting, .reconnectSucceeded):
            return .connected
        case (_, .retriesExhausted):
            return exhaustedState
        case (.awaitingWifi, .wifiMatched(let id)):
            return .fallbackWifi(id)
        default:
            return state
        }
    }

    private func nextAfterFailure(attempt: Int) -> AndroidUsbRecoveryState {
        let next = attempt + 1
        guard TransportSelectionPolicy.recoveryDelays.indices.contains(next) else {
            return exhaustedState
        }
        return .waiting(attempt: next,
                        delay: TransportSelectionPolicy.recoveryDelays[next])
    }

    private var exhaustedState: AndroidUsbRecoveryState {
        mode == .auto ? .awaitingWifi : .failed
    }
}
