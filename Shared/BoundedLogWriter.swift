import Foundation

/// Bounded asynchronous diagnostics, inspired by OpenDisplay 19481a6 (GPL-3.0).
/// Limits both queued work and disk growth; logging failures never stop streaming.
final class BoundedLogWriter: @unchecked Sendable {
    private let url: URL
    private let maxFileBytes: Int
    private let maxEntryBytes: Int
    private let maxPendingLines: Int
    private let output: ((String) -> Void)?
    private let queue = DispatchQueue(label: "displayweave.log")
    private let lock = NSLock()
    private var pending = 0
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    init(url: URL, maxFileBytes: Int = 2 * 1024 * 1024, maxEntryBytes: Int = 8192,
         maxPendingLines: Int = 256, output: ((String) -> Void)? = nil) {
        self.url = url
        self.maxFileBytes = max(128, maxFileBytes)
        self.maxEntryBytes = min(max(64, maxEntryBytes), max(128, maxFileBytes))
        self.maxPendingLines = max(1, maxPendingLines)
        self.output = output
    }

    func info(_ message: String) {
        lock.lock()
        guard pending < maxPendingLines else { lock.unlock(); return }
        pending += 1
        lock.unlock()
        // Copy a bounded value before dispatch so a large caller message cannot
        // turn the pending-line limit into an unbounded retained-memory queue.
        let boundedMessage = String(decoding: message.utf8.prefix(maxEntryBytes), as: UTF8.self)
        let time = Date()
        queue.async {
            defer {
                self.lock.lock(); self.pending -= 1; self.lock.unlock()
            }
            let line = "[\(self.formatter.string(from: time))] \(boundedMessage)"
            var bytes = Data(line.utf8.prefix(self.maxEntryBytes - 1))
            while String(data: bytes, encoding: .utf8) == nil { bytes.removeLast() }
            bytes.append(10)
            self.output?(String(decoding: bytes, as: UTF8.self))
            self.append(bytes)
        }
    }

    private func append(_ bytes: Data) {
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path) {
            guard manager.createFile(atPath: url.path, contents: nil,
                                     attributes: [.posixPermissions: 0o600]) else { return }
        }
        do {
            let handle = try FileHandle(forUpdating: url)
            defer { try? handle.close() }
            let size = try handle.seekToEnd()
            if size + UInt64(bytes.count) > UInt64(maxFileBytes) {
                // Bound even an oversized file created by an older app version.
                try handle.seek(toOffset: size > UInt64(maxFileBytes) ? size - UInt64(maxFileBytes) : 0)
                let previous = try handle.read(upToCount: maxFileBytes) ?? Data()
                try previous.write(to: url.appendingPathExtension("previous"), options: .atomic)
                try handle.truncate(atOffset: 0)
                try handle.seek(toOffset: 0)
            }
            try handle.write(contentsOf: bytes)
        } catch { /* diagnostics are best effort */ }
    }

    /// Deterministic test / export boundary; never call from the writer queue.
    func flush() { queue.sync {} }
}
