import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case assertion(String)
    var description: String {
        switch self { case let .assertion(message): return message }
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure.assertion(message) }
}

private func sample(runId: String, sessionId: String = "session,\"one\"") -> BenchmarkSample {
    let receiver = try! JSONDecoder().decode(
        ReceiverStats.self,
        from: Data(#"{"type":"stats","receivedFps":118.8,"decodedFps":118.7,"renderedFps":118.5}"#.utf8))
    return BenchmarkSample(
        timestamp: Date(timeIntervalSince1970: 1_700_000_000.125),
        monotonicElapsed: .milliseconds(1234), runId: runId, sessionId: sessionId,
        scene: "detail", phase: "steady", deviceModel: "Pixel 9", transport: "USB",
        codec: "h265", resolution: .init(width: 2560, height: 1600), requestedFps: 120,
        actualVirtualDisplayRefreshRate: 120, captureFps: 119.5, encodedFps: 119.2,
        sentFps: 119, receiver: receiver, targetBitrateMbps: 35,
        encodeLatencyMs: 3.25, pendingSends: 1, macQueue: 2, macDrops: 0,
        macCPU: 18.5, macMemory: 512
    )
}

private func expectRecorderError(_ operation: () throws -> Void, containing text: String) throws {
    do {
        try operation()
        throw TestFailure.assertion("Expected BenchmarkRecorderError containing \(text)")
    } catch let error as BenchmarkRecorderError {
        try require(String(describing: error).contains(text), "Unexpected recorder error: \(error)")
    }
}

@main
struct BenchmarkRecorderSelfTest {
static func main() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("BenchmarkRecorderSelfTest-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let recorder = BenchmarkRecorder(rootURL: root)
    try expectRecorderError({ try recorder.append(sample(runId: "not-started")) }, containing: "notStarted")

    try recorder.start(runId: "run-one")
    try expectRecorderError({ try recorder.start(runId: "other") }, containing: "alreadyStarted")
    try recorder.append(sample(runId: "run-one"))
    let first = try recorder.stop()
    try require(first.csvURL.lastPathComponent == "benchmark.csv", "Wrong CSV URL")
    try require(first.jsonlURL.lastPathComponent == "benchmark.jsonl", "Wrong JSONL URL")

    let csv = try String(contentsOf: first.csvURL, encoding: .utf8)
    try require(csv.hasSuffix("\r\n"), "CSV records must end in CRLF")
    let records = csv.components(separatedBy: "\r\n").dropLast()
    try require(records.count == 2, "CSV must contain exactly header plus one data record")
    try require(records[0] == BenchmarkSample.csvHeader.joined(separator: ","), "CSV header mismatch")
    try require(records[1].contains("\"session,\"\"one\"\"\""), "CSV field was not escaped")

    let jsonlData = try Data(contentsOf: first.jsonlURL)
    try require(jsonlData.last == 0x0A, "JSONL record must end in LF")
    let jsonLines = String(decoding: jsonlData, as: UTF8.self).split(separator: "\n")
    try require(jsonLines.count == 1, "JSONL must contain exactly one object")
    let object = try JSONSerialization.jsonObject(with: Data(jsonLines[0].utf8)) as? [String: Any]
    try require(object?["runId"] as? String == "run-one", "JSONL runId mismatch")

    try recorder.start(runId: "empty-run")
    let empty = try recorder.stop()
    let emptyCSV = try String(contentsOf: empty.csvURL, encoding: .utf8)
    try require(emptyCSV == BenchmarkSample.csvHeader.joined(separator: ",") + "\r\n", "Empty run must contain header only")
    let emptyJSONL = try Data(contentsOf: empty.jsonlURL)
    try require(emptyJSONL.isEmpty, "Empty run JSONL must remain empty")
    try require(first.csvURL.deletingLastPathComponent() != empty.csvURL.deletingLastPathComponent(), "Runs must be independent")

    try expectRecorderError({ _ = try recorder.stop() }, containing: "notStarted")
    for unsafe in ["../escape", "..", "a/b", "a\\b", ""] {
        try expectRecorderError({ try recorder.start(runId: unsafe) }, containing: "invalidRunId")
    }

    try FileManager.default.createDirectory(at: root.appendingPathComponent("existing"), withIntermediateDirectories: true)
    try expectRecorderError({ try recorder.start(runId: "existing") }, containing: "runDirectoryExists")

    let fileRoot = root.appendingPathComponent("not-a-directory")
    try Data("x".utf8).write(to: fileRoot)
    let broken = BenchmarkRecorder(rootURL: fileRoot)
    try expectRecorderError({ try broken.start(runId: "run") }, containing: "fileOperationFailed")

    for iteration in 0..<20 {
        let runId = "concurrent-\(iteration)"
        let firstRecorder = BenchmarkRecorder(rootURL: root)
        let secondRecorder = BenchmarkRecorder(rootURL: root)
        let startGate = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        let lock = NSLock()
        var successes = 0
        for concurrentRecorder in [firstRecorder, secondRecorder] {
            group.enter()
            DispatchQueue.global().async {
                startGate.wait()
                if (try? concurrentRecorder.start(runId: runId)) != nil {
                    lock.lock(); successes += 1; lock.unlock()
                }
                group.leave()
            }
        }
        startGate.signal(); startGate.signal(); group.wait()
        try require(successes == 1, "Exactly one concurrent recorder may own a run directory")
        if successes == 1 {
            _ = try? firstRecorder.stop()
            _ = try? secondRecorder.stop()
        }
    }
    print("BenchmarkRecorderSelfTest passed")
}
}
