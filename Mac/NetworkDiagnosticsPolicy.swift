import Foundation

enum UDPMediaActivationPolicy {
    static let forceDirectCableDefaultsKey = "forceUDPMediaOnDirectCable"

    /// Dedicated wired `DirectCable` links (Thunderbolt Bridge / point-to-point Ethernet)
    /// stay on kernel TCP by default so hardware TSO/LRO operates without software pacer
    /// overhead; Wi-Fi and unpinned LAN links activate `udpMediaV1` when advertised.
    /// Whenever `UDPMediaSenderSession` is created, `pinnedInterfaceName` is always bound.
    static func shouldActivateUDPMedia(
        peerSupportsUDP: Bool,
        pinnedInterfaceName: String?,
        forceOnDirectCable: Bool = UserDefaults.standard.bool(forKey: forceDirectCableDefaultsKey)
    ) -> Bool {
        guard peerSupportsUDP else { return false }
        if pinnedInterfaceName != nil && !forceOnDirectCable {
            return false
        }
        return true
    }
}
