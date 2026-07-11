import Foundation

enum KeyframePolicy {
    static func candidateSeconds(transport: BitrateTransport) -> [Int] {
        transport == .wifi ? [1, 2, 3] : [1, 2]
    }

    static func defaultSeconds(transport: BitrateTransport) -> Int {
        transport == .wifi ? 2 : 1
    }

    static func frameInterval(fps: Int, transport: BitrateTransport) -> Int {
        RefreshRatePolicy.sanitize(fps) * defaultSeconds(transport: transport)
    }
}
