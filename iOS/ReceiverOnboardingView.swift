import SwiftUI
import AVFoundation
import UIKit
import Combine

// MARK: - First-run onboarding (the Mac app is required to connect)

/// Shown on first launch / while the device has never connected: OpenDisplay
/// is two apps, and the iOS side is useless without the Mac app running.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "laptopcomputer.and.iphone")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.tint)
                        .padding(.top, 24)

                    VStack(spacing: 10) {
                        Text("准备好你的 Mac")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text("DisplayWeave 可以把这台 \(deviceKind) 变成 Mac 的第二块屏幕，但需要在通过同一根 USB 线连接、或处于同一局域网的 Mac 上运行 **DisplayWeave 或 OpenDisplay Mac 端 app**。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ConnectionSetupGuide()
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

                    Link(destination: macAppURL) {
                        Label("获取 Mac 端 app", systemImage: "arrow.down.circle")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)

                    Text("之后也可以在设置里找到这个链接，点按设置按钮或摇动这台 \(deviceKind) 即可打开设置。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 520)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .tint(.blue)
            .navigationTitle("欢迎")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") {
                        onClose()
                        dismiss()
                    }
                }
            }
        }
    }
}
