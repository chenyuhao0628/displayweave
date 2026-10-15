import SwiftUI

/// A single settings host also works from the manually hosted control window.
/// This avoids relying on a SwiftUI scene environment in NSHostingView.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 610),
                                 styleMask: [.titled, .closable, .resizable],
                                 backing: .buffered, defer: false)
            panel.title = "DisplayWeave 设置"
            panel.contentView = NSHostingView(rootView: SenderSettingsView(controller: .shared))
            panel.contentMinSize = NSSize(width: 540, height: 520)
            panel.isReleasedWhenClosed = false
            panel.setFrameAutosaveName("DisplayWeaveSettings")
            panel.center()
            window = panel
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
