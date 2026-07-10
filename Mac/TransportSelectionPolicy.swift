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
