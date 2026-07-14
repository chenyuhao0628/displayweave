import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum MacSenderTestPatternContractSelfTest {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = try String(
            contentsOf: root.appendingPathComponent("Mac/MacSender.swift"),
            encoding: .utf8)

        expect(source.contains("private let testPatternOwnerID = UUID()"),
               "each sender owns one stable test-pattern identity")
        expect(source.contains("TestPattern.show(ownerID: testPatternOwnerID"),
               "test-pattern creation is associated with the sender owner")

        let reconfigure = section(
            source, from: "private func reconfigure", to: "private func findSCDisplay")
        expect(hidesBeforeDisplayRelease(reconfigure),
               "rotation hides the old pattern before releasing its display")

        let stop = section(source, from: "func stop()", to: "func startBenchmark")
        expect(hidesBeforeDisplayRelease(stop),
               "disconnect hides the pattern before releasing its display")

        expect(source.contains("private var connectionGeneration: UInt64 = 0"),
               "NWConnection callbacks have an independent generation")
        expect(source.contains("private var reconnectWorkItem: DispatchWorkItem?"),
               "delayed reconnect work is cancellable and coalesced")
        expect(source.contains("self.isCurrentConnection(conn, generation: generation)"),
               "TCP state callbacks validate connection object and generation")
        expect(source.contains("let connectionGeneration = self.adoptConnection(conn)"),
               "an adopted USB connection receives its own callback generation")
        expect(source.contains("self.becomeReady(conn, generation: connectionGeneration)"),
               "USB readiness is gated by the adopted connection generation")
        expect(source.contains("receiveControl(on conn: NWConnection, generation: UInt64)"),
               "control reads carry the adopted connection generation")
        expect(source.contains("guard reconnectWorkItem == nil else"),
               "duplicate reconnect requests are coalesced")
        expect(stop.contains("cancelPendingReconnect()"),
               "stop cancels and invalidates delayed reconnect work")

        print("MacSenderTestPatternContractSelfTest PASS")
    }

    private static func section(_ source: String, from start: String, to end: String) -> String {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            return ""
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private static func hidesBeforeDisplayRelease(_ source: String) -> Bool {
        guard let hide = source.range(of: "TestPattern.hide(ownerID: testPatternOwnerID)"),
              let release = source.range(of: "virtualDisplay = nil") else {
            return false
        }
        return hide.lowerBound < release.lowerBound
    }
}
