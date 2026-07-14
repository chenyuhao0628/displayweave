import Foundation
import CoreGraphics

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
@MainActor
enum TestPatternLifecycleSelfTest {
    static func main() async {
        let ownerID = UUID()
        let missingDisplayID = CGDirectDisplayID.max

        TestPattern.show(ownerID: ownerID, on: missingDisplayID)
        expect(TestPattern.isTracking(ownerID: ownerID),
               "show tracks a pending test-pattern window")

        TestPattern.hide(ownerID: ownerID)
        expect(!TestPattern.isTracking(ownerID: ownerID),
               "hide cancels a pending test-pattern window")

        try? await Task.sleep(for: .seconds(4))
        expect(!TestPattern.isTracking(ownerID: ownerID),
               "a cancelled asynchronous show cannot recreate the window")

        print("TestPatternLifecycleSelfTest PASS")
    }
}
