import Foundation
import Combine

enum MacRole: String, CaseIterable {
    case sender, receiver
    var label: String { self == .sender ? "发送屏幕" : "接收屏幕" }
}

@MainActor
protocol MacRoleService: AnyObject {
    func start()
    func stop(completion: (() -> Void)?)
}

/// Injected services let lifecycle tests verify exclusivity while cleanup is
/// suspended. The next role never starts before the old role reports completion.
@MainActor
final class MacRoleController: ObservableObject {
    @Published private(set) var role: MacRole
    @Published private(set) var transitioning = false
    private let senderService: MacRoleService
    private let receiverService: MacRoleService
    private let persist: (MacRole) -> Void

    init(initialRole: MacRole, sender: MacRoleService, receiver: MacRoleService,
         persist: @escaping (MacRole) -> Void) {
        role = initialRole
        senderService = sender
        receiverService = receiver
        self.persist = persist
        (initialRole == .sender ? sender : receiver).start()
    }

    func select(_ next: MacRole) {
        guard next != role, !transitioning else { return }
        transitioning = true
        let old = role == .sender ? senderService : receiverService
        old.stop { [weak self] in
            guard let self else { return }
            (next == .sender ? self.senderService : self.receiverService).start()
            self.role = next
            self.persist(next)
            self.transitioning = false
        }
    }
}
