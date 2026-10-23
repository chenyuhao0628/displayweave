import CoreGraphics
import Foundation

/// Bounded OS queries used by the upstream 5de4252 unit-collision recovery.
enum DisplayTopology {
    static func onlineUnits() -> [DisplayUnitIdentity] {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 256)
        guard CGGetOnlineDisplayList(256, &ids, &count) == .success else { return [] }
        return ids.prefix(min(Int(count), ids.count)).map {
            DisplayUnitIdentity(displayID: $0, unit: CGDisplayUnitNumber($0))
        }
    }

    static func isOnline(_ id: CGDirectDisplayID) -> Bool {
        onlineUnits().contains { $0.displayID == id }
    }

    static func settledUnit(_ id: CGDirectDisplayID) async throws -> DisplayUnitIdentity {
        for _ in 0..<40 {
            try Task.checkCancellation()
            if let match = onlineUnits().first(where: { $0.displayID == id }), match.unit != UInt32.max { return match }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw DisplayUnitCoordinator.failure("虚拟显示器尚未就绪，请重新连接；若持续失败，请解锁 Mac 后重试。")
    }

    static func waitUntilOffline(_ ids: [UInt32]) async throws {
        for _ in 0..<60 {
            try Task.checkCancellation()
            let online = Set(onlineUnits().map(\.displayID))
            if ids.allSatisfy({ !online.contains($0) }) { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw DisplayUnitCoordinator.failure("旧虚拟显示器尚未释放，请断开相关会话后重新连接。")
    }
}
