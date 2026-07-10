import SwiftUI
import AppKit
import MetalKit

/// Debug aid: a full-screen animated window on the virtual display so the
/// pipeline streams continuously — without it, ScreenCaptureKit emits nothing
/// while the screen is static and steady-state latency can't be measured.
/// Enable with `defaults write sh.peet.opensidecar.mac testPattern -bool true`.
@MainActor
enum TestPattern {
    // One window per virtual display — multi-device sessions each get their
    // own pattern, so all pipelines stream at once during measurements.
    private static var windows: [CGDirectDisplayID: NSWindow] = [:]

    static func show(on displayID: CGDirectDisplayID) {
        hide(on: displayID)
        // The screen may register a beat after the virtual display appears.
        Task { @MainActor in
            for _ in 0..<10 {
                if let screen = NSScreen.screens.first(where: {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
                }) {
                    let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless],
                                     backing: .buffered, defer: false)
                    w.contentView = DisplayLinkPatternView(displayID: displayID)
                    w.setFrame(screen.frame, display: true)
                    w.orderFrontRegardless()
                    windows[displayID] = w
                    Log.info("test pattern window shown on display \(displayID)")
                    return
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
            Log.info("test pattern: screen for display \(displayID) never appeared")
        }
    }

    static func hide(on displayID: CGDirectDisplayID) {
        windows.removeValue(forKey: displayID)?.orderOut(nil)
    }
}

private final class DisplayLinkPatternView: MTKView, MTKViewDelegate {
    private lazy var commandQueue = device?.makeCommandQueue()

    init(displayID: CGDirectDisplayID) {
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        delegate = self
        preferredFramesPerSecond = 120
        enableSetNeedsDisplay = false
        isPaused = false
        framebufferOnly = true
        colorPixelFormat = .bgra8Unorm
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let commandQueue,
              let pass = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let t = ProcessInfo.processInfo.systemUptime
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: 0.45 + sin(t * 1.7) * 0.35,
            green: 0.45 + cos(t * 2.3) * 0.35,
            blue: 0.65,
            alpha: 1)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
