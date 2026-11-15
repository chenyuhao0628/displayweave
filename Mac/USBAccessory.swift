//
// Copyright (C) 2026 DisplayWeave contributors
// Adapted from OpenDisplay (https://github.com/OpenDisplay/OpenDisplay,
// commits e8a7f0f, bcf8e2b, 710c45c), Copyright (C) OpenDisplay contributors.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//

import Foundation
import IOKit
import IOUSBHost
import Network

/// Android Open Accessory (AOA 2.0) user-space USB transport for macOS.
///
/// When `adb` is not running or USB debugging is disabled on the phone, the Mac
/// switches a matched Android USB device into Google's standard accessory mode
/// (`0x18D1:0x2D00`/`0x2D01`) and bridges its bulk IN/OUT pipes to a local
/// loopback `NWConnection`. `MacSender` then layers `UsbmuxTLSRelay` + `AppleTLS`
/// + `AppleSecureAdmission` (`DWA1`/`DWR1`) over that stream by default, keeping
/// identical mutual TLS, pairing, and revocation guarantees as Wi-Fi and ADB.
enum AOA {
    /// Prefix used in `UsbmuxDevice.udid` to distinguish AOA devices from `usbmuxd`.
    static let prefix = "aoa:"

    static let googleVendorID: Int = 0x18D1
    static let appleVendorID: Int = 0x05AC
    static let accessoryProductIDs: Set<Int> = [0x2D00, 0x2D01, 0x2D04, 0x2D05]

    /// Matches `accessory_filter.xml` on Android Receiver for wire compatibility.
    static let manufacturer = "OpenDisplay"
    static let model = "OpenDisplay Receiver"
    static let releaseURI = "https://github.com/chenyuhao0628/displayweave/releases"

    /// Android's `f_accessory` gadget queues 16 KiB bulk requests.
    static let bulkReadBufferBytes = 16 * 1024
    static let maxConsecutiveEmptyReads = 64

    /// `IOReturn` codes surfaced as `NSError.code` by `IOUSBHostObject`.
    static let exclusiveAccessErrorCode: UInt32 = 0xE000_02C5 // kIOReturnExclusiveAccess
    static let pipeStalledErrorCode: UInt32 = 0xE000_5000     // kUSBHostReturnPipeStalled

    static let identity: [(UInt16, String)] = [
        (0, manufacturer),
        (1, model),
        (2, "Second display over USB"),
        (3, "1"),
        (4, releaseURI),
        (5, "0001"),
    ]

    private static let reqGetProtocol: UInt8 = 51
    private static let reqSendString: UInt8 = 52
    private static let reqStart: UInt8 = 53
    private static let reenumerateTimeoutSeconds: TimeInterval = 10.0
    fileprivate static let loopbackConnectTimeoutSeconds: TimeInterval = 5.0
    private static let dialLock = AOASerialLock()

    static func isUDID(_ udid: String?) -> Bool {
        udid?.hasPrefix(prefix) == true
    }

    static func serial(from udid: String?) -> String? {
        guard let udid, udid.hasPrefix(prefix) else { return nil }
        let serial = String(udid.dropFirst(prefix.count))
        return serial.isEmpty ? nil : serial
    }

    /// Returns `true` when a bulk OUT write ends on a USB packet boundary
    /// (`byteCount % maxPacketSize == 0`) without filling an exact multiple of
    /// Android's 16 KiB `f_accessory` URB (`byteCount % urbByteCount != 0`).
    /// Without a trailing ZLP, the USB controller holds the partial 16 KiB URB open.
    static func needsZeroLengthPacket(
        byteCount: Int,
        maxPacketSize: Int,
        urbByteCount: Int = bulkReadBufferBytes
    ) -> Bool {
        guard byteCount > 0, maxPacketSize > 0, urbByteCount > 0 else { return false }
        return byteCount % maxPacketSize == 0 && byteCount % urbByteCount != 0
    }

    enum Failure: LocalizedError, Equatable {
        case noDevice
        case notSupported
        case notAccessory
        case noApp
        case noInterface
        case busy

        var errorDescription: String? {
            switch self {
            case .noDevice:
                return "未发现 Android USB 设备，请使用支持数据传输的 USB 线连接手机或平板"
            case .notSupported:
                return "此 USB 设备不支持 Android 配件模式（AOA），请检查数据线或在手机切换 USB 用途"
            case .notAccessory:
                return "Android 未切换到 USB 配件模式，请重新插拔数据线并在手机提示中点“确定”"
            case .noApp:
                return "已进入 USB 配件模式，请在手机上解锁屏幕、允许配件访问并打开 DisplayWeave"
            case .noInterface:
                return "无法打开 Android USB 配件数据通道，请重新插拔数据线后重试"
            case .busy:
                return "USB 设备正被 adb 或其他程序独占占用（0xE00002C5）：请在手机上允许 USB 调试以通过 ADB 连接，或在终端运行 adb kill-server 后使用免调试即插即用"
            }
        }
    }

    /// Outcome of `askProtocol` (AOA request 51 `GET_PROTOCOL`).
    enum ProtocolAnswer: Equatable, Sendable {
        case supported(UInt16)
        case refused
        case busy
        case silent

        init(probeError: NSError) {
            switch UInt32(truncatingIfNeeded: probeError.code) {
            case AOA.exclusiveAccessErrorCode:
                self = .busy
            case AOA.pipeStalledErrorCode:
                self = .refused
            default:
                self = .silent
            }
        }
    }

    // MARK: - Dial

    /// Switches `serial` into AOA accessory mode if needed, opens bulk IN/OUT
    /// pipes, and returns a connected loopback `NWConnection` paired with the
    /// owning `AccessoryRelay`.
    static func dial(
        serial: String,
        queue: DispatchQueue
    ) async throws -> (connection: NWConnection, relay: AccessoryRelay) {
        await dialLock.acquire(serial)
        defer { Task { await dialLock.release(serial) } }
        try Task.checkCancellation()

        AccessoryRelay.close(serial: serial)
        let service = try await ensureAccessory(serial: serial)
        let opened: (IOUSBHostInterface, IOUSBHostPipe, IOUSBHostPipe)
        do {
            opened = try await openAccessoryInterface(service)
        } catch {
            reset(service)
            IOObjectRelease(service)
            throw error
        }
        let relay: AccessoryRelay
        do {
            relay = try AccessoryRelay(
                serial: serial,
                service: service,
                interface: opened.0,
                inPipe: opened.1,
                outPipe: opened.2
            )
        } catch {
            opened.0.destroy()
            reset(service)
            IOObjectRelease(service)
            throw error
        }
        do {
            let conn = try await relay.connectLoopback(on: queue)
            return (conn, relay)
        } catch {
            relay.close()
            throw error
        }
    }

    // MARK: - Handshake & Enumeration

    private static func ensureAccessory(serial: String) async throws -> io_service_t {
        guard let initial = await waitForDevice(serial: serial, accessory: nil, timeoutSeconds: 5.0) else {
            throw Failure.noDevice
        }
        if isAccessory(initial) {
            // Left over from an earlier session: reset back to normal USB mode so
            // Android's `f_accessory` clears stale state and triggers a fresh attach.
            reset(initial)
            IOObjectRelease(initial)
            guard let normal = await waitForDevice(
                serial: serial,
                accessory: false,
                timeoutSeconds: reenumerateTimeoutSeconds
            ) else {
                throw Failure.notAccessory
            }
            IOObjectRelease(normal)
        } else {
            IOObjectRelease(initial)
        }

        var lastBusy = false
        let deadline = ContinuousClock.now + .milliseconds(Int(reenumerateTimeoutSeconds * 1_000))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if let current = findDevice(serial: serial) {
                if isAccessory(current) {
                    return current
                }
                do {
                    try startAccessory(current)
                    lastBusy = false
                } catch {
                    lastBusy = (error as? Failure) == .busy
                }
                IOObjectRelease(current)
            }
            if let switched = await waitForDevice(serial: serial, accessory: true, timeoutSeconds: 2.0) {
                return switched
            }
        }
        throw lastBusy ? Failure.busy : Failure.notAccessory
    }

    private static func waitForDevice(
        serial: String,
        accessory: Bool?,
        timeoutSeconds: TimeInterval
    ) async -> io_service_t? {
        let deadline = ContinuousClock.now + .milliseconds(Int(timeoutSeconds * 1_000))
        while ContinuousClock.now < deadline {
            if Task.isCancelled { return nil }
            if let dev = findDevice(serial: serial) {
                if accessory == nil || isAccessory(dev) == accessory {
                    return dev
                }
                IOObjectRelease(dev)
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    static func askProtocol(_ service: io_service_t) -> ProtocolAnswer {
        let host: IOUSBHostDevice
        do {
            host = try IOUSBHostDevice(__ioService: service, options: [], queue: nil, interestHandler: nil)
        } catch let error as NSError {
            return ProtocolAnswer(probeError: error) == .busy ? .busy : .silent
        }
        defer { host.destroy() }

        guard let buf = NSMutableData(length: 2) else { return .silent }
        let req = IOUSBDeviceRequest(
            bmRequestType: 0xC0,
            bRequest: reqGetProtocol,
            wValue: 0,
            wIndex: 0,
            wLength: 2
        )
        var transferred = 0
        do {
            try host.__send(req, data: buf, bytesTransferred: &transferred, completionTimeout: 1.0)
        } catch let error as NSError {
            return ProtocolAnswer(probeError: error)
        }
        guard transferred == 2 else { return .refused }
        var version: UInt16 = 0
        buf.getBytes(&version, length: 2)
        let v = UInt16(littleEndian: version)
        return v >= 1 ? .supported(v) : .refused
    }

    private static func startAccessory(_ service: io_service_t) throws {
        switch askProtocol(service) {
        case .supported(let version):
            Log.info("AOA protocol v\(version) supported")
        case .busy:
            throw Failure.busy
        case .refused, .silent:
            throw Failure.notSupported
        }

        let host: IOUSBHostDevice
        do {
            host = try IOUSBHostDevice(__ioService: service, options: [], queue: nil, interestHandler: nil)
        } catch let error as NSError {
            if UInt32(truncatingIfNeeded: error.code) == exclusiveAccessErrorCode {
                throw Failure.busy
            }
            throw Failure.notSupported
        }
        defer { host.destroy() }

        var transferred = 0
        for (index, value) in identity {
            let bytes = NSMutableData(data: Data(value.utf8) + [0])
            let req = IOUSBDeviceRequest(
                bmRequestType: 0x40,
                bRequest: reqSendString,
                wValue: 0,
                wIndex: index,
                wLength: UInt16(bytes.length)
            )
            try host.__send(req, data: bytes, bytesTransferred: &transferred, completionTimeout: 1.0)
        }

        let start = IOUSBDeviceRequest(
            bmRequestType: 0x40,
            bRequest: reqStart,
            wValue: 0,
            wIndex: 0,
            wLength: 0
        )
        // The device drops off the bus on START, sometimes before the status stage completes.
        try? host.__send(
            start,
            data: nil as NSMutableData?,
            bytesTransferred: nil as UnsafeMutablePointer<Int>?,
            completionTimeout: 1.0
        )
    }

    private static func openAccessoryInterface(
        _ device: io_service_t
    ) async throws -> (IOUSBHostInterface, IOUSBHostPipe, IOUSBHostPipe) {
        for _ in 0..<20 {
            try Task.checkCancellation()
            if let claimed = try claimAccessoryInterfaceOnce(device) {
                return claimed
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw Failure.noInterface
    }

    private static func claimAccessoryInterfaceOnce(
        _ device: io_service_t
    ) throws -> (IOUSBHostInterface, IOUSBHostPipe, IOUSBHostPipe)? {
        var iter: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(
            device,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iter
        ) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iter) }

        while case let child = IOIteratorNext(iter), child != IO_OBJECT_NULL {
            defer { IOObjectRelease(child) }
            // Accessory interface is vendor class 0xFF/0xFF; with USB debugging on,
            // adb's 0xFF/0x42 sits alongside it on interface 1.
            guard IOObjectConformsTo(child, "IOUSBHostInterface") != 0,
                  intProp(child, "bInterfaceClass") == 0xFF,
                  intProp(child, "bInterfaceSubClass") == 0xFF else { continue }
            let iface: IOUSBHostInterface
            do {
                iface = try IOUSBHostInterface(
                    __ioService: child,
                    options: [],
                    queue: nil,
                    interestHandler: nil
                )
            } catch let error as NSError {
                if UInt32(truncatingIfNeeded: error.code) == exclusiveAccessErrorCode {
                    throw Failure.busy
                }
                throw Failure.noInterface
            }
            var inPipe: IOUSBHostPipe?
            var outPipe: IOUSBHostPipe?
            for address in 1...15 {
                if inPipe == nil {
                    inPipe = try? iface.copyPipe(withAddress: 0x80 | address)
                }
                if outPipe == nil {
                    outPipe = try? iface.copyPipe(withAddress: address)
                }
            }
            guard let inPipe, let outPipe else {
                iface.destroy()
                throw Failure.noInterface
            }
            return (iface, inPipe, outPipe)
        }
        return nil
    }

    // MARK: - IORegistry Helpers

    static func isAccessory(_ service: io_service_t) -> Bool {
        guard let vid = intProp(service, "idVendor"),
              let pid = intProp(service, "idProduct") else { return false }
        return vid == googleVendorID && accessoryProductIDs.contains(pid)
    }

    static func serialNumber(of service: io_service_t) -> String? {
        stringProp(service, "USB Serial Number")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
    }

    static func productName(of service: io_service_t) -> String? {
        stringProp(service, "USB Product Name")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
    }

    private static func findDevice(serial: String) -> io_service_t? {
        guard let matching = IOServiceMatching("IOUSBHostDevice") else { return nil }
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iter) }

        while case let svc = IOIteratorNext(iter), svc != IO_OBJECT_NULL {
            if serialNumber(of: svc) == serial {
                return svc
            }
            IOObjectRelease(svc)
        }
        return nil
    }

    static func intProp(_ entry: io_registry_entry_t, _ key: String) -> Int? {
        (IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber)?.intValue
    }

    static func stringProp(_ entry: io_registry_entry_t, _ key: String) -> String? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    /// Resets the USB device after aborting bulk pipes so Android's `f_accessory`
    /// clears its latched `disconnected` flag before the next session opens it.
    fileprivate static func reset(_ service: io_service_t) {
        guard service != IO_OBJECT_NULL,
              let host = try? IOUSBHostDevice(
                __ioService: service,
                options: [],
                queue: nil,
                interestHandler: nil
              ) else { return }
        try? host.reset()
        host.destroy()
    }
}

/// Async mutual exclusion per serial so overlapping dials never reset a newer session.
private actor AOASerialLock {
    private var held: Set<String> = []
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func acquire(_ key: String) async {
        guard held.contains(key) else {
            held.insert(key)
            return
        }
        await withCheckedContinuation { waiters[key, default: []].append($0) }
    }

    func release(_ key: String) {
        if var queue = waiters[key], !queue.isEmpty {
            let next = queue.removeFirst()
            waiters[key] = queue.isEmpty ? nil : queue
            next.resume()
        } else {
            held.remove(key)
        }
    }
}

// MARK: - Loopback Bulk Pipe Relay

/// Bridges `IOUSBHostPipe` bulk IN/OUT endpoints to a single local loopback
/// `NWConnection` so `UsbmuxTLSRelay` + `AppleTLS` (or explicit legacy framing)
/// operates over USB accessory mode identically to `usbmuxd`.
final class AccessoryRelay: @unchecked Sendable {
    private static let registryLock = NSLock()
    private static var active: [String: AccessoryRelay] = [:]

    static func close(serial: String) {
        registryLock.lock()
        let existing = active.removeValue(forKey: serial)
        registryLock.unlock()
        existing?.close()
    }

    private let serial: String
    private let service: io_service_t
    private let interface: IOUSBHostInterface
    private let inPipe: IOUSBHostPipe
    private let outPipe: IOUSBHostPipe
    private let maxPacket: Int
    private let listener: NWListener
    private let queue = DispatchQueue(label: "displayweave.usb.aoa-relay.net", qos: .userInteractive)
    private let writeQueue = DispatchQueue(label: "displayweave.usb.aoa-relay.write", qos: .userInteractive)
    private let lock = NSLock()
    private var accepted: NWConnection?
    private var closed = false
    private var receivedBytesFromAccessory = false
    private var listenerReadyPort: UInt16?
    private var readyCallbacks: [(Result<UInt16, Error>) -> Void] = []

    var hasReceivedData: Bool {
        lock.lock()
        defer { lock.unlock() }
        return receivedBytesFromAccessory
    }

    init(
        serial: String,
        service: io_service_t,
        interface: IOUSBHostInterface,
        inPipe: IOUSBHostPipe,
        outPipe: IOUSBHostPipe
    ) throws {
        self.serial = serial
        self.service = service
        self.interface = interface
        self.inPipe = inPipe
        self.outPipe = outPipe
        self.maxPacket = max(1, Int(outPipe.descriptors.pointee.descriptor.wMaxPacketSize & 0x07FF))

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        self.listener = try NWListener(using: params)

        Self.registryLock.lock()
        let previous = Self.active.updateValue(self, forKey: serial)
        Self.registryLock.unlock()
        previous?.close()

        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener.stateUpdateHandler = { [weak self] state in
            self?.handleListenerState(state)
        }
        listener.start(queue: queue)
    }

    deinit {
        close()
    }

    fileprivate func connectLoopback(on callerQueue: DispatchQueue) async throws -> NWConnection {
        let port = try await waitForListenerPort()
        try Task.checkCancellation()

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)
        params.preferNoProxies = true
        let conn = NWConnection(
            to: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!),
            using: params
        )
        try await withTaskCancellationHandler {
            try await waitUntilReady(conn, queue: callerQueue)
        } onCancel: {
            conn.cancel()
        }
        return conn
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener.port?.rawValue else {
                failListenerReady(AOA.Failure.noInterface)
                return
            }
            lock.lock()
            listenerReadyPort = port
            let callbacks = readyCallbacks
            readyCallbacks.removeAll()
            lock.unlock()
            callbacks.forEach { $0(.success(port)) }
        case .failed(let error):
            failListenerReady(error)
            close()
        case .cancelled:
            failListenerReady(CancellationError())
        default:
            break
        }
    }

    private func failListenerReady(_ error: Error) {
        lock.lock()
        let callbacks = readyCallbacks
        readyCallbacks.removeAll()
        lock.unlock()
        callbacks.forEach { $0(.failure(error)) }
    }

    private func waitForListenerPort() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            lock.lock()
            if closed {
                lock.unlock()
                cont.resume(throwing: CancellationError())
                return
            }
            if let port = listenerReadyPort {
                lock.unlock()
                cont.resume(returning: port)
                return
            }
            readyCallbacks.append { result in
                cont.resume(with: result)
            }
            lock.unlock()
        }
    }

    private func waitUntilReady(_ conn: NWConnection, queue: DispatchQueue) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let resumeLock = NSLock()
            var finished = false
            let timer = DispatchSource.makeTimerSource(queue: queue)
            let finish: (Result<Void, Error>) -> Void = { result in
                resumeLock.lock()
                guard !finished else {
                    resumeLock.unlock()
                    return
                }
                finished = true
                resumeLock.unlock()
                timer.cancel()
                conn.stateUpdateHandler = nil
                if case .failure = result { conn.cancel() }
                cont.resume(with: result)
            }
            timer.schedule(deadline: .now() + AOA.loopbackConnectTimeoutSeconds)
            timer.setEventHandler {
                finish(.failure(AOA.Failure.noInterface))
            }
            timer.resume()
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(.success(()))
                case .failed(let error):
                    finish(.failure(error))
                case .cancelled:
                    finish(.failure(CancellationError()))
                default:
                    break
                }
            }
            conn.start(queue: queue)
        }
    }

    private func accept(_ conn: NWConnection) {
        lock.lock()
        guard !closed, accepted == nil else {
            lock.unlock()
            conn.cancel()
            return
        }
        accepted = conn
        lock.unlock()

        listener.cancel()
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.close()
            default:
                break
            }
        }
        conn.start(queue: queue)
        pumpReads()
        pumpWrites()
    }

    private func isClosed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    private func pumpReads() {
        Thread.detachNewThread { [self] in
            // Android's `f_accessory` queues 16 KiB USB requests; reading less
            // can truncate or drop the remainder of a transfer.
            guard let buf = NSMutableData(length: AOA.bulkReadBufferBytes) else {
                close()
                return
            }
            var consecutiveEmptyReads = 0
            while !isClosed() {
                var transferred = 0
                do {
                    try inPipe.__sendIORequest(
                        with: buf,
                        bytesTransferred: &transferred,
                        completionTimeout: 0
                    )
                } catch {
                    if !isClosed() { Log.info("AOA bulk IN closed: \(error)") }
                    close()
                    return
                }
                if transferred == 0 {
                    consecutiveEmptyReads += 1
                    if consecutiveEmptyReads >= AOA.maxConsecutiveEmptyReads {
                        Log.info("AOA bulk IN exceeded \(AOA.maxConsecutiveEmptyReads) consecutive empty reads — closing")
                        close()
                        return
                    }
                    continue
                }
                consecutiveEmptyReads = 0
                lock.lock()
                receivedBytesFromAccessory = true
                let conn = accepted
                lock.unlock()
                let chunk = Data(bytes: buf.bytes, count: transferred)
                let sem = DispatchSemaphore(value: 0)
                var sendFailed = false
                conn?.send(content: chunk, completion: .contentProcessed { err in
                    if err != nil { sendFailed = true }
                    sem.signal()
                })
                sem.wait()
                if sendFailed {
                    close()
                    return
                }
            }
        }
    }

    private func pumpWrites() {
        lock.lock()
        let conn = accepted
        lock.unlock()
        conn?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, ended, err in
            guard let self else { return }
            guard let data, !data.isEmpty else {
                if ended || err != nil {
                    self.close()
                } else {
                    self.pumpWrites()
                }
                return
            }
            self.writeQueue.async { [weak self] in
                guard let self, !self.isClosed() else { return }
                let buf = NSMutableData(data: data)
                var transferred = 0
                // Before the Android app opens `/dev/usb_accessory` (e.g. while
                // the user taps OK on the system USB accessory dialog), bulk OUT
                // waits up to 30s; once active, wedge detection fails in 5s.
                let timeout: TimeInterval = self.hasReceivedData ? 5.0 : 30.0
                do {
                    try self.outPipe.__sendIORequest(
                        with: buf,
                        bytesTransferred: &transferred,
                        completionTimeout: timeout
                    )
                    if AOA.needsZeroLengthPacket(byteCount: data.count, maxPacketSize: self.maxPacket) {
                        var zlpTransferred = 0
                        try self.outPipe.__sendIORequest(
                            with: NSMutableData(),
                            bytesTransferred: &zlpTransferred,
                            completionTimeout: 1.0
                        )
                    }
                } catch {
                    if !self.isClosed() { Log.info("AOA bulk OUT closed: \(error)") }
                    self.close()
                    return
                }
                if ended || err != nil {
                    self.close()
                    return
                }
                self.pumpWrites()
            }
        }
    }

    func close() {
        lock.lock()
        if closed {
            lock.unlock()
            return
        }
        closed = true
        let conn = accepted
        accepted = nil
        let callbacks = readyCallbacks
        readyCallbacks.removeAll()
        lock.unlock()

        Self.registryLock.lock()
        if Self.active[serial] === self {
            Self.active.removeValue(forKey: serial)
        }
        Self.registryLock.unlock()

        callbacks.forEach { $0(.failure(CancellationError())) }
        listener.cancel()
        queue.async { conn?.cancel() }
        try? inPipe.__abort(with: .synchronous)
        try? outPipe.__abort(with: .synchronous)
        interface.destroy()
        AOA.reset(service)
        IOObjectRelease(service)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
