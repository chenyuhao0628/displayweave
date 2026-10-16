import Foundation
import CoreFoundation

enum PencilGestureAction: String, CaseIterable {
    case system, none, toggleEraser, undo, redo, shortcut1, shortcut2
    func resolve(system: Self) -> Self { self == .system ? (system == .system ? .none : system) : self }
    var label: String {
        switch self {
        case .system: return "跟随系统（支持画笔／橡皮切换）"
        case .none: return "无操作"
        case .toggleEraser: return "切换画笔／橡皮"
        case .undo: return "撤销（⌘Z）"
        case .redo: return "重做（⇧⌘Z）"
        case .shortcut1: return "发送端自定义快捷键 1"
        case .shortcut2: return "发送端自定义快捷键 2"
        }
    }
}

enum PencilRemoteAction: String { case undo, redo, shortcut1, shortcut2 }

struct PencilGestureDeduplicator {
    private var last: TimeInterval = -1
    mutating func accept(_ timestamp: TimeInterval) -> Bool {
        guard timestamp.isFinite, timestamp >= 0, timestamp > last else { return false }
        last = timestamp; return true
    }
}

struct PencilShortcut: Equatable {
    let keyCode: UInt16
    let modifiers: Int
    init?(keyCode: Int, modifiers: Int) {
        guard (0...127).contains(keyCode), ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode),
              (0...15).contains(modifiers) else { return nil }
        self.keyCode = UInt16(keyCode); self.modifiers = modifiers
    }
    static func configured(_ action: PencilRemoteAction, defaults: UserDefaults = .standard) -> Self? {
        switch action {
        case .undo: return Self(keyCode: 6, modifiers: 8)
        case .redo: return Self(keyCode: 6, modifiers: 9)
        case .shortcut1, .shortcut2:
            let slot = action == .shortcut1 ? 1 : 2
            let key = defaults.object(forKey: "pencilShortcut\(slot)Key") as? Int ?? (slot == 1 ? 14 : 11)
            let modifiers = defaults.object(forKey: "pencilShortcut\(slot)Modifiers") as? Int ?? 0
            return Self(keyCode: key, modifiers: modifiers)
        }
    }
}

struct PencilActionMessage {
    let session: String
    let sequence: UInt64
    let action: PencilRemoteAction
    init?(_ data: Data) {
        guard data.count <= 4096,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "pencilAction",
              let session = object["inputSession"] as? String, UUID(uuidString: session) != nil,
              let action = (object["action"] as? String).flatMap(PencilRemoteAction.init(rawValue:)),
              let n = object["sequence"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, (1...9_007_199_254_740_991).contains(n.doubleValue),
              n.doubleValue.rounded(.towardZero) == n.doubleValue else { return nil }
        self.session = session; sequence = n.uint64Value; self.action = action
    }
}
