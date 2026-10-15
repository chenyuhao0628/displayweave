import Foundation

/// Keep the compatibility log path used by the local run/debug scripts.
enum Log {
    private static let writer = BoundedLogWriter(url: URL(fileURLWithPath: "/tmp/opensidecar-mac.log")) {
        print($0, terminator: "")
    }
    static func info(_ message: String) { writer.info(message) }
}
