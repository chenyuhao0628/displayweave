import Foundation

enum ReceiverSceneState: Equatable, Sendable {
    case active
    case inactive
    case background
}

enum ReceiverSceneAction: Equatable, Sendable {
    case startListening
    case stopListening
    case none
}

enum ReceiverSceneLifecyclePolicy {
    static func action(for state: ReceiverSceneState) -> ReceiverSceneAction {
        switch state {
        case .active: return .startListening
        case .inactive: return .none
        case .background: return .stopListening
        }
    }
}
