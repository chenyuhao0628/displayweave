import Foundation

struct WifiTransportCandidate: Equatable, Sendable {
    let id: String
    let installID: String?
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
