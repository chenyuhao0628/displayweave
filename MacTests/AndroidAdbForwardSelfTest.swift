import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

private actor RecordingAdbRunner: AndroidAdbProcessRunning {
    private(set) var calls: [[String]] = []

    func run(executable: URL, arguments: [String], timeout: Duration) async throws
        -> AndroidAdbCommandResult {
        calls.append(arguments)
        return AndroidAdbCommandResult(stdout: "", stderr: "", exitCode: 0)
    }
}

private actor MissingListenerRunner: AndroidAdbProcessRunning {
    func run(executable: URL, arguments: [String], timeout: Duration) async throws
        -> AndroidAdbCommandResult {
        AndroidAdbCommandResult(stdout: "",
                                stderr: "adb: error: listener 'tcp:19005' not found",
                                exitCode: 1)
    }
}

private struct SequencePortAllocator: AndroidAdbPortAllocating {
    let ports: [UInt16]
    private let index = LockedIndex()

    func allocate() throws -> UInt16 {
        index.next(from: ports)
    }
}

private final class LockedIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next(from ports: [UInt16]) -> UInt16 {
        lock.lock()
        defer { lock.unlock() }
        let port = ports[value]
        value += 1
        return port
    }
}

private actor MemoryForwardStore: AndroidAdbForwardRecordStoring {
    private var records: [AndroidAdbForward]

    init(_ records: [AndroidAdbForward] = []) {
        self.records = records
    }

    func records() async -> [AndroidAdbForward] { records }

    func upsert(_ mapping: AndroidAdbForward) async {
        records.removeAll { $0.sessionID == mapping.sessionID }
        records.append(mapping)
        records.sort { $0.localPort < $1.localPort }
    }

    func remove(sessionID: UUID) async {
        records.removeAll { $0.sessionID == sessionID }
    }
}

@main
struct AndroidAdbForwardSelfTest {
    static func main() async throws {
        let runner = RecordingAdbRunner()
        let client = AndroidAdbClient(executable: URL(fileURLWithPath: "/fake/adb"),
                                      runner: runner)
        let store = MemoryForwardStore()
        let manager = AndroidAdbForwardManager(
            client: client,
            portAllocator: SequencePortAllocator(ports: [19001, 19002, 19003]),
            recordStore: store)

        let first = try await manager.create(serial: "A")
        let second = try await manager.create(serial: "B")
        let descriptor = AndroidAdbSessionDescriptor(mapping: first)
        require(descriptor.sessionID == "android-adb:A",
                "Android session identity should remain stable across port recreation")
        require(descriptor.host == "127.0.0.1" && descriptor.port == 19001,
                "Android session should dial only its loopback forward")
        require(descriptor.transportName == "usb",
                "streamConfig should identify the ADB path as USB")
        require(first.localPort == 19001 && second.localPort == 19002,
                "each Android device should receive an independent local port")
        require(first.remotePort == 9000 && second.remotePort == 9000,
                "both mappings should target the existing Android receiver port")
        let persistedAfterCreate = await store.records()
        require(persistedAfterCreate == [first, second],
                "owned mappings should remain persisted after installation")
        var calls = await runner.calls
        require(calls[0] == ["-s", "A", "forward", "tcp:19001", "tcp:9000"],
                "first mapping should be scoped to serial A")
        require(calls[1] == ["-s", "B", "forward", "tcp:19002", "tcp:9000"],
                "second mapping should be scoped to serial B")

        let replacement = try await manager.create(serial: "A")
        calls = await runner.calls
        require(calls[2] == ["-s", "A", "forward", "--remove", "tcp:19001"],
                "replacement must reclaim the previous owned listener first")
        require(calls[3] == ["-s", "A", "forward", "tcp:19003", "tcp:9000"],
                "replacement should install exactly one new listener")
        let mappingsAfterReplacement = await manager.ownedMappings()
        require(mappingsAfterReplacement == [second, replacement],
                "same-device replacement must not retain the old mapping")
        let persistedAfterReplacement = await store.records()
        require(persistedAfterReplacement == [second, replacement],
                "same-device replacement must remove the stale ownership record")

        await manager.remove(sessionID: replacement.sessionID)
        calls = await runner.calls
        require(calls.last == ["-s", "A", "forward", "--remove", "tcp:19003"],
                "cleanup should remove only the owned mapping")
        require(!calls.flatMap { $0 }.contains("--remove-all"),
                "DisplayWeave must never remove another tool's ADB mappings")
        let remaining = await manager.ownedMappings()
        require(remaining == [second],
                "removing A must leave B owned and active")
        let persistedAfterRemove = await store.records()
        require(persistedAfterRemove == [second],
                "normal cleanup should remove only A from persistent ownership")

        let stale = AndroidAdbForward(sessionID: UUID(), serial: "STALE",
                                      localPort: 19003, remotePort: 9000)
        let staleStore = MemoryForwardStore([stale])
        let staleRunner = RecordingAdbRunner()
        let staleClient = AndroidAdbClient(executable: URL(fileURLWithPath: "/fake/adb"),
                                           runner: staleRunner)
        let staleManager = AndroidAdbForwardManager(
            client: staleClient,
            portAllocator: SequencePortAllocator(ports: [19004]),
            recordStore: staleStore)
        await staleManager.cleanupPersistedMappings()
        let staleCalls = await staleRunner.calls
        require(staleCalls == [["-s", "STALE", "forward", "--remove", "tcp:19003"]],
                "next launch should remove each persisted mapping exactly")
        let persistedAfterRecovery = await staleStore.records()
        require(persistedAfterRecovery.isEmpty,
                "successfully reclaimed mappings should be removed from persistence")
        require(!staleCalls.flatMap { $0 }.contains("--remove-all"),
                "crash recovery must never remove mappings owned by other tools")

        let missing = AndroidAdbForward(sessionID: UUID(), serial: "GONE",
                                        localPort: 19005, remotePort: 9000)
        let missingStore = MemoryForwardStore([missing])
        let missingManager = AndroidAdbForwardManager(
            client: AndroidAdbClient(executable: URL(fileURLWithPath: "/fake/adb"),
                                     runner: MissingListenerRunner()),
            portAllocator: SequencePortAllocator(ports: [19006]),
            recordStore: missingStore)
        await missingManager.cleanupPersistedMappings()
        let missingRecords = await missingStore.records()
        require(missingRecords.isEmpty,
                "an already absent exact listener should count as successfully reclaimed")

        let failedStore = MemoryForwardStore()
        let failedManager = AndroidAdbForwardManager(
            client: AndroidAdbClient(executable: URL(fileURLWithPath: "/fake/adb"),
                                     runner: MissingListenerRunner()),
            portAllocator: SequencePortAllocator(ports: [19007]),
            recordStore: failedStore)
        do {
            _ = try await failedManager.create(serial: "FAIL")
            fatalError("a failed adb forward command must fail session creation")
        } catch {
            let failedRecords = await failedStore.records()
            require(failedRecords.isEmpty,
                    "a synchronous install failure should roll back its ownership record")
        }

        print("AndroidAdbForwardSelfTest PASS")
    }
}
