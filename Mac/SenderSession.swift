import SwiftUI
import Network
import Combine
import Sparkle

enum ConnectionTarget: Hashable {
    case usb(udid: String?)           // wired via built-in usbmuxd; nil = first device
    case androidAdbDevice(serial: String)
    case androidAdb(AndroidAdbForward)
    case wifi(NWBrowser.Result)       // discovered via Bonjour

    /// Stable identity for sessions and persistence — survives Bonjour
    /// re-discovery (fresh NWBrowser.Result) and USB replugs (new DeviceID).
    var sessionID: String {
        switch self {
        case .usb(let udid): return "usb:\(udid ?? "first")"
        case .androidAdbDevice(let serial): return "android-adb:\(serial)"
        case .androidAdb(let mapping): return "android-adb:\(mapping.serial)"
        case .wifi(let result):
            if case .service(let name, _, _, _) = result.endpoint { return "wifi:\(name)" }
            return "wifi:unknown"
        }
    }
}

/// One connected (or connecting) device: its target, its sender pipeline,
/// and the per-device status the UI shows. Each session owns a full pipeline
/// — virtual display, capture, encoder, socket — so devices are independent:
/// one disconnecting never stalls the others.
@MainActor
final class DeviceSession: ObservableObject, Identifiable {
    nonisolated let id: String
    let target: ConnectionTarget
    let name: String
    let sender: MacSender
    var startupTask: Task<Void, Never>?
    var androidForwardManager: AndroidAdbForwardManager?

    @Published var status = "正在启动…"
    @Published var framesSent = 0
    @Published var mbps = 0.0
    @Published var targetMbps = 0.0
    @Published var benchmarkStatus = "Idle"
    // Receiver's per-install identity (from hello) — the key for recognizing
    // the same physical device across USB and WiFi.
    var deviceID: String?
    // "iPhone" / "iPad" from hello — naming fallback while (or in case)
    // lockdown hasn't resolved the device's real name.
    var deviceKind: String?

    var transportLabel: String {
        switch target {
        case .usb, .androidAdb, .androidAdbDevice: return "USB"
        case .wifi: return "局域网"
        }
    }

    init(id: String, target: ConnectionTarget, name: String, sender: MacSender) {
        self.id = id
        self.target = target
        self.name = name
        self.sender = sender
    }
}
