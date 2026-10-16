import SwiftUI

struct PencilSettingsSection: View {
    @ObservedObject var receiver: PhoneReceiver
    var body: some View {
        Section("Apple Pencil") {
            LabeledContent("输入模式", value: receiver.pencilExtendedAvailable ? "压感、倾角、旋转与工具" : receiver.pencilAvailable ? "压感与倾角" : "兼容触控")
            Text("支持的 iPad 可传递压感、倾角和悬停；Mac 需授予辅助功能权限，绘图软件需支持数位笔输入。旧版 Mac 使用普通触控，当前笔画结束后再应用新能力。")
                .font(.caption).foregroundStyle(.secondary)
            Picker("工具", selection: Binding(get: { receiver.selectedPencilTool }, set: { receiver.selectPencilTool($0) })) {
                Text("画笔").tag(PencilTool.pen)
                Text("橡皮").tag(PencilTool.eraser)
            }.disabled(!receiver.pencilExtendedAvailable)
            PencilGestureSettings()
            Text(receiver.pencilActionStatus).font(.caption).foregroundStyle(.secondary)
            Text("旋转／挤压需要相应 Pencil 硬件与 iPadOS 17.5。高级模式仅用于加密连接；快捷键还需 Mac 单独许可。工具和快捷键效果取决于 Mac 当前应用。系统其他手势偏好不转发。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct PencilGestureSettings: View {
    @AppStorage("pencilDoubleTapAction") private var doubleTap = PencilGestureAction.system
    @AppStorage("pencilSqueezeAction") private var squeeze = PencilGestureAction.system
    var body: some View {
        Picker("双击", selection: $doubleTap) {
            ForEach(PencilGestureAction.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        Picker("挤压", selection: $squeeze) {
            ForEach(PencilGestureAction.allCases, id: \.self) { Text($0.label).tag($0) }
        }
    }
}
