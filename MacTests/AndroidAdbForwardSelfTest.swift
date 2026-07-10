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

@main
struct AndroidAdbForwardSelfTest {
    static func main() async throws {
        let runner = RecordingAdbRunner()
        let client = AndroidAdbClient(executable: URL(fileURLWithPath: "/fake/adb"),
                                      runner: runner)
        let manager = AndroidAdbForwardManager(
            client: client,
            portAllocator: SequencePortAllocator(ports: [19001, 19002]))

        let first = try await manager.create(serial: "A")
        let second = try await manager.create(serial: "B")
        require(first.localPort == 19001 && second.localPort == 19002,
                "each Android device should receive an independent local port")
        require(first.remotePort == 9000 && second.remotePort == 9000,
                "both mappings should target the existing Android receiver port")
        var calls = await runner.calls
        require(calls[0] == ["-s", "A", "forward", "tcp:19001", "tcp:9000"],
                "first mapping should be scoped to serial A")
        require(calls[1] == ["-s", "B", "forward", "tcp:19002", "tcp:9000"],
                "second mapping should be scoped to serial B")

        await manager.remove(sessionID: first.sessionID)
        calls = await runner.calls
        require(calls.last == ["-s", "A", "forward", "--remove", "tcp:19001"],
                "cleanup should remove only the owned mapping")
        require(!calls.flatMap { $0 }.contains("--remove-all"),
                "DisplayWeave must never remove another tool's ADB mappings")
        let remaining = await manager.ownedMappings()
        require(remaining == [second],
                "removing A must leave B owned and active")

        print("AndroidAdbForwardSelfTest PASS")
    }
}
