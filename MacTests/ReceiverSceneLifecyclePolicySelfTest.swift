import Foundation

private func check<T: Equatable>(_ expected: T, _ actual: T, _ message: String) {
    if expected != actual {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

@main
struct ReceiverSceneLifecyclePolicySelfTest {
    static func main() {
        check(.startListening,
              ReceiverSceneLifecyclePolicy.action(for: .active),
              "the foreground receiver must listen")
        check(.none,
              ReceiverSceneLifecyclePolicy.action(for: .inactive),
              "temporary interruptions must not tear down the display")
        check(.stopListening,
              ReceiverSceneLifecyclePolicy.action(for: .background),
              "backgrounding must close the receiver connection")
        print("ReceiverSceneLifecyclePolicySelfTest PASS")
    }
}
