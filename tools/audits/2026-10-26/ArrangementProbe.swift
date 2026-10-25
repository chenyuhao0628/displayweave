// Snapshot reproducer: see docs/code-and-experience-audit-2026-10-26.md.
import Foundation
import CoreGraphics
@main struct ArrangementProbe {
    static func main() {
        let suite = "DisplayWeave.code-review.arrangement.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let neighbor = CGRect(x: 0, y: 1080, width: 1920, height: 1080)
        let saved = CGRect(x: 1920, y: 1580, width: 1080, height: 1920)
        let rotated = CGSize(width: 1920, height: 1080)
        DisplayArrangement.save(origin: saved.origin, size: saved.size,
            device: "fixture", defaults: defaults, mainBounds: main)
        let actual = DisplayArrangement.origin(for: rotated, device: "fixture", defaults: defaults,
            mainBounds: main, displays: [main, neighbor])!
        let respectingActualNeighbor = DisplayArrangement.remappedOrigin(from: saved, to: rotated, against: [main, neighbor])
        print("Saved display shares an edge with lower external display, not main display")
        print("Production restore origin: \(actual); actual-neighbor remap: \(respectingActualNeighbor)")
        precondition(actual.y == 1080 && respectingActualNeighbor.y == 1580)
    }
}
