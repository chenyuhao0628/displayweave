import Foundation

/// App-managed migration; signing identity remains independent of feed hosting.
enum UpdateFeedPolicy {
    static let canonical = "https://downloads.urlget.cyou/displayweave/appcast.xml"
    static let legacy = "https://chenyuhao0628.github.io/displayweave/appcast.xml"
}
