import SwiftUI
import AVFoundation
import UIKit
import Combine

// MARK: - Shake to open settings

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

// MARK: - Root screen

struct ReceiverScreen: View {
    @StateObject private var model = ReceiverModel()
    @State private var showSettings = false
    @State private var showOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("showAnalytics") private var showAnalytics = false
    @AppStorage("metalRenderer") private var metalRenderer = false
    // First-run onboarding (issue #49): explain the Mac app is required.
    // Shown until either the user dismisses it or the device connects once.
    @AppStorage("hasConnectedBefore") private var hasConnectedBefore = false
    @AppStorage("onboardingDismissed") private var onboardingDismissed = false

    // Streaming = connected and the video format is known.
    private var isStreaming: Bool {
        model.receiver.connected && model.receiver.videoSize != .zero
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if isStreaming {
                    Color.black.ignoresSafeArea()
                    VideoLayerView(displayLayer: model.receiver.displayLayer,
                                   receiver: model.receiver,
                                   useMetal: metalRenderer)
                        .id(metalRenderer)   // rebuild the layer tree on toggle
                        .ignoresSafeArea()
                    if showAnalytics {
                        VStack {
                            Spacer()
                            PerfOverlay(stats: model.receiver.perf,
                                        videoSize: model.receiver.videoSize)
                                .padding(.bottom, 10)
                        }
                        .allowsHitTesting(false)   // never block touch input
                    }
                } else {
                    IdleView(receiver: model.receiver, showSettings: $showSettings)
                }
            }
            .onAppear { model.receiver.setOrientation(portrait: geo.size.height > geo.size.width) }
            .onChange(of: geo.size) { _, size in
                model.receiver.setOrientation(portrait: size.height > size.width)
            }
            .sheet(isPresented: $showOnboarding) {
                OnboardingView { onboardingDismissed = true }
            }
        }
        .ignoresSafeArea(edges: isStreaming ? .all : [])
        .overlay(alignment: .topTrailing) {
            if isStreaming {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("设置与帮助")
                .padding(12)
            }
        }
        .statusBarHidden(isStreaming)
        .persistentSystemOverlays(isStreaming ? .hidden : .automatic)
        .sheet(isPresented: $showSettings) {
            SettingsView(receiver: model.receiver)
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            showSettings = true
        }
        .onChange(of: scenePhase) { _, phase in
            let state: ReceiverSceneState
            switch phase {
            case .active: state = .active
            case .inactive: state = .inactive
            case .background: state = .background
            @unknown default: state = .inactive
            }
            switch ReceiverSceneLifecyclePolicy.action(for: state) {
            case .startListening: model.receiver.ensureListening()
            case .stopListening: model.receiver.stop()
            case .none: break
            }
        }
        .onChange(of: model.receiver.connected) { _, isConnected in
            // The first valid connection retires the onboarding hint for good.
            if isConnected {
                hasConnectedBefore = true
                showOnboarding = false
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            model.start()
            // Show the first-run hint unless the device has connected before
            // or the user already dismissed it.
            if !hasConnectedBefore && !onboardingDismissed {
                showOnboarding = true
            }
        }
    }
}
