import Foundation

struct WifiTransportCandidate: Equatable, Sendable {
    let id: String
    let installID: String?
}

enum AndroidExistingTransport: Equatable, Sendable {
    case wifi(installID: String?)
    case usb
}

enum AndroidTransportHandoverDecision: Equatable, Sendable {
    case keepExisting
    case replaceWiFiWithUSB
}

enum AndroidTransportHandoverPolicy {
    static func decision(mode: StreamTransportMode,
                         existing: AndroidExistingTransport,
                         arrivingUSBInstallID: String?) -> AndroidTransportHandoverDecision {
        guard mode != .wifi,
              case .wifi(let wifiInstallID) = existing,
              let wifiInstallID,
              wifiInstallID == arrivingUSBInstallID else {
            return .keepExisting
        }
        return .replaceWiFiWithUSB
    }
}

enum TransportCandidate: Equatable, Sendable {
    case androidUSB(String)
    case wifi(String)
}

struct TransportSelectionPolicy: Sendable {
    static let recoveryDelays: [Double] = [0.5, 1, 2, 4, 8]

    /// A Thunderbolt/Ethernet Mac still uses LAN, never the USB transport.
    static func permits(mode: StreamTransportMode, isLAN: Bool) -> Bool {
        mode == .auto || (isLAN ? mode == .wifi : mode == .usb)
    }

    func preferred(mode: StreamTransportMode,
                   androidUSB: String?,
                   wifi: WifiTransportCandidate?) -> TransportCandidate? {
        switch mode {
        case .auto:
            if let androidUSB { return .androidUSB(androidUSB) }
            return wifi.map { .wifi($0.id) }
        case .usb:
            return androidUSB.map(TransportCandidate.androidUSB)
        case .wifi:
            return wifi.map { .wifi($0.id) }
        }
    }

    func fallbackWifi(usbInstallID: String?,
                      receivers: [WifiTransportCandidate]) -> WifiTransportCandidate? {
        guard let usbInstallID else { return nil }
        return receivers.first { $0.installID == usbInstallID }
    }
}

enum ReconnectHandshakeAction: Equatable, Sendable {
    case sendStreamConfig
    case forceKeyframe
}

enum ReconnectHandshakePolicy {
    static func actions(hasConfiguredStream: Bool) -> [ReconnectHandshakeAction] {
        hasConfiguredStream ? [.sendStreamConfig, .forceKeyframe] : [.forceKeyframe]
    }
}

enum ReconnectPeerReadinessEvent: Equatable, Sendable {
    case socketReady
    case peerMessage
}

enum ReconnectPeerReadinessPolicy {
    static func clearsDisconnectGrace(for event: ReconnectPeerReadinessEvent) -> Bool {
        event == .peerMessage
    }
}

enum DisconnectGracePolicy {
    static let initialConnectGraceSeconds: TimeInterval = 30

    static func graceSeconds(everConnected: Bool,
                             reconnectGraceSeconds: TimeInterval) -> TimeInterval {
        everConnected ? reconnectGraceSeconds : max(reconnectGraceSeconds, initialConnectGraceSeconds)
    }

    static func startedAt(existing: Date?, failureObservedAt: Date) -> Date {
        existing ?? failureObservedAt
    }

    static func hasExpired(startedAt: Date, now: Date,
                           graceSeconds: TimeInterval) -> Bool {
        now.timeIntervalSince(startedAt) >= graceSeconds
    }

    static func remainingSeconds(startedAt: Date, now: Date,
                                 graceSeconds: TimeInterval) -> Int {
        Int(ceil(max(0, graceSeconds - now.timeIntervalSince(startedAt))))
    }
}

enum ConnectionGenerationPolicy {
    static func accepts(callbackGeneration: UInt64,
                        currentGeneration: UInt64,
                        isCurrentObject: Bool,
                        stopped: Bool) -> Bool {
        !stopped && isCurrentObject && callbackGeneration == currentGeneration
    }

    static func acceptsReconnectTask(taskGeneration: UInt64,
                                     currentGeneration: UInt64,
                                     stopped: Bool) -> Bool {
        !stopped && taskGeneration == currentGeneration
    }
}

enum ConnectionClosureEvent: Equatable, Sendable {
    case cleanEnd
    case failure
}

enum ConnectionClosureAction: Equatable, Sendable {
    case endSession
    case retryWithinGrace
}

enum ReceiverPeerKind: Equatable, Sendable {
    case android
    case legacyApple
    case unknown
}

enum ConnectionClosurePolicy {
    static func action(for event: ConnectionClosureEvent,
                       peer: ReceiverPeerKind) -> ConnectionClosureAction {
        guard event == .cleanEnd, peer == .legacyApple else {
            return .retryWithinGrace
        }
        return .endSession
    }
}

enum ReceiverControlPolicy {
    static func closureAction(messageType: String,
                              peer: ReceiverPeerKind) -> ConnectionClosureAction? {
        if peer == .legacyApple, messageType == "closing" || messageType == "sleeping" { return .endSession }
        guard messageType == "goodbye" else { return nil }
        return peer == .legacyApple ? .endSession : .retryWithinGrace
    }
}

enum AndroidUsbRecoveryState: Equatable, Sendable {
    case connected
    case waiting(attempt: Int, delay: Double)
    case reconnecting(attempt: Int)
    case awaitingWifi
    case fallbackWifi(String)
    case failed
    case cancelled
}

enum AndroidUsbRecoveryEvent: Equatable, Sendable {
    case socketFailed
    case adbAvailable
    case adbUnavailable
    case reconnectSucceeded
    case retriesExhausted
    case wifiMatched(String)
    case cancelled
}

struct AndroidUsbRecoveryMachine: Sendable {
    let mode: StreamTransportMode

    func reduce(state: AndroidUsbRecoveryState,
                event: AndroidUsbRecoveryEvent) -> AndroidUsbRecoveryState {
        if event == .cancelled { return .cancelled }
        switch (state, event) {
        case (.connected, .socketFailed):
            return .waiting(attempt: 0, delay: TransportSelectionPolicy.recoveryDelays[0])
        case (.waiting(let attempt, _), .adbAvailable):
            return .reconnecting(attempt: attempt)
        case (.waiting(let attempt, _), .adbUnavailable),
             (.reconnecting(let attempt), .socketFailed):
            return nextAfterFailure(attempt: attempt)
        case (.reconnecting, .reconnectSucceeded):
            return .connected
        case (_, .retriesExhausted):
            return exhaustedState
        case (.awaitingWifi, .wifiMatched(let id)):
            return .fallbackWifi(id)
        default:
            return state
        }
    }

    private func nextAfterFailure(attempt: Int) -> AndroidUsbRecoveryState {
        let next = attempt + 1
        guard TransportSelectionPolicy.recoveryDelays.indices.contains(next) else {
            return exhaustedState
        }
        return .waiting(attempt: next,
                        delay: TransportSelectionPolicy.recoveryDelays[next])
    }

    private var exhaustedState: AndroidUsbRecoveryState {
        mode == .auto ? .awaitingWifi : .failed
    }
}

enum PersistedDeviceCollectionPolicy {
    static let defaultMaxEntries = 128
    static let maxIdentifierUTF8Bytes = 256

    static func isValidIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= maxIdentifierUTF8Bytes
    }

    static func boundedSet(
        _ values: Set<String>,
        previous: Set<String> = [],
        maxEntries: Int = defaultMaxEntries
    ) -> Set<String> {
        let valid = values.filter(isValidIdentifier)
        guard valid.count > maxEntries else { return valid }
        let added = valid.subtracting(previous).sorted().prefix(maxEntries)
        var result = Set(added)
        if result.count < maxEntries {
            for existing in valid.intersection(previous).sorted() {
                result.insert(existing)
                if result.count >= maxEntries { break }
            }
        }
        return result
    }

    static func boundedDictionary(
        _ values: [String: String],
        previous: [String: String] = [:],
        maxEntries: Int = defaultMaxEntries
    ) -> [String: String] {
        let valid = values.filter { isValidIdentifier($0.key) && isValidIdentifier($0.value) }
        guard valid.count > maxEntries else { return valid }
        let updatedKeys = valid.keys
            .filter { previous[$0] != valid[$0] }
            .sorted()
            .prefix(maxEntries)
        var result: [String: String] = [:]
        for key in updatedKeys {
            result[key] = valid[key]
        }
        if result.count < maxEntries {
            for key in valid.keys.sorted() where result[key] == nil {
                result[key] = valid[key]
                if result.count >= maxEntries { break }
            }
        }
        return result
    }
}

enum AndroidWiredAdbState: Equatable, Sendable {
    case device
    case unauthorized
    case offline
    case other(String)
}

struct AndroidWiredAdbCandidate: Equatable, Sendable {
    let serial: String
    let state: AndroidWiredAdbState
    let model: String?

    init(serial: String, state: AndroidWiredAdbState, model: String? = nil) {
        self.serial = serial
        self.state = state
        self.model = model
    }
}

struct AndroidWiredAccessoryCandidate: Equatable, Sendable {
    let serial: String
    let name: String?
    let busy: Bool

    init(serial: String, name: String? = nil, busy: Bool = false) {
        self.serial = serial
        self.name = name
        self.busy = busy
    }
}

enum AndroidWiredArbitrationDecision: Equatable, Sendable {
    /// `adb` reports this wired serial in `device` state: prefer `adb forward`
    /// and do not fight `adb` for exclusive IOKit USB access.
    case preferAdb(serial: String, model: String?)
    /// `adb` is not claiming this serial: dial directly via AOA (`aoa:<serial>`).
    case useAccessory(serial: String, name: String?)
    /// `adb` or another USB host holds exclusive access (`0xE00002C5` / unauthorized).
    case blockedByExclusiveOwner(serial: String, name: String?, adbState: AndroidWiredAdbState?)

    var serial: String {
        switch self {
        case .preferAdb(let serial, _),
             .useAccessory(let serial, _),
             .blockedByExclusiveOwner(let serial, _, _):
            return serial
        }
    }
}

enum AndroidWiredArbitrationPolicy {
    static func arbitrate(
        adbCandidates: [AndroidWiredAdbCandidate],
        accessoryCandidates: [AndroidWiredAccessoryCandidate]
    ) -> [AndroidWiredArbitrationDecision] {
        var orderedSerials: [String] = []
        var seen = Set<String>()
        var adbBySerial: [String: AndroidWiredAdbCandidate] = [:]
        var accessoryBySerial: [String: AndroidWiredAccessoryCandidate] = [:]

        for candidate in adbCandidates where !candidate.serial.isEmpty {
            if seen.insert(candidate.serial).inserted {
                orderedSerials.append(candidate.serial)
            }
            if let existing = adbBySerial[candidate.serial] {
                if existing.state != .device && candidate.state == .device {
                    adbBySerial[candidate.serial] = candidate
                }
            } else {
                adbBySerial[candidate.serial] = candidate
            }
        }

        for candidate in accessoryCandidates where !candidate.serial.isEmpty {
            if seen.insert(candidate.serial).inserted {
                orderedSerials.append(candidate.serial)
            }
            if let existing = accessoryBySerial[candidate.serial] {
                if existing.busy && !candidate.busy {
                    accessoryBySerial[candidate.serial] = candidate
                }
            } else {
                accessoryBySerial[candidate.serial] = candidate
            }
        }

        return orderedSerials.compactMap { serial in
            let adb = adbBySerial[serial]
            let accessory = accessoryBySerial[serial]
            if let adb, adb.state == .device {
                return .preferAdb(serial: serial, model: adb.model ?? accessory?.name)
            }
            if let accessory, !accessory.busy {
                return .useAccessory(serial: serial, name: accessory.name ?? adb?.model)
            }
            if adb != nil || accessory != nil {
                return .blockedByExclusiveOwner(
                    serial: serial,
                    name: adb?.model ?? accessory?.name,
                    adbState: adb?.state
                )
            }
            return nil
        }
    }

    static func shouldAutoConnectAccessory(
        mode: StreamTransportMode,
        sessionID: String,
        knownInstallID: String?,
        trustedPeerIDs: Set<String>,
        importedInvitationID: String?,
        allowLegacySender: Bool,
        disabledSessionIDs: Set<String>
    ) -> Bool {
        guard mode != .wifi, !disabledSessionIDs.contains(sessionID) else {
            return false
        }
        if let knownInstallID, trustedPeerIDs.contains(knownInstallID) {
            return true
        }
        return importedInvitationID != nil || allowLegacySender
    }

    static func recoveryMessage(
        serial: String,
        name: String?,
        adbState: AndroidWiredAdbState?
    ) -> String {
        let shortSerial = serial.count > 12 ? "…" + serial.suffix(8) : serial
        let label = name.map { "\($0)（\(shortSerial)）" } ?? shortSerial
        switch adbState {
        case .unauthorized:
            return "USB 设备 \(label) 尚未授权 USB 调试：请在手机弹窗中允许当前 Mac，或在终端运行 adb kill-server 后使用免调试即插即用"
        case .offline:
            return "ADB 设备离线（\(label)）：请重插数据线并解锁手机，或在终端运行 adb kill-server 后使用免调试即插即用"
        case .other(let raw):
            return "ADB 状态（\(raw) · \(label)）：请在手机确认连接，或在终端运行 adb kill-server 后使用免调试即插即用"
        case .device, nil:
            return "USB 设备 \(label) 正被 adb 或其他程序独占占用（0xE00002C5）：请在手机上允许 USB 调试以通过 ADB 连接，或在终端运行 adb kill-server 后使用免调试即插即用"
        }
    }
}
