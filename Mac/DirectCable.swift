// Adapted from peetzweg/opendisplay DirectCable.swift (d2dfb3f / 42ad6fb, GPL-3.0).
// Candidate only: a DHCP-less Ethernet segment can look like a direct cable.
import Foundation
import Network
import Darwin

enum DirectCable {
    static func isLinkLocal(_ address: String) -> Bool {
        let parts = address.split(separator: "%", omittingEmptySubsequences: false)
        guard parts.count <= 2, !parts.contains(where: { $0.isEmpty }) else { return false }
        let literal = String(parts[0])
        if let v4 = IPv4Address(literal) { return parts.count == 1 && v4.isLinkLocal }
        if let v6 = IPv6Address(literal) { return v6.isLinkLocal }
        return false
    }

    static func isCandidate(name: String, wired: Bool, addresses: [String]) -> Bool {
        wired && !name.hasPrefix("anpi") && !name.hasPrefix("lo")
            && !addresses.isEmpty && addresses.allSatisfy(isLinkLocal)
    }

    static func interface(for result: NWBrowser.Result) -> NWInterface? {
        guard case .bonjour(let txt) = result.metadata,
              txt["device"]?.lowercased() == "mac", let id = txt["id"], !id.isEmpty else { return nil }
        let addresses = interfaceAddresses()
        return result.interfaces.sorted { $0.name < $1.name }.first {
            isCandidate(name: $0.name, wired: $0.type == .wiredEthernet, addresses: addresses[$0.name] ?? [])
        }
    }

    /// Match service resolution and the TCP route to the same interface.
    static func endpoint(_ endpoint: NWEndpoint, on interface: NWInterface?) -> NWEndpoint {
        guard let interface, case .service(let name, let type, let domain, _) = endpoint else { return endpoint }
        return .service(name: name, type: type, domain: domain, interface: interface)
    }

    private static func interfaceAddresses() -> [String: [String]] {
        var result: [String: [String]] = [:]
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return result }
        defer { freeifaddrs(list) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = ptr.pointee
            guard entry.ifa_flags & UInt32(IFF_UP) != 0,
                  entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let address = entry.ifa_addr else { continue }
            let family = Int32(address.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            result[String(cString: entry.ifa_name), default: []].append(String(cString: host))
        }
        return result
    }
}

/// One auto attempt per appearance. Explicit disconnect survives replug until a
/// manual connect or app restart. State is bounded even on a busy shared LAN.
struct DirectCableAutoConnectPolicy {
    private var attempted: Set<String> = []
    private var optedOut: Set<String> = []
    private var optOutLimitReached = false

    mutating func arrivals(present: Set<String>, active: Set<String>, enabled: Bool) -> [String] {
        attempted.formIntersection(present)
        guard enabled, !optOutLimitReached else { return [] }
        let result = present.subtracting(active).subtracting(attempted).subtracting(optedOut).sorted().prefix(256)
        attempted.formUnion(result)
        return Array(result)
    }

    mutating func disconnect(_ id: String) {
        guard optedOut.count < 256 else { optOutLimitReached = true; return }
        optedOut.insert(id)
    }

    mutating func manualConnect(_ id: String) {
        optedOut.remove(id)
        if attempted.count < 256 { attempted.insert(id) }
    }
}
