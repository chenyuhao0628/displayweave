import Foundation

@MainActor private final class Service: MacRoleService {
    var active = false
    var starts = 0
    var stopCompletion: (() -> Void)?
    var mayStart: () -> Bool = { true }
    func start() { precondition(mayStart(), "roles overlapped"); active = true; starts += 1 }
    func stop(completion: (() -> Void)?) { stopCompletion = completion }
    func finishStop() { active = false; let completion = stopCompletion; stopCompletion = nil; completion?() }
}

@main struct MacRoleControllerSelfTest {
    @MainActor static func main() {
        let sender = Service(), receiver = Service()
        sender.mayStart = { !receiver.active }
        receiver.mayStart = { !sender.active }
        var persisted: [MacRole] = []
        let controller = MacRoleController(initialRole: .sender, sender: sender, receiver: receiver) { persisted.append($0) }
        precondition(sender.active && !receiver.active)
        controller.select(.receiver)
        precondition(controller.transitioning && !receiver.active)
        controller.select(.receiver)
        controller.select(.sender)
        sender.finishStop()
        precondition(!controller.transitioning && receiver.active && !sender.active)
        controller.select(.sender)
        precondition(!sender.active && controller.transitioning)
        receiver.finishStop()
        precondition(sender.active && !receiver.active && sender.starts == 2)
        precondition(persisted == [.receiver, .sender])
        let s2 = Service(), r2 = Service()
        _ = MacRoleController(initialRole: .receiver, sender: s2, receiver: r2) { _ in }
        precondition(r2.active && s2.starts == 0)
        print("Mac role exclusivity, delayed cleanup, repeated selection and saved role PASS")
    }
}
