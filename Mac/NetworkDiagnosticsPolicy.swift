import Darwin
import Foundation
import Network
import SystemConfiguration
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

struct IPv4SubnetSnapshot: Equatable, Sendable {
    let addressHostOrder: UInt32
    let netmaskHostOrder: UInt32

    func contains(hostOrderAddress: UInt32) -> Bool {
        (hostOrderAddress & netmaskHostOrder) == (addressHostOrder & netmaskHostOrder)
    }

    static func parseIPv4HostOrder(_ text: String) -> UInt32? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var addr = in_addr()
        guard trimmed.withCString({ inet_pton(AF_INET, $0, &addr) }) == 1 else {
            return nil
        }
        return UInt32(bigEndian: addr.s_addr)
    }
}

enum WiFiEmptyDiscoveryIsolationPolicy {
    static let gracePeriodSeconds: TimeInterval = 8.0
    static let advisoryMessage = "提示：Wi-Fi 搜索已超过 8 秒仍未发现接收端。请确认两台设备连接在同一局域网子网且接收端已打开 DisplayWeave；若当前连接的是访客、酒店、校园或企业 Wi-Fi，路由器可能开启了客户端隔离（AP Isolation），建议改用个人热点或 USB 有线连接。"

    static func isVPNTunnelOwningRoute(
        primaryIPv4Interface: String?,
        primaryIPv6Interface: String?,
        ipv4Router: String?,
        physicalIPv4Subnets: [IPv4SubnetSnapshot],
        hasActiveUtunIPv4: Bool
    ) -> Bool {
        let v4If = primaryIPv4Interface?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let v6If = primaryIPv6Interface?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if v4If.hasPrefix("utun") || v6If.hasPrefix("utun") {
            return true
        }
        if hasActiveUtunIPv4,
           let ipv4Router,
           let routerAddr = IPv4SubnetSnapshot.parseIPv4HostOrder(ipv4Router),
           !physicalIPv4Subnets.isEmpty,
           !physicalIPv4Subnets.contains(where: { $0.contains(hostOrderAddress: routerAddr) }) {
            return true
        }
        return false
    }

    static func currentVPNTunnelOwnsRouting() -> Bool {
        var primaryIPv4If: String?
        var primaryIPv6If: String?
        var ipv4Router: String?
        if let store = SCDynamicStoreCreate(nil, "DisplayWeaveNetworkDiagnostics" as CFString, nil, nil) {
            if let v4Dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] {
                primaryIPv4If = v4Dict["PrimaryInterface"] as? String
                ipv4Router = v4Dict["Router"] as? String
            }
            if let v6Dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv6" as CFString) as? [String: Any] {
                primaryIPv6If = v6Dict["PrimaryInterface"] as? String
            }
        }

        var physicalSubnets: [IPv4SubnetSnapshot] = []
        var hasActiveUtunIPv4 = false
        var firstAddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&firstAddr) == 0, let head = firstAddr {
            defer { freeifaddrs(head) }
            var cursor: UnsafeMutablePointer<ifaddrs>? = head
            while let current = cursor {
                let entry = current.pointee
                cursor = entry.ifa_next
                let flags = Int32(entry.ifa_flags)
                guard (flags & IFF_UP) != 0,
                      (flags & IFF_LOOPBACK) == 0,
                      let addrPtr = entry.ifa_addr,
                      Int32(addrPtr.pointee.sa_family) == AF_INET,
                      let namePtr = entry.ifa_name else {
                    continue
                }
                let ifName = String(cString: namePtr).lowercased()
                let ipv4Addr = addrPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                }
                guard ipv4Addr != 0 else { continue }
                if ifName.hasPrefix("utun") {
                    hasActiveUtunIPv4 = true
                } else if ifName.hasPrefix("en") || ifName.hasPrefix("bridge"),
                          let maskPtr = entry.ifa_netmask,
                          Int32(maskPtr.pointee.sa_family) == AF_INET {
                    let netmask = maskPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                        UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                    }
                    if netmask != 0 {
                        physicalSubnets.append(
                            IPv4SubnetSnapshot(addressHostOrder: ipv4Addr, netmaskHostOrder: netmask)
                        )
                    }
                }
            }
        }

        return isVPNTunnelOwningRoute(
            primaryIPv4Interface: primaryIPv4If,
            primaryIPv6Interface: primaryIPv6If,
            ipv4Router: ipv4Router,
            physicalIPv4Subnets: physicalSubnets,
            hasActiveUtunIPv4: hasActiveUtunIPv4
        )
    }

    static func advisory(
        roleEnabled: Bool,
        permitsWiFi: Bool,
        browserReady: Bool,
        localNetworkDenied: Bool,
        hasDiscoveryError: Bool,
        discoveredCount: Int,
        hasWiredDevicesOrActiveSessions: Bool,
        vpnTunnelOwnsRouting: Bool,
        emptyDurationSeconds: TimeInterval
    ) -> String? {
        guard roleEnabled,
              permitsWiFi,
              browserReady,
              !localNetworkDenied,
              !hasDiscoveryError,
              discoveredCount == 0,
              !hasWiredDevicesOrActiveSessions,
              !vpnTunnelOwnsRouting,
              emptyDurationSeconds.isFinite,
              emptyDurationSeconds >= gracePeriodSeconds else {
            return nil
        }
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
