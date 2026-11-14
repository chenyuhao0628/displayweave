import Foundation
import Network
import dnssd

enum LANProxyBypassPolicy {
    /// Bypass system HTTP/SOCKS proxies on LAN/Bonjour TCP transports without
    /// altering `127.0.0.1` / `::1` / `localhost` loopback ADB/usbmux tunnels.
    static func shouldBypassProxies(for endpoint: NWEndpoint) -> Bool {
        switch endpoint {
        case .service:
            return true
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let address):
                return !address.isLoopback
            case .ipv6(let address):
                return !address.isLoopback
            case .name(let name, _):
                let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return normalized != "localhost"
                    && normalized != "127.0.0.1"
                    && normalized != "::1"
            @unknown default:
                return true
            }
        case .unix:
            return false
        default:
            return true
        }
    }
}

enum LocalNetworkDiscoveryPolicy {
    static let policyDeniedMessage = "请在“系统设置 > 隐私与安全性 > 本地网络”中允许 DisplayWeave，然后重试"
    static let maxRetryDelaySeconds: TimeInterval = 15.0

    static func isPolicyDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error {
            return code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied)
        }
        return false
    }

    static func recoveryStatus(for error: NWError) -> String {
        if isPolicyDenied(error) {
            return policyDeniedMessage
        }
        return "局域网设备发现失败（\(error.localizedDescription)），正在重试；请检查“系统设置 > 隐私与安全性 > 本地网络”权限与网络设置"
    }

    static func retryDelaySeconds(attempt: Int) -> TimeInterval {
        let clampedAttempt = max(0, min(attempt, 4))
        return min(maxRetryDelaySeconds, pow(2.0, Double(clampedAttempt)))
    }
}

enum WiFiAWDLAdvisoryPolicy {
    static let sharingSuiteName = "com.apple.sharingd"
    static let discoverableModeKey = "DiscoverableMode"
    static let advisoryMessage = "提示：当前隔空投送（AirDrop）设为“所有人”，可能触发 AWDL 周期性信道扫描抖动；若 Wi-Fi 画面偶发卡顿，可在控制中心将隔空投送改为“仅限联系人”或“关闭”。"

    static func currentDiscoverableMode(
        defaults: UserDefaults? = UserDefaults(suiteName: sharingSuiteName)
    ) -> String? {
        defaults?.string(forKey: discoverableModeKey)
    }

    static func advisory(wifiStreamingActive: Bool, discoverableMode: String?) -> String? {
        guard wifiStreamingActive, let discoverableMode else { return nil }
        let normalized = discoverableMode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.caseInsensitiveCompare("Everyone") == .orderedSame else { return nil }
        return advisoryMessage
    }
}

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
