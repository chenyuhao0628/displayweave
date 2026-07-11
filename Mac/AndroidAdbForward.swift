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

struct AndroidAdbForward: Codable, Equatable, Hashable, Identifiable, Sendable {
    let sessionID: UUID
    let serial: String
    let localPort: UInt16
    let remotePort: UInt16

    var id: UUID { sessionID }
}

protocol AndroidAdbForwardRecordStoring: Sendable {
    func records() async -> [AndroidAdbForward]
    func upsert(_ mapping: AndroidAdbForward) async
    func remove(sessionID: UUID) async
}

actor UserDefaultsAndroidAdbForwardStore: AndroidAdbForwardRecordStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard,
         key: String = "androidAdbOwnedForwards") {
        self.defaults = defaults
        self.key = key
    }

    func records() -> [AndroidAdbForward] {
        readRecords()
    }

    func upsert(_ mapping: AndroidAdbForward) {
        var records = readRecords()
        records.removeAll { $0.sessionID == mapping.sessionID }
        records.append(mapping)
        records.sort { $0.localPort < $1.localPort }
        writeRecords(records)
    }

    func remove(sessionID: UUID) {
        var records = readRecords()
        records.removeAll { $0.sessionID == sessionID }
        writeRecords(records)
    }

    private func readRecords() -> [AndroidAdbForward] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([AndroidAdbForward].self,
                                                      from: data) else { return [] }
        return records
    }

    private func writeRecords(_ records: [AndroidAdbForward]) {
        if records.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: key)
        }
    }
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
    private let recordStore: any AndroidAdbForwardRecordStoring
    private var mappings: [UUID: AndroidAdbForward] = [:]

    init(client: AndroidAdbClient,
         portAllocator: any AndroidAdbPortAllocating = SystemLoopbackPortAllocator(),
         recordStore: any AndroidAdbForwardRecordStoring = UserDefaultsAndroidAdbForwardStore()) {
        self.client = client
        self.portAllocator = portAllocator
        self.recordStore = recordStore
    }

    func create(serial: String, remotePort: UInt16 = 9000) async throws -> AndroidAdbForward {
        let localPort = try portAllocator.allocate()
        let mapping = AndroidAdbForward(sessionID: UUID(), serial: serial,
                                        localPort: localPort, remotePort: remotePort)
        await recordStore.upsert(mapping)
        do {
            try await install(mapping)
            mappings[mapping.sessionID] = mapping
            return mapping
        } catch {
            await recordStore.remove(sessionID: mapping.sessionID)
            throw error
        }
    }

    func recreate(_ mapping: AndroidAdbForward) async throws {
        await recordStore.upsert(mapping)
        do {
            try await install(mapping)
            mappings[mapping.sessionID] = mapping
        } catch {
            await recordStore.remove(sessionID: mapping.sessionID)
            throw error
        }
    }

    func remove(sessionID: UUID) async {
        guard let mapping = mappings.removeValue(forKey: sessionID) else { return }
        do {
            try await removeForward(mapping)
            await recordStore.remove(sessionID: sessionID)
        } catch {
            if isMissingListener(error) {
                await recordStore.remove(sessionID: sessionID)
            }
            // Other errors keep the record so a later launch can retry.
        }
    }

    func cleanupPersistedMappings() async {
        let persisted = await recordStore.records()
        for mapping in persisted {
            do {
                try await removeForward(mapping)
                await recordStore.remove(sessionID: mapping.sessionID)
            } catch {
                if isMissingListener(error) {
                    await recordStore.remove(sessionID: mapping.sessionID)
                }
                // Other errors keep the record so a later launch can retry.
            }
        }
    }

    func ownedMappings() -> [AndroidAdbForward] {
        Array(mappings.values).sorted { $0.localPort < $1.localPort }
    }

    private func install(_ mapping: AndroidAdbForward) async throws {
        try await client.run(serial: mapping.serial, arguments: [
            "forward", "tcp:\(mapping.localPort)", "tcp:\(mapping.remotePort)",
        ])
    }

    private func removeForward(_ mapping: AndroidAdbForward) async throws {
        try await client.run(serial: mapping.serial, arguments: [
            "forward", "--remove", "tcp:\(mapping.localPort)",
        ])
    }

    private func isMissingListener(_ error: Error) -> Bool {
        guard case AndroidAdbFailure.commandFailed(_, let message) = error else {
            return false
        }
        return message.contains("listener") && message.contains("not found")
    }

}
