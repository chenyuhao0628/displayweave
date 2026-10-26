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
    var lifetime: SessionLifetime!
    @Published var failed = false
    var androidForwardManager: AndroidAdbForwardManager?
    // Route selected when this pipeline was created; discovery may change later.
    var macLANRoute: MacLANRoute?

    @Published var status = "正在启动…"
    @Published var framesSent = 0
    @Published var mbps = 0.0
    @Published var targetMbps = 0.0
    @Published var streamDescription = ""
    @Published var streamLimitDescription: String?
    @Published var benchmarkStatus = "Idle"
    // Receiver's per-install identity (from hello) — the key for recognizing
    // the same physical device across USB and WiFi.
    @Published var deviceID: String?
    @Published var receiverInfo: PhoneInfo?

    var nativeDesktop: DesktopGeometry? {
        guard let info = receiverInfo else { return nil }
        return desktopGeometry(.native, info: info)
    }

    func desktopGeometry(_ selection: DesktopResolution) -> DesktopGeometry? {
        receiverInfo.map { desktopGeometry(selection, info: $0) }
    }

    private func desktopGeometry(_ selection: DesktopResolution, info: PhoneInfo) -> DesktopGeometry {
        let scale = info.isMacReceiver && (info.panel?.scale ?? info.scale) < 1.5 ? 1 : 2
        return DesktopResolutionPolicy.geometry(selection,
            nativeWidth: info.panel?.pixelsWide ?? info.pixelsWide,
            nativeHeight: info.panel?.pixelsHigh ?? info.pixelsHigh,
            nativePointsWide: info.panel?.pointsWide, nativePointsHigh: info.panel?.pointsHigh,
            backingScale: scale)
    }
    // "iPhone" / "iPad" from hello — naming fallback while (or in case)
    // lockdown hasn't resolved the device's real name.
    var deviceKind: String?

    var transportLabel: String {
        switch target {
        case .usb, .androidAdb, .androidAdbDevice: return "USB"
        case .wifi:
            if let route = macLANRoute, !route.interfaceName.isEmpty {
                return "\(route.direct ? "有线" : "局域网") · \(route.interfaceName)"
            }
            return sender.directLinkInterfaceName.map { "有线 · \($0)" } ?? "局域网"
        }
    }

    init(id: String, target: ConnectionTarget, name: String, sender: MacSender) {
        self.id = id
        self.target = target
        self.name = name
        self.sender = sender
    }
}
