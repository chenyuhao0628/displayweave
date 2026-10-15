import Foundation

enum Log {
    private static let writer = BoundedLogWriter(url:
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("opensidecar-phone.log")) { NSLog("[displayweave] %@", $0) }
    static func info(_ message: String) { writer.info(message) }
}
