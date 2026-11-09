#if DEBUG
import SwiftUI
import AppKit
import MetalKit
import QuartzCore

/// Debug aid: a full-screen animated window on the virtual display so the
/// pipeline streams continuously — without it, ScreenCaptureKit emits nothing
/// while the screen is static and steady-state latency can't be measured.
/// Enable with `defaults write app.displayweave.mac.debug testPattern -bool true`.
@MainActor
enum TestPattern {
    private struct PendingShow {
        let generation: UUID
        let task: Task<Void, Never>
    }

    // One owner per sender session. The owner remains stable when rotation
    // replaces its virtual display, so an old asynchronous show can be
    // cancelled before macOS moves its orphaned window onto the main display.
    private static var windows: [UUID: NSWindow] = [:]
    private static var pendingShows: [UUID: PendingShow] = [:]
    // AppKit may still own a display-transform animation when a virtual
    // display disappears. Releasing the window in that transaction has
    // crashed inside _NSWindowTransformAnimation.dealloc on macOS 26.
    // Keep a bounded pool of hidden shell windows without their Metal views.
    private static var retiredWindows: [NSWindow] = []
    private static let maxRetiredWindows = 16

    static func show(ownerID: UUID, on displayID: CGDirectDisplayID) {
        hide(ownerID: ownerID)
        let generation = UUID()
        // The screen may register a beat after the virtual display appears.
        let task = Task { @MainActor in
            defer {
                if pendingShows[ownerID]?.generation == generation {
                    pendingShows.removeValue(forKey: ownerID)
                }
            }
            for _ in 0..<10 {
                guard !Task.isCancelled else { return }
                if let screen = NSScreen.screens.first(where: {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
                }) {
                    let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless],
                                     backing: .buffered, defer: false)
                    w.animationBehavior = .none
                    w.isReleasedWhenClosed = false
                    w.contentView = DisplayLinkPatternView(screen: screen)
                    w.setFrame(screen.frame, display: true, animate: false)
                    guard !Task.isCancelled else {
                        retire(w)
                        return
                    }
                    w.orderFrontRegardless()
                    windows[ownerID] = w
                    Log.info("test pattern window shown on display \(displayID)")
                    return
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
            if !Task.isCancelled {
                Log.info("test pattern: screen for display \(displayID) never appeared")
            }
        }
        pendingShows[ownerID] = PendingShow(generation: generation, task: task)
    }

    static func hide(ownerID: UUID) {
        pendingShows.removeValue(forKey: ownerID)?.task.cancel()
        if let window = windows.removeValue(forKey: ownerID) {
            retire(window)
        }
    }

    private static func retire(_ window: NSWindow) {
        (window.contentView as? DisplayLinkPatternView)?.stop()
        window.contentView = nil
        window.animationBehavior = .none
        window.orderOut(nil)
        if retiredWindows.count >= maxRetiredWindows {
            retiredWindows.removeFirst()
        }
        retiredWindows.append(window)
    }

    static func isTracking(ownerID: UUID) -> Bool {
        pendingShows[ownerID] != nil || windows[ownerID] != nil
    }
}

private final class DisplayLinkPatternView: MTKView, MTKViewDelegate {
    private lazy var commandQueue = device?.makeCommandQueue()
    private var renderDisplayLink: CADisplayLink?

    init(screen: NSScreen) {
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        delegate = self
        // A fixed 120fps MTKView can fall to a divisor (30fps) on a 90Hz
        // virtual display. Bind an NSScreen CADisplayLink to the virtual display.
        enableSetNeedsDisplay = true
        isPaused = true
        framebufferOnly = true
        colorPixelFormat = .bgra8Unorm
        let link = screen.displayLink(target: self, selector: #selector(stepDisplayLink))
        link.add(to: .main, forMode: .common)
        renderDisplayLink = link
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stop()
    }

    @objc private func stepDisplayLink() {
        autoreleasepool {
            draw()
        }
    }

    func stop() {
        renderDisplayLink?.invalidate()
        renderDisplayLink = nil
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let t = ProcessInfo.processInfo.systemUptime
        guard let commandQueue,
              let pass = currentRenderPassDescriptor,
              let drawable = currentDrawable else { return }
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: 0.45 + sin(t * 1.7) * 0.35,
            green: 0.45 + cos(t * 2.3) * 0.35,
            blue: 0.65,
            alpha: 1)
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
#else
import Foundation
import CoreGraphics

/// Release builds keep only the call-site contract. The animated Metal view,
/// display link, and window implementation are not compiled into artifacts.
@MainActor
enum TestPattern {
    static func show(ownerID: UUID, on displayID: CGDirectDisplayID) {}
    static func hide(ownerID: UUID) {}
    static func isTracking(ownerID: UUID) -> Bool { false }
}
#endif
