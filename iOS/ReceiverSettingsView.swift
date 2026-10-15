import SwiftUI
import AVFoundation
import UIKit
import Combine

// MARK: - Settings / help sheet

struct SettingsView: View {
    @ObservedObject var receiver: PhoneReceiver
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showAnalytics") private var showAnalytics = false
    @AppStorage("metalRenderer") private var metalRenderer = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("状态") {
                    LabeledContent("监听", value: "端口 9000")
                    LabeledContent("连接",
                                   value: receiver.connected ? "已连接" : "正在等待 Mac")
                    if receiver.videoSize != .zero {
                        LabeledContent("画面",
                                       value: "\(Int(receiver.videoSize.width))×\(Int(receiver.videoSize.height)) @ \(receiver.fps) fps")
                    }
                }

                Section {
                    // Isolated from the receiver: the Status section above
                    // re-renders on every stream update, and a TextField that
                    // rebuilds mid-tap loses focus (the "tap twice to edit"
                    // bug). This subview owns its focus and doesn't observe
                    // the receiver, so it survives those rebuilds.
                    DeviceNameField { receiver.setServiceName($0) }
                } header: {
                    Text("名称")
                } footer: {
                    Text("此名称会显示在 Mac 端的 局域网设备列表里。iOS 不允许 app 读取这台 \(deviceKind) 的真实设备名，所以请在这里设置一次。")
                }

                Section {
                    Toggle("性能浮层", isOn: $showAnalytics)
                    Toggle("Metal 渲染器（实验性）", isOn: $metalRenderer)
                } header: {
                    Text("性能分析")
                } footer: {
                    Text("性能浮层会在串流时显示 FPS、码率、帧间隔、卡顿和延迟图表。实验性 Metal 渲染器会手动解码并显示帧，可额外显示解码和真实上屏延迟；但实测系统视频层更快，除非调试，否则建议关闭。")
                }

                Section {
                    Button("打开 DisplayWeave 的 iOS 设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } header: {
                    Text("权限")
                } footer: {
                    Text("局域网模式需要“本地网络”权限。如果 Mac 找不到这台 \(deviceKind)，请到“设置”→“隐私与安全性”→“本地网络”中允许 DisplayWeave。USB 模式不需要此权限。")
                }

                Section {
                    Label("USB：插上线并运行 Mac 端 app，它会自动通过线缆连接，可减少无线网络干扰。",
                          systemImage: "cable.connector")
                    Label("局域网：两台设备连接到同一网络，然后在 Mac 端连接菜单中选择这台 \(deviceKind)。",
                          systemImage: "wifi")
                    Label("旋转这台 \(deviceKind)，即可作为竖屏第二显示器使用。",
                          systemImage: "rectangle.portrait.rotate")
                    Label("触摸：轻点=点击，拖动=拖拽，双指滑动=滚动。",
                          systemImage: "hand.tap")
                } header: {
                    Text("如何连接")
                }

                Section {
                    Link(destination: macAppURL) {
                        Label("获取 Mac 端 app", systemImage: "arrow.down.circle")
                    }
                } footer: {
                    Text("DisplayWeave 需要 Mac 端 app 在同一根线缆或同一局域网 网络中的 Mac 上运行。如果还没有安装，可以从这里下载。")
                }

                Section("关于") {
                    LabeledContent("版本", value: version)
                    Link(destination: URL(string: "https://github.com/chenyuhao0628/displayweave")!) {
                        Label("GitHub — chenyuhao0628/displayweave", systemImage: "link")
                    }
                    Link(destination: macAppURL) {
                        Label("官网", systemImage: "globe")
                    }
                }
            }
            .navigationTitle("DisplayWeave")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

/// The device-name editor, deliberately kept out of any high-frequency
/// @ObservedObject so streaming updates can't rebuild it and steal focus.
private struct DeviceNameField: View {
    @AppStorage("deviceName") private var deviceName = UIDevice.current.name
    @FocusState private var focused: Bool
    let onChange: (String) -> Void

    var body: some View {
        TextField("设备名称", text: $deviceName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .focused($focused)
            .onChange(of: deviceName) { _, name in onChange(name) }
    }
}
