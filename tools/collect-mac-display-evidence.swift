#!/usr/bin/env swift
// DisplayWeave customer geometry snapshot. GPL-3.0; see LICENSE in the repository.
// Read-only: no display creation/configuration, application launch, preference
// writes, screenshots, permission requests, network access, or automatic upload.
import AppKit
import ApplicationServices
import CryptoKit
import Darwin
import SystemConfiguration

let usage = """
Usage: xcrun swift collect-mac-display-evidence.swift \
  --machine A --role sender --case C00 --phase failing --output /absolute/local/folder \
  [--hardware] [--window-pid 1234] [--app-path /Applications/DisplayWeave.app]

Start on the Mac running Codex. Each call creates a new private LOCAL snapshot.
--machine and --role label the source; they do not select or connect to another Mac.
Collect peer evidence only when useful, using an existing authorized access method.
--hardware adds a bounded GPU/display system_profiler query; use on the first snapshot only.
--window-pid includes bounds for one customer-chosen neutral test app, without titles.
--app-path inspects an extra installed copy WITHOUT launching it. Running apps are discovered separately.
No compiler? Do not install tools during the baseline; follow the guide's fallback.
Copied application logs are PRIVATE and need review/redaction before sharing.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

struct Options {
    var machine = "", role = "", caseID = "", phase = "", output = ""
    var hardware = false
    var windowPID: pid_t?
    var appPath: String?
    init(_ arguments: [String]) {
        var i = 0
        var seen = Set<String>()
        while i < arguments.count {
            let key = arguments[i]
            if key == "--help" { print(usage); exit(0) }
            guard seen.insert(key).inserted else { fail("Repeated option: \(key)") }
            if key == "--hardware" { hardware = true; i += 1; continue }
            guard i + 1 < arguments.count else { fail("Missing value for \(key)\n\(usage)") }
            let value = arguments[i + 1]
            switch key {
            case "--machine": machine = value
            case "--role": role = value
            case "--case": caseID = value
            case "--phase": phase = value
            case "--output": output = value
            case "--window-pid":
                guard let pid = Int32(value), pid > 0 else { fail("Invalid positive PID") }
                windowPID = pid
            case "--app-path": appPath = value
            default: fail("Unknown option: \(key)\n\(usage)")
            }
            i += 2
        }
        let token = "^[A-Za-z0-9_-]{1,40}$"
        guard ["A", "B"].contains(machine), ["sender", "receiver"].contains(role),
              caseID.range(of: token, options: .regularExpression) != nil,
              phase.range(of: token, options: .regularExpression) != nil,
              output.hasPrefix("/"), appPath == nil || appPath!.hasPrefix("/") else { fail(usage) }
    }
}

let options = Options(Array(CommandLine.arguments.dropFirst()))
// Only new evidence files are created. Restrict them even if the caller's umask is permissive.
umask(0o077)
let fm = FileManager.default
let started = Date()
let iso = ISO8601DateFormatter()
iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
let stamp = iso.string(from: started).replacingOccurrences(of: ":", with: "-")
let output = URL(fileURLWithPath: options.output, isDirectory: true)
    .appendingPathComponent("\(options.caseID)-\(options.machine)-\(options.phase)-\(stamp)-\(UUID().uuidString.prefix(8))", isDirectory: true)
do { try fm.createDirectory(at: output, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
catch { fail("Cannot create evidence directory: \(error)") }

func json(_ object: Any, to name: String) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: output.appendingPathComponent(name), options: .atomic)
}
func size(_ s: CGSize) -> [String: Double] { ["width": s.width, "height": s.height] }
func rect(_ r: CGRect) -> [String: Double] { ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height] }
func homeRedacted(_ path: String?) -> Any {
    guard let path else { return NSNull() }
    let home = fm.homeDirectoryForCurrentUser.path
    return path == home || path.hasPrefix(home + "/") ? "$HOME" + path.dropFirst(home.count) : path
}
func sysctlString(_ name: String) -> String? {
    var count = 0
    guard sysctlbyname(name, nil, &count, nil, 0) == 0, count > 0, count <= 4096 else { return nil }
    var bytes = [UInt8](repeating: 0, count: count)
    guard sysctlbyname(name, &bytes, &count, nil, 0) == 0 else { return nil }
    return String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
}
func mode(_ m: CGDisplayMode) -> [String: Any] {
    ["modeID": m.ioDisplayModeID, "width": m.width, "height": m.height,
     "pixelWidth": m.pixelWidth, "pixelHeight": m.pixelHeight,
     "refreshHz": m.refreshRate, "ioFlags": m.ioFlags,
     "usableForDesktopGUI": m.isUsableForDesktopGUI()]
}

// An SSH shell may not share the desktop user's WindowServer/permission context.
// Export scope hints, never SSH endpoints, account names or environment contents.
func executionContext() -> [String: Any] {
    var consoleUID: uid_t = 0
    var consoleGID: gid_t = 0
    let consoleName = SCDynamicStoreCopyConsoleUser(nil, &consoleUID, &consoleGID) as String?
    let consoleUserPresent = consoleName.map { !["loginwindow", "_mbsetupuser"].contains($0) } ?? false
    let sshHint = ["SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY"].contains { ProcessInfo.processInfo.environment[$0] != nil }
    return ["sshEnvironmentPresent": sshHint, "effectiveUserID": geteuid(),
            "consoleUserPresent": consoleUserPresent,
            "consoleUserID": consoleUserPresent ? consoleUID as Any : NSNull(),
            "matchesConsoleUser": consoleUserPresent ? (geteuid() == consoleUID) as Any : NSNull(),
            "machineAndRoleAreCallerLabels": true,
            "note": "Only this execution host is measured. SSH hints and matching user IDs do not prove access to the active graphical session. Empty app/window lists may mean unavailable session access, not absence of a running app. Preferences belong to the executing user; no account switching is attempted."]
}

// Numeric display IDs are local WindowServer identifiers, not hardware serials.
func displays() -> [String: Any] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 64)
    var count: UInt32 = 0
    let result = CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count)
    let cg: [[String: Any]] = result == .success ? ids.prefix(Int(min(count, 64))).map { id in
        let modes = CGDisplayCopyAllDisplayModes(id,
            [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] ?? []
        return ["displayID": id, "online": CGDisplayIsOnline(id) != 0, "active": CGDisplayIsActive(id) != 0,
                "builtIn": CGDisplayIsBuiltin(id) != 0, "main": CGDisplayIsMain(id) != 0,
                "asleep": CGDisplayIsAsleep(id) != 0, "rotationDegrees": CGDisplayRotation(id),
                "mirrorTargetID": CGDisplayMirrorsDisplay(id), "bounds": rect(CGDisplayBounds(id)),
                "reportedMillimeters": size(CGDisplayScreenSize(id)),
                "vendorNumber": CGDisplayVendorNumber(id), "modelNumber": CGDisplayModelNumber(id),
                "matchesDisplayWeaveVirtualVendorProduct": CGDisplayVendorNumber(id) == 0x5043 && CGDisplayModelNumber(id) == 0x4F53,
                "currentMode": CGDisplayCopyDisplayMode(id).map(mode) as Any? ?? NSNull(),
                "availableModes": modes.prefix(256).map(mode), "availableModeCount": modes.count,
                "availableModesTruncated": modes.count > 256]
    } : []
    let ns: [[String: Any]] = NSScreen.screens.prefix(64).map { screen in
        let inset = screen.safeAreaInsets
        return ["displayID": (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) ?? 0,
                "frame": rect(screen.frame), "visibleFrame": rect(screen.visibleFrame),
                "backingScaleFactor": screen.backingScaleFactor,
                "maximumFramesPerSecond": screen.maximumFramesPerSecond,
                "safeAreaInsets": ["top": inset.top, "bottom": inset.bottom, "left": inset.left, "right": inset.right]]
    }
    return ["capturedAtUTC": iso.string(from: Date()), "onlineListError": result.rawValue,
            "displayListAtCapacity": count >= 64, "coreGraphics": cg, "appKit": ns,
            "note": "Current mode backing pixels are not a measurement of native panel pixels. Reported millimeters may be synthetic. CG and AppKit origins use different coordinate conventions."]
}

let knownIDs: Set<String> = ["app.displayweave.mac", "app.displayweave.mac.debug"]
let running = NSWorkspace.shared.runningApplications.filter {
    knownIDs.contains($0.bundleIdentifier ?? "") ||
        ["DisplayWeave", "OpenSidecar"].contains($0.executableURL?.lastPathComponent ?? "")
}.prefix(8)

func appInfo(_ url: URL) -> [String: Any] {
    guard let bundle = Bundle(url: url) else { return ["bundlePath": homeRedacted(url.path), "status": "unreadable"] }
    func modified(_ file: URL?) -> Any {
        guard let file, let attributes = try? fm.attributesOfItem(atPath: file.path),
              let date = attributes[.modificationDate] as? Date else { return NSNull() }
        return iso.string(from: date)
    }
    return ["bundlePath": homeRedacted(url.path), "executablePath": homeRedacted(bundle.executableURL?.path),
            "bundleID": bundle.bundleIdentifier as Any? ?? NSNull(),
            "version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as Any? ?? NSNull(),
            "build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") as Any? ?? NSNull(),
            "executableArchitectures": bundle.executableArchitectures as Any? ?? NSNull(),
            "executableModifiedUTC": modified(bundle.executableURL),
            "infoPlistModifiedUTC": modified(url.appendingPathComponent("Contents/Info.plist"))]
}
func preferenceSnapshot(_ id: String) -> [String: Any] {
    let keys = ["macRole", "mode", "receiverDisplayID", "receiverFullscreen", "fpsMode", "fps", "codecMode", "codec",
                "quality", "transportMode", "debugStats", "bitrateMode", "bitrateMbps", "streamPriority", "adaptEncoderLoad"]
    let allowed: Set<String> = ["automatic", "native", "fullHD", "quadHD", "ultraHD", "iMac4K", "iMac4_5K", "iMac5K"]
    func safeResolution(_ value: String) -> String { allowed.contains(value) ? value : "unknown" }
    var values: [String: Any] = [:]
    for key in keys {
        guard let value = CFPreferencesCopyAppValue(key as CFString, id as CFString) else { continue }
        if let string = value as? String { values[key] = String(string.prefix(128)) }
        else if let number = value as? NSNumber { values[key] = number }
    }
    if let savedDefault = CFPreferencesCopyAppValue("desktopResolutionDefault.v2" as CFString, id as CFString) as? String {
        values["desktopResolutionDefault.v2"] = safeResolution(savedDefault)
    }
    if let saved = CFPreferencesCopyAppValue("desktopResolutions.v1" as CFString, id as CFString) as? [String: String] {
        values["desktopResolutions.v1"] = saved.keys.sorted().prefix(128).map { peer -> [String: String] in
            let hash = SHA256.hash(data: Data(peer.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
            return ["peerAlias": "peer-" + hash, "resolution": safeResolution(saved[peer] ?? "")]
        }
    }
    return ["bundleID": id, "storedValuesOnly": values,
            "note": "Missing keys are unknown/default, not false. In-memory settings or launch overrides may differ. Peer aliases are SHA256(installation ID), first 12 hex digits. No identity/trust/invitation keys exported."]
}

// Window bounds are outer-window geometry, never private NSView/video-layer bounds.
let windowPIDs = Set(running.map(\.processIdentifier) + (options.windowPID.map { [$0] } ?? []))
func windows() -> [String: Any] {
    let all = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    let matching = (all ?? []).filter { windowPIDs.contains(($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0) }
    let records = matching.prefix(128).map { item -> [String: Any] in
        var record: [String: Any] = [:]
        for key in [kCGWindowNumber, kCGWindowOwnerPID, kCGWindowBounds, kCGWindowLayer, kCGWindowIsOnscreen, kCGWindowAlpha] {
            record[key as String] = item[key as String]
        }
        return record
    }
    return ["status": all == nil ? "unavailable" : "query-completed",
            "capturedAtUTC": iso.string(from: Date()), "records": records, "truncated": matching.count > 128,
            "note": "No window titles or other applications exported. Missing windows may be restricted by permissions or Spaces. These are outer bounds, not the video rectangle."]
}

// Read existing AX permission only. No AXIsProcessTrustedWithOptions(prompt:true).
func accessibilityWindows() -> [String: Any] {
    guard AXIsProcessTrusted() else { return ["status": "SKIP: collector has no existing Accessibility permission"] }
    let deadline = Date().addingTimeInterval(4)
    var records: [[String: Any]] = []
    for pid in windowPIDs.sorted() {
        guard Date() < deadline else { break }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        var appRecord: [String: Any] = ["pid": pid, "error": status.rawValue]
        if status == .success, let list = value as? [AXUIElement] {
            appRecord["truncated"] = list.count > 16
            appRecord["windows"] = list.prefix(16).enumerated().map { index, window -> [String: Any] in
                guard Date() < deadline else { return ["status": "SKIP: four-second AX collection budget reached"] }
                AXUIElementSetMessagingTimeout(window, 0.2)
                var item: [String: Any] = ["indexWithinThisSnapshot": index]
                for attribute in [kAXPositionAttribute, kAXSizeAttribute, "AXFullScreen"] {
                    var raw: CFTypeRef?
                    let error = AXUIElementCopyAttributeValue(window, attribute as CFString, &raw)
                    item[attribute + "Error"] = error.rawValue
                    guard error == .success, let raw else { continue }
                    if attribute == "AXFullScreen", let bool = raw as? NSNumber { item[attribute] = bool; continue }
                    guard CFGetTypeID(raw) == AXValueGetTypeID() else { continue }
                    let ax = raw as! AXValue
                    if AXValueGetType(ax) == .cgPoint {
                        var point = CGPoint.zero
                        if AXValueGetValue(ax, .cgPoint, &point) { item[attribute] = ["x": point.x, "y": point.y] }
                    } else if AXValueGetType(ax) == .cgSize {
                        var s = CGSize.zero
                        if AXValueGetValue(ax, .cgSize, &s) { item[attribute] = size(s) }
                    }
                }
                return item
            }
        }
        records.append(appRecord)
    }
    return ["status": "queried", "records": records, "timeBudgetReached": Date() >= deadline,
            "note": "AX indices are not stable window IDs. Match the single neutral test window with CG window numbers and timestamps; content bounds remain unmeasured."]
}

// Copy only the two known, bounded log files; never traverse directories or export defaults wholesale.
func copyLogs() -> [[String: Any]] {
    ["/tmp/opensidecar-mac.log.previous", "/tmp/opensidecar-mac.log"].map { path in
        var record: [String: Any] = ["source": path, "copyStartedUTC": iso.string(from: Date())]
        do {
            let attr = try fm.attributesOfItem(atPath: path)
            guard attr[.type] as? FileAttributeType == .typeRegular else {
                record["status"] = "SKIP: not a regular file"; return record
            }
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
            defer { try? handle.close() }
            let length = try handle.seekToEnd()
            let limit: UInt64 = 2 * 1024 * 1024
            try handle.seek(toOffset: length > limit ? length - limit : 0)
            let data = try handle.read(upToCount: Int(limit)) ?? Data()
            let name = "PRIVATE-" + URL(fileURLWithPath: path).lastPathComponent
            try data.write(to: output.appendingPathComponent(name), options: .atomic)
            record["status"] = "copied; private, review before sharing"
            record["file"] = name
            record["sourceBytesAtCopy"] = length
            record["copiedBytes"] = data.count
            record["tailTruncated"] = length > limit
            record["sourceModifiedUTC"] = (attr[.modificationDate] as? Date).map { iso.string(from: $0) } as Any? ?? NSNull()
        } catch { record["status"] = "unavailable: \(error.localizedDescription)" }
        record["copyFinishedUTC"] = iso.string(from: Date())
        return record
    }
}

// Optional, runs AFTER the geometry snapshot to keep profiler load out of the reproduction instant.
func gpuSummary() -> [String: Any] {
    guard options.hardware else { return ["status": "SKIP: use --hardware once for GPU/display profiler fields"] }
    let temporary = output.appendingPathComponent(".profiler-private-temporary.json")
    defer { try? fm.removeItem(at: temporary) }
    guard fm.createFile(atPath: temporary.path, contents: nil),
          let handle = try? FileHandle(forWritingTo: temporary) else { return ["status": "unavailable: temp file"] }
    defer { try? handle.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    process.arguments = ["SPDisplaysDataType", "-json", "-detailLevel", "mini", "-timeout", "10"]
    process.standardOutput = handle
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return ["status": "unavailable: \(error.localizedDescription)"] }
    let deadline = Date().addingTimeInterval(15)
    while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    if process.isRunning {
        process.terminate()
        Thread.sleep(forTimeInterval: 0.1)
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        return ["status": "SKIP: system_profiler exceeded 15 seconds"]
    }
    guard process.terminationStatus == 0,
          let attr = try? fm.attributesOfItem(atPath: temporary.path),
          let bytes = attr[.size] as? NSNumber, bytes.intValue <= 2 * 1024 * 1024,
          let data = try? Data(contentsOf: temporary),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let gpus = object["SPDisplaysDataType"] as? [[String: Any]] else { return ["status": "unavailable: profiler format, size or exit status"] }
    func select(_ object: [String: Any], keys: [String]) -> [String: Any] {
        var result: [String: Any] = [:]
        for key in keys { if let value = object[key] as? String { result[key] = String(value.prefix(256)) } }
        return result
    }
    let devices = gpus.prefix(16).map { gpu -> [String: Any] in
        var item = select(gpu, keys: ["sppci_model", "spdisplays_vendor", "spdisplays_vram", "spdisplays_vram_shared", "spdisplays_cores", "spdisplays_metal"])
        item["displays"] = ((gpu["spdisplays_ndrvs"] as? [[String: Any]]) ?? []).prefix(64).map {
            select($0, keys: ["_spdisplays_displayID", "spdisplays_resolution", "_spdisplays_resolution",
                             "spdisplays_pixels", "spdisplays_uiLooksLike", "spdisplays_display_type",
                             "spdisplays_main", "spdisplays_retina", "spdisplays_connection_type", "spdisplays_rotation"])
        }
        return item
    }
    return ["status": "collected", "devices": devices, "note": "Allowlisted profiler fields only; native panel pixels still need independent model/spec or customer confirmation."]
}

var snapshot: [String: Any] = [
    "schema": "displayweave.mac-geometry.v1", "collectorVersion": "3",
    "executionContext": executionContext(),
    "machine": options.machine, "role": options.role, "caseID": options.caseID, "phase": options.phase,
    "startedAtUTC": iso.string(from: started), "timezone": TimeZone.current.identifier,
    "secondsFromGMT": TimeZone.current.secondsFromGMT(for: started),
    "system": ["modelIdentifier": sysctlString("hw.model") as Any? ?? NSNull(),
               "architecture": sysctlString("hw.machine") as Any? ?? NSNull(),
               "cpu": sysctlString("machdep.cpu.brand_string") as Any? ?? NSNull(),
               "os": ProcessInfo.processInfo.operatingSystemVersionString,
               "osBuild": sysctlString("kern.osversion") as Any? ?? NSNull(),
               "memoryBytes": ProcessInfo.processInfo.physicalMemory],
    "geometry": displays(),
    "runningDisplayWeaveApps": running.map { app -> [String: Any] in
        var record = app.bundleURL.map(appInfo) ?? [:]
        record["pid"] = app.processIdentifier
        record["launchedAtUTC"] = app.launchDate.map { iso.string(from: $0) } as Any? ?? NSNull()
        record["runningExecutablePath"] = homeRedacted(app.executableURL?.path)
        record["runningArchitecture"] = app.executableArchitecture
        record["runningArchitectureName"] = [16777228: "arm64", 16777223: "x86_64"][app.executableArchitecture] ?? "other"
        record["versionSource"] = "Info.plist at running bundle path; if files changed since launch, the loaded executable may differ."
        return record
    },
    "preferences": Set(running.compactMap(\.bundleIdentifier)).sorted().map(preferenceSnapshot),
    "windowOwnerPIDs": windowPIDs.sorted(), "windows": windows(),
    "limits": ["Receiver private view/layer bounds and actual hello are not measured by this external collector.",
               "No native physical resolution is inferred from a mode, mode list, or frame times backing scale.",
               "No process arguments, window titles, screenshots, serials, UUIDs, trust keys or full preferences exported.",
               "Log copies may contain private identifiers; review and redact locally before sharing.",
               "This is a sequential snapshot, not an atomic cross-machine measurement. Record clock offsets and case events."]
]
snapshot["logs"] = copyLogs()
snapshot["accessibility"] = accessibilityWindows()
if let path = options.appPath { snapshot["extraInstalledCopyNotNecessarilyRunning"] = appInfo(URL(fileURLWithPath: path)) }
snapshot["geometryStageFinishedUTC"] = iso.string(from: Date())
snapshot["hardware"] = gpuSummary()
snapshot["finishedAtUTC"] = iso.string(from: Date())
do {
    try json(snapshot, to: "snapshot.json")
    try Data("""
    PRIVATE evidence; review locally before sharing.
    Raw logs can contain device names, addresses and IDs. Keep timestamps, geometry,
    configVersion/sessionEpoch and performance numbers when making redacted copies.
    snapshot.json uses only selected fields, but paths/metadata still need review.
    The collector did not capture screen content or inspect private video-view bounds.
    Do not zip this directory until you have created and reviewed a separate redacted copy.
    Log timestamps may have time-of-day only; use snapshot timezone and case timeline.
    Logs may rotate during a copy; preserve both files, gaps and truncation indicators.
    """.utf8).write(to: output.appendingPathComponent("READ-BEFORE-SHARING.txt"), options: .atomic)
    print("Private snapshot saved: \(output.path)")
} catch { fail("Could not finish snapshot: \(error)") }
