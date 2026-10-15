import Foundation

@main struct BoundedLogWriterSelfTest {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.log")
        let logger = BoundedLogWriter(url: url, maxFileBytes: 1024, maxEntryBytes: 128, maxPendingLines: 8)
        for i in 0..<50 { logger.info("entry \(i) " + String(repeating: "字", count: 500)); logger.flush() }
        for path in [url, url.appendingPathExtension("previous")] {
            let bytes = try Data(contentsOf: path)
            precondition(bytes.count <= 1024 && !bytes.isEmpty, "log exceeded bound")
            precondition(String(data: bytes, encoding: .utf8) != nil, "UTF-8 entry was cut mid-scalar")
        }
        let before = try Data(contentsOf: url)
        logger.info("last marker"); logger.flush()
        let last = try String(contentsOf: url, encoding: .utf8)
        precondition(last.contains("last marker"))
        precondition(!before.isEmpty)
        DispatchQueue.concurrentPerform(iterations: 2000) { i in logger.info("concurrent \(i)") }
        logger.flush()
        let concurrent = try Data(contentsOf: url)
        precondition(concurrent.count <= 1024)
        print("Bounded log: rotation, UTF-8 truncation, concurrent writers and queue pressure PASS")
    }
}
