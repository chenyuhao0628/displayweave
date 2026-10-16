import SwiftUI

struct PencilShortcutSettings: View {
    @AppStorage("allowPencilShortcuts") private var enabled = false
    var body: some View {
        Section("Pencil 快捷键") {
            Toggle("允许 Pencil 手势执行快捷键", isOn: $enabled)
            Text("默认关闭。需要加密配对与辅助功能权限；在 iPad 为双击／挤压选择撤销、重做或自定义槽位。快捷键作用于此 Mac 的当前应用。")
                .font(.caption).foregroundStyle(.secondary)
            if enabled {
                PencilShortcutSlot(slot: 1)
                PencilShortcutSlot(slot: 2)
                Text("键名对应 Mac 物理键位；布局与输入法沿用发送端。默认槽位为 E 和 B，请按绘图应用的快捷键修改。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PencilShortcutSlot: View {
    let slot: Int
    @AppStorage private var key: Int
    @AppStorage private var modifiers: Int
    init(slot: Int) {
        self.slot = slot
        _key = AppStorage(wrappedValue: slot == 1 ? 14 : 11, "pencilShortcut\(slot)Key")
        _modifiers = AppStorage(wrappedValue: 0, "pencilShortcut\(slot)Modifiers")
    }
    private static let keys: [(Int, String)] = [
        (0,"A"),(11,"B"),(8,"C"),(2,"D"),(14,"E"),(3,"F"),(5,"G"),(4,"H"),(34,"I"),(38,"J"),(40,"K"),
        (37,"L"),(46,"M"),(45,"N"),(31,"O"),(35,"P"),(12,"Q"),(15,"R"),(1,"S"),(17,"T"),(32,"U"),
        (9,"V"),(13,"W"),(7,"X"),(16,"Y"),(6,"Z"),
        (29,"0"),(18,"1"),(19,"2"),(20,"3"),(21,"4"),(23,"5"),(22,"6"),(26,"7"),(28,"8"),(25,"9"),
        (27,"−"),(24,"="),(33,"["),(30,"]"),(42,"\\"),(41,";"),(39,"'"),(43,","),(47,"."),(44,"/"),(50,"`"),
        (49,"空格"),(36,"Return"),(48,"Tab"),(53,"Escape"),(51,"Delete"),
        (123,"←"),(124,"→"),(125,"↓"),(126,"↑"),
        (122,"F1"),(120,"F2"),(99,"F3"),(118,"F4"),(96,"F5"),(97,"F6"),(98,"F7"),(100,"F8"),
        (101,"F9"),(109,"F10"),(103,"F11"),(111,"F12")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("自定义快捷键 \(slot)", selection: $key) {
                ForEach(Self.keys, id: \.0) { item in Text(item.1).tag(item.0) }
            }
            HStack {
                modifier("⇧", label: "Shift", bit: 1)
                modifier("⌃", label: "Control", bit: 2)
                modifier("⌥", label: "Option", bit: 4)
                modifier("⌘", label: "Command", bit: 8)
            }
        }
    }
    private func modifier(_ title: String, label: String, bit: Int) -> some View {
        Toggle(title, isOn: Binding(get: { modifiers & bit != 0 }, set: { value in
            modifiers = value ? modifiers | bit : modifiers & ~bit
        })).toggleStyle(.checkbox).accessibilityLabel(label)
    }
}
