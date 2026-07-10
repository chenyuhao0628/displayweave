import Foundation
import Darwin

protocol AndroidAdbPortAllocating: Sendable {
    func allocate() throws -> UInt16
}

struct SystemLoopbackPortAllocator: AndroidAdbPortAllocating {
    enum Failure: Error { case socket(Int32), bind(Int32), address(Int32) }

    func allocate() throws -> UInt16 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw Failure.socket(errno) }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw Failure.bind(errno) }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard nameResult == 0 else { throw Failure.address(errno) }
        return UInt16(bigEndian: address.sin_port)
    }
}

struct AndroidAdbForward: Equatable, Hashable, Identifiable, Sendable {
    let sessionID: UUID
    let serial: String
    let localPort: UInt16
    let remotePort: UInt16

    var id: UUID { sessionID }
}

struct AndroidAdbSessionDescriptor: Equatable, Sendable {
    let serial: String
    let host: String
    let port: UInt16
    let transportName: String

    var sessionID: String { "android-adb:\(serial)" }

    init(mapping: AndroidAdbForward) {
        serial = mapping.serial
        host = "127.0.0.1"
        port = mapping.localPort
        transportName = "usb"
    }
}

actor AndroidAdbForwardManager {
    private let client: AndroidAdbClient
    private let portAllocator: any AndroidAdbPortAllocating
    private var mappings: [UUID: AndroidAdbForward] = [:]

    init(client: AndroidAdbClient,
         portAllocator: any AndroidAdbPortAllocating = SystemLoopbackPortAllocator()) {
        self.client = client
        self.portAllocator = portAllocator
    }

    func create(serial: String, remotePort: UInt16 = 9000) async throws -> AndroidAdbForward {
        let localPort = try portAllocator.allocate()
        let mapping = AndroidAdbForward(sessionID: UUID(), serial: serial,
                                        localPort: localPort, remotePort: remotePort)
        try await install(mapping)
        mappings[mapping.sessionID] = mapping
        return mapping
    }

    func recreate(_ mapping: AndroidAdbForward) async throws {
        try await install(mapping)
        mappings[mapping.sessionID] = mapping
    }

    func remove(sessionID: UUID) async {
        guard let mapping = mappings.removeValue(forKey: sessionID) else { return }
        _ = try? await client.run(serial: mapping.serial, arguments: [
            "forward", "--remove", "tcp:\(mapping.localPort)",
        ])
    }

    func ownedMappings() -> [AndroidAdbForward] {
        Array(mappings.values).sorted { $0.localPort < $1.localPort }
    }

    private func install(_ mapping: AndroidAdbForward) async throws {
        try await client.run(serial: mapping.serial, arguments: [
            "forward", "tcp:\(mapping.localPort)", "tcp:\(mapping.remotePort)",
        ])
    }
}
