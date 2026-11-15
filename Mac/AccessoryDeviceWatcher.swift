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

/// Watches IOKit for Android USB devices capable of AOA 2.0 without disturbing
/// non-Android USB peripherals or fighting a running `adb` server.
///
/// Safety invariants:
/// - Never sends AOA `0xC0 GET_PROTOCOL` on raw `IOUSBHostDevice` attach (which
///   breaks USB-C dock Ethernet chips such as ASIX AX88179A).
/// - Only probes `IOUSBHostInterface` entries classified by `AndroidUSBFunction`
///   (`.adb` or `.mtp`), and probes at most once per attachment (`asked`), except
///   when retrying `0xE00002C5` (`busy`) after `adb` releases the device.
/// - Defers USB probing while `AndroidAdb` already reports the same `serial`
///   online in `.device` state.
final class AccessoryDeviceWatcher: @unchecked Sendable {
    static let detachGrace: Duration = .seconds(10)
    private static let busyRetryInterval: Duration = .seconds(2)
    private static let maxTrackedEntries = PersistedDeviceCollectionPolicy.defaultMaxEntries

    private let queue = DispatchQueue(label: "displayweave.usb.aoa-watcher")
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var stopped = false

    private var serialByEntry: [UInt64: String] = [:]
    private var nameBySerial: [String: String?] = [:]
    private var busyDevices: [String: String?] = [:]
    private var pendingDetach: [String: Task<Void, Never>] = [:]
    private var probes: [UInt64: Task<Void, Never>] = [:]
    private var deferredByAdb: [UInt64: (serial: String, name: String?)] = [:]
    private var adbClaimedSerials: Set<String> = []
    private var capable: Set<String> = []
    private var asked: Set<UInt64> = []

    private let onChange: @MainActor ([UsbmuxDevice]) -> Void
    private let onBusyChange: @MainActor ([UsbmuxDevice]) -> Void

    init(
        onChange: @escaping @MainActor ([UsbmuxDevice]) -> Void,
        onBusyChange: @escaping @MainActor ([UsbmuxDevice]) -> Void = { _ in }
    ) {
        self.onChange = onChange
        self.onBusyChange = onBusyChange
        queue.async { [weak self] in self?.startOnQueue() }
    }

    deinit {
        stop()
    }

    func stop() {
        queue.sync {
            guard !stopped else { return }
            stopped = true
            pendingDetach.values.forEach { $0.cancel() }
            pendingDetach.removeAll()
            probes.values.forEach { $0.cancel() }
            probes.removeAll()
            deferredByAdb.removeAll()
            serialByEntry.removeAll()
            nameBySerial.removeAll()
            busyDevices.removeAll()
            for iter in iterators where iter != IO_OBJECT_NULL {
                IOObjectRelease(iter)
            }
            iterators.removeAll()
            if let port {
                IONotificationPortDestroy(port)
                self.port = nil
            }
        }
    }

    /// Updates the set of wired serials currently online in `AndroidAdb` (`.device`).
    /// When `adb` claims a serial, we stop fighting it for exclusive USB access;
    /// when `adb` exits (`adb kill-server`), deferred interfaces are probed cleanly.
    func updateAdbOnlineSerials(_ serials: Set<String>) {
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            let previous = self.adbClaimedSerials
            guard previous != serials else { return }
            self.adbClaimedSerials = serials

            var busyChanged = false
            for serial in serials {
                if self.busyDevices.removeValue(forKey: serial) != nil {
                    busyChanged = true
                }
            }
            if busyChanged {
                self.publishBusy()
            }

            // Serials released by adb (e.g. after `adb kill-server`) can now be probed.
            let released = previous.subtracting(serials)
            guard !released.isEmpty else { return }
            let toResume = self.deferredByAdb.filter { released.contains($0.value.serial) }
            for (entryID, info) in toResume {
                self.deferredByAdb.removeValue(forKey: entryID)
                self.asked.remove(entryID)
                self.startProbe(entryID: entryID, serial: info.serial, name: info.name)
            }
        }
    }

    private func startOnQueue() {
        guard !stopped, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, queue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        for fn in AndroidUSBFunction.candidates {
            guard let match = IOServiceMatching("IOUSBHostInterface") as? NSMutableDictionary else { continue }
            match[kIOPropertyMatchKey] = [
                "bInterfaceClass": Int(fn.class),
                "bInterfaceSubClass": Int(fn.subclass),
                "bInterfaceProtocol": Int(fn.protocol),
            ]
            var addIter: io_iterator_t = 0
            let kr = IOServiceAddMatchingNotification(
                port,
                kIOFirstMatchNotification,
                match,
                { ctx, it in
                    guard let ctx else { return }
                    Unmanaged<AccessoryDeviceWatcher>.fromOpaque(ctx).takeUnretainedValue()
                        .interfacesMatched(it)
                },
                refcon,
                &addIter
            )
            if kr == KERN_SUCCESS {
                iterators.append(addIter)
                interfacesMatched(addIter)
            }
        }

        var addDevIter: io_iterator_t = 0
        if IOServiceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            IOServiceMatching("IOUSBHostDevice"),
            { ctx, it in
                guard let ctx else { return }
                Unmanaged<AccessoryDeviceWatcher>.fromOpaque(ctx).takeUnretainedValue()
                    .devicesAttached(it)
            },
            refcon,
            &addDevIter
        ) == KERN_SUCCESS {
            iterators.append(addDevIter)
            devicesAttached(addDevIter)
        }

        var remDevIter: io_iterator_t = 0
        if IOServiceAddMatchingNotification(
            port,
            kIOTerminatedNotification,
            IOServiceMatching("IOUSBHostDevice"),
            { ctx, it in
                guard let ctx else { return }
                Unmanaged<AccessoryDeviceWatcher>.fromOpaque(ctx).takeUnretainedValue()
                    .devicesDetached(it)
            },
            refcon,
            &remDevIter
        ) == KERN_SUCCESS {
            iterators.append(remDevIter)
            devicesDetached(remDevIter)
        }
    }

    // MARK: - Interface-Gated AOA Probe

    private func interfacesMatched(_ iter: io_iterator_t) {
        while case let iface = IOIteratorNext(iter), iface != IO_OBJECT_NULL {
            defer { IOObjectRelease(iface) }
            guard !stopped else { continue }
            guard let cls = AOA.intProp(iface, "bInterfaceClass").flatMap(UInt8.init(exactly:)),
                  let sub = AOA.intProp(iface, "bInterfaceSubClass").flatMap(UInt8.init(exactly:)),
                  let prt = AOA.intProp(iface, "bInterfaceProtocol").flatMap(UInt8.init(exactly:)),
                  AndroidUSBFunction(
                    interfaceClass: cls,
                    subclass: sub,
                    protocol: prt,
                    name: AOA.stringProp(iface, "kUSBString")
                  ) != nil else { continue }

            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(iface, kIOServicePlane, &parent) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(parent) }
            guard IOObjectConformsTo(parent, "IOUSBHostDevice") != 0,
                  AOA.intProp(parent, "idVendor") != AOA.appleVendorID,
                  !AOA.isAccessory(parent),
                  let serial = AOA.serialNumber(of: parent) else { continue }

            var devID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(parent, &devID) == KERN_SUCCESS else { continue }

            let name = AOA.productName(of: parent)
            if capable.contains(serial) {
                attach(entryID: devID, serial: serial, name: name)
                continue
            }

            // Probe at most once per attachment unless deferred by ADB or busy.
            guard asked.insert(devID).inserted else { continue }
            if asked.count > Self.maxTrackedEntries * 2 {
                asked.removeAll(keepingCapacity: true)
                asked.insert(devID)
            }

            if adbClaimedSerials.contains(serial) {
                deferredByAdb[devID] = (serial: serial, name: name)
                continue
            }

            startProbe(entryID: devID, serial: serial, name: name)
        }
    }

    private func startProbe(entryID: UInt64, serial: String, name: String?) {
        guard probes[entryID] == nil, !stopped else { return }
        probes[entryID] = Task { [weak self] in
            await self?.probeLoop(entryID: entryID, serial: serial, name: name)
        }
    }

    private func probeLoop(entryID: UInt64, serial: String, name: String?) async {
        defer {
            queue.async { [weak self] in
                self?.probes.removeValue(forKey: entryID)
            }
        }
        while !Task.isCancelled {
            let claimedByAdb = queue.sync { stopped || adbClaimedSerials.contains(serial) }
            if claimedByAdb {
                queue.async { [weak self] in
                    guard let self, !self.stopped else { return }
                    self.deferredByAdb[entryID] = (serial: serial, name: name)
                    if self.busyDevices.removeValue(forKey: serial) != nil {
                        self.publishBusy()
                    }
                }
                return
            }

            guard let match = IORegistryEntryIDMatching(entryID) else { return }
            let dev = IOServiceGetMatchingService(kIOMainPortDefault, match)
            guard dev != IO_OBJECT_NULL else {
                queue.async { [weak self] in
                    guard let self else { return }
                    if self.busyDevices.removeValue(forKey: serial) != nil {
                        self.publishBusy()
                    }
                }
                return
            }
            let answer = AOA.askProtocol(dev)
            IOObjectRelease(dev)

            switch answer {
            case .supported(let version):
                Log.info("AOA probe supported v\(version): \(name ?? serial)")
                queue.async { [weak self] in
                    guard let self, !self.stopped else { return }
                    self.rememberCapable(serial)
                    if self.busyDevices.removeValue(forKey: serial) != nil {
                        self.publishBusy()
                    }
                    self.attach(entryID: entryID, serial: serial, name: name)
                }
                return
            case .busy:
                queue.async { [weak self] in
                    guard let self, !self.stopped, !self.adbClaimedSerials.contains(serial) else { return }
                    let prior = self.busyDevices.updateValue(name, forKey: serial)
                    if prior == nil {
                        Log.info("AOA probe hit 0xE00002C5 (busy) for \(name ?? serial) — waiting for exclusive owner")
                        self.publishBusy()
                    }
                }
                try? await Task.sleep(for: Self.busyRetryInterval)
            case .refused, .silent:
                return
            }
        }
    }

    private func rememberCapable(_ serial: String) {
        capable.insert(serial)
        if capable.count > Self.maxTrackedEntries {
            capable = PersistedDeviceCollectionPolicy.boundedSet(
                capable,
                maxEntries: Self.maxTrackedEntries
            )
        }
    }

    // MARK: - Device Attach / Detach (No Raw USB Control Requests!)

    private func devicesAttached(_ iter: io_iterator_t) {
        while case let svc = IOIteratorNext(iter), svc != IO_OBJECT_NULL {
            defer { IOObjectRelease(svc) }
            guard !stopped, let serial = AOA.serialNumber(of: svc) else { continue }
            var devID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(svc, &devID) == KERN_SUCCESS else { continue }
            // Never send GET_PROTOCOL here. Attach immediately only when the
            // device is already enumerated as an AOA accessory or was proven
            // capable earlier in this session.
            guard AOA.isAccessory(svc) || capable.contains(serial) else { continue }
            if busyDevices.removeValue(forKey: serial) != nil {
                publishBusy()
            }
            attach(entryID: devID, serial: serial, name: AOA.productName(of: svc))
        }
    }

    private func devicesDetached(_ iter: io_iterator_t) {
        var sawDetach = false
        while case let svc = IOIteratorNext(iter), svc != IO_OBJECT_NULL {
            defer { IOObjectRelease(svc) }
            sawDetach = true
            var devID: UInt64 = 0
            var detachedSerial: String?
            if IORegistryEntryGetRegistryEntryID(svc, &devID) == KERN_SUCCESS {
                probes.removeValue(forKey: devID)?.cancel()
                deferredByAdb.removeValue(forKey: devID)
                asked.remove(devID)
                detachedSerial = serialByEntry.removeValue(forKey: devID)
            }
            guard !stopped else { continue }
            let serial = detachedSerial ?? AOA.serialNumber(of: svc)
            if let serial, busyDevices.removeValue(forKey: serial) != nil {
                publishBusy()
            }
            guard let serial = detachedSerial,
                  !serialByEntry.values.contains(serial) else { continue }
            // Switching composite -> accessory detaches and re-enumerates on the
            // bus; hold disappearance briefly so the UI row does not flicker.
            let name = nameBySerial[serial] ?? nil
            pendingDetach.removeValue(forKey: serial)?.cancel()
            pendingDetach[serial] = Task { [weak self] in
                try? await Task.sleep(for: Self.detachGrace)
                guard !Task.isCancelled else { return }
                self?.finishDetach(serial: serial, fallbackName: name)
            }
        }
        if sawDetach, serialByEntry.isEmpty, pendingDetach.isEmpty {
            publish()
        }
    }

    private func attach(entryID: UInt64, serial: String, name: String?) {
        let priorDetach = pendingDetach.removeValue(forKey: serial)
        priorDetach?.cancel()
        let reenumerating = priorDetach != nil
        let wasPresent = serialByEntry.values.contains(serial)
        serialByEntry[entryID] = serial

        let priorName = nameBySerial[serial] ?? nil
        let keepPriorName = AOA.isAccessoryName(name)
        let resolvedName = (keepPriorName ? priorName : nil) ?? name ?? priorName
        nameBySerial[serial] = resolvedName
        if nameBySerial.count > Self.maxTrackedEntries {
            let compacted = PersistedDeviceCollectionPolicy.boundedDictionary(
                nameBySerial.compactMapValues { $0 },
                maxEntries: Self.maxTrackedEntries
            )
            nameBySerial = compacted.mapValues { Optional($0) }
        }
        if !wasPresent && !reenumerating {
            Log.info("AOA USB attached: \(resolvedName ?? serial)")
        }
        publish()
    }

    private func finishDetach(serial: String, fallbackName: String?) {
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.pendingDetach.removeValue(forKey: serial)
            guard !self.serialByEntry.values.contains(serial) else { return }
            Log.info("AOA USB detached: \(fallbackName ?? serial)")
            self.publish()
        }
    }

    private func publish() {
        var activeSerials = Set(serialByEntry.values)
        activeSerials.formUnion(pendingDetach.keys)
        let snapshot = activeSerials
            .map { serial in
                UsbmuxDevice(
                    deviceID: 0,
                    udid: AOA.prefix + serial,
                    name: nameBySerial[serial] ?? nil
                )
            }
            .sorted { $0.udid < $1.udid }
        let cb = onChange
        Task { @MainActor in cb(snapshot) }
    }

    private func publishBusy() {
        let activeSerials = Set(serialByEntry.values)
        let snapshot = busyDevices
            .filter { !adbClaimedSerials.contains($0.key) && !activeSerials.contains($0.key) }
            .map { UsbmuxDevice(deviceID: 0, udid: AOA.prefix + $0.key, name: $0.value) }
            .sorted { $0.udid < $1.udid }
        let cb = onBusyChange
        Task { @MainActor in cb(snapshot) }
    }
}

private extension AOA {
    static func isAccessoryName(_ name: String?) -> Bool {
        guard let lower = name?.lowercased() else { return true }
        return lower.contains("accessory") || lower == model.lowercased()
    }
}
