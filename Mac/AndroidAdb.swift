import Foundation

enum AndroidAdbState: Equatable, Sendable {
    case device
    case unauthorized
    case offline
    case unknown(String)
}

enum AndroidAdbConnectionKind: Equatable, Sendable {
    case usb
    case wirelessDebugging
    case unknown
}

struct AndroidAdbDevice: Equatable, Identifiable, Sendable {
    let serial: String
    let state: AndroidAdbState
    let model: String?
    let connectionKind: AndroidAdbConnectionKind
    let product: String?
    let device: String?

    var id: String { serial }

    init(serial: String, state: AndroidAdbState, model: String?,
         connectionKind: AndroidAdbConnectionKind = .unknown,
         product: String? = nil, device: String? = nil) {
        self.serial = serial
        self.state = state
        self.model = model
        self.connectionKind = connectionKind
        self.product = product
        self.device = device
    }
}

enum AndroidAdbDeviceSelection {
    static func usbDevices(from devices: [AndroidAdbDevice]) -> [AndroidAdbDevice] {
        devices.filter { $0.connectionKind == .usb }
    }
}

struct AndroidAdbPresentation: Equatable, Sendable {
    let message: String
    let connectableSerials: [String]

    static func make(executableFound: Bool,
                     devices: [AndroidAdbDevice]) -> AndroidAdbPresentation {
        guard executableFound else {
            return AndroidAdbPresentation(message: "未找到 ADB，请配置 Android SDK 中的 adb 路径",
                                          connectableSerials: [])
        }
        guard !devices.isEmpty else {
            return AndroidAdbPresentation(message: AndroidAdbFailure.noDevices.localizedDescription,
                                          connectableSerials: [])
        }
        let ready = devices.filter { $0.state == .device }.map(\.serial)
        if ready.count > 1 {
            return AndroidAdbPresentation(
                message: AndroidAdbFailure.multipleDevices(ready).localizedDescription,
                connectableSerials: ready)
        }
        if ready.count == 1 {
            return AndroidAdbPresentation(message: "Android USB 设备已就绪",
                                          connectableSerials: ready)
        }
        if let unauthorized = devices.first(where: { $0.state == .unauthorized }) {
            return AndroidAdbPresentation(
                message: AndroidAdbFailure.unauthorized(unauthorized.serial).localizedDescription,
                connectableSerials: [])
        }
        if let offline = devices.first(where: { $0.state == .offline }) {
            return AndroidAdbPresentation(
                message: AndroidAdbFailure.offline(offline.serial).localizedDescription,
                connectableSerials: [])
        }
        return AndroidAdbPresentation(message: "ADB 设备不可用", connectableSerials: [])
    }
}

enum AndroidAdbDeviceList {
    static func parse(_ output: String) -> [AndroidAdbDevice] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard fields.count >= 2, fields[0] != "List" else { return nil }

            let state: AndroidAdbState
            switch fields[1] {
            case "device": state = .device
            case "unauthorized": state = .unauthorized
            case "offline": state = .offline
            default: state = .unknown(fields[1])
            }

            var metadata: [String: String] = [:]
            for field in fields.dropFirst(2) {
                guard let separator = field.firstIndex(of: ":") else { continue }
                let key = String(field[..<separator])
                let value = String(field[field.index(after: separator)...])
                metadata[key] = value
            }
            let model = metadata["model"]?.replacingOccurrences(of: "_", with: " ")
            let connectionKind: AndroidAdbConnectionKind
            if metadata["usb"] != nil {
                connectionKind = .usb
            } else if fields[0].contains("._adb-tls-connect._tcp") {
                connectionKind = .wirelessDebugging
            } else {
                connectionKind = .unknown
            }
            return AndroidAdbDevice(serial: fields[0], state: state, model: model,
                                    connectionKind: connectionKind,
                                    product: metadata["product"], device: metadata["device"])
        }
    }
}

enum AndroidAdbFailure: Error, LocalizedError, Equatable {
    case executableNotFound([String])
    case noDevices
    case unauthorized(String)
    case offline(String)
    case multipleDevices([String])
    case commandFailed(exitCode: Int32, message: String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let paths):
            return "未找到 ADB。已检查：\(paths.joined(separator: "、"))"
        case .noDevices:
            return "未检测到 Android 设备"
        case .unauthorized:
            return "设备尚未授权 USB 调试，请在 Android 设备上允许当前 Mac"
        case .offline:
            return "ADB 设备离线"
        case .multipleDevices:
            return "检测到多个 Android 设备，请选择目标设备"
        case .commandFailed(let exitCode, let message):
            return "ADB 命令失败（退出码 \(exitCode)）：\(message)"
        case .timedOut:
            return "ADB 命令超时"
        }
    }
}

struct AndroidAdbCommandResult: Equatable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

protocol AndroidAdbProcessRunning: Sendable {
    func run(executable: URL, arguments: [String], timeout: Duration) async throws
        -> AndroidAdbCommandResult
}

struct FoundationAdbProcessRunner: AndroidAdbProcessRunning {
    func run(executable: URL, arguments: [String], timeout: Duration) async throws
        -> AndroidAdbCommandResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Int32?.self) { group in
                group.addTask {
                    process.waitUntilExit()
                    return process.terminationStatus
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    return nil
                }

                guard let first = try await group.next() else {
                    throw AndroidAdbFailure.timedOut
                }
                if first == nil {
                    if process.isRunning { process.terminate() }
                    process.waitUntilExit()
                    group.cancelAll()
                    throw AndroidAdbFailure.timedOut
                }
                group.cancelAll()
                let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                return AndroidAdbCommandResult(
                    stdout: String(decoding: outputData, as: UTF8.self),
                    stderr: String(decoding: errorData, as: UTF8.self),
                    exitCode: first!)
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

enum AndroidAdbExecutableResolver {
    static func resolve(
        configuredPath: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        isExecutable: (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) }
    ) -> URL? {
        var candidates: [URL] = []
        if let configuredPath, !configuredPath.isEmpty {
            candidates.append(expand(configuredPath, homeDirectory: homeDirectory))
        }
        for directory in environment["PATH"]?.split(separator: ":") ?? [] {
            candidates.append(URL(fileURLWithPath: String(directory)).appendingPathComponent("adb"))
        }
        if let androidHome = environment["ANDROID_HOME"], !androidHome.isEmpty {
            candidates.append(URL(fileURLWithPath: androidHome)
                .appendingPathComponent("platform-tools/adb"))
        }
        if let sdkRoot = environment["ANDROID_SDK_ROOT"], !sdkRoot.isEmpty {
            candidates.append(URL(fileURLWithPath: sdkRoot)
                .appendingPathComponent("platform-tools/adb"))
        }
        candidates.append(homeDirectory.appendingPathComponent("Library/Android/sdk/platform-tools/adb"))
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/adb"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/adb"))
        return candidates.first { fileExists($0) && isExecutable($0) }
    }

    static func searchedPaths(
        configuredPath: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        var paths: [String] = []
        if let configuredPath, !configuredPath.isEmpty {
            paths.append(expand(configuredPath, homeDirectory: homeDirectory).path)
        }
        paths += (environment["PATH"]?.split(separator: ":") ?? []).map {
            URL(fileURLWithPath: String($0)).appendingPathComponent("adb").path
        }
        if let value = environment["ANDROID_HOME"], !value.isEmpty {
            paths.append(URL(fileURLWithPath: value).appendingPathComponent("platform-tools/adb").path)
        }
        if let value = environment["ANDROID_SDK_ROOT"], !value.isEmpty {
            paths.append(URL(fileURLWithPath: value).appendingPathComponent("platform-tools/adb").path)
        }
        paths.append(homeDirectory.appendingPathComponent("Library/Android/sdk/platform-tools/adb").path)
        paths.append("/opt/homebrew/bin/adb")
        paths.append("/usr/local/bin/adb")
        return paths
    }

    private static func expand(_ path: String, homeDirectory: URL) -> URL {
        if path == "~" { return homeDirectory }
        if path.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(path.dropFirst(2)))
        }
        return URL(fileURLWithPath: path)
    }
}

struct AndroidAdbClient: Sendable {
    let executable: URL
    let runner: any AndroidAdbProcessRunning

    func devices() async throws -> [AndroidAdbDevice] {
        let result = try await runner.run(executable: executable,
                                          arguments: ["devices", "-l"],
                                          timeout: .seconds(10))
        guard result.exitCode == 0 else {
            throw AndroidAdbFailure.commandFailed(exitCode: result.exitCode,
                                                  message: result.stderr)
        }
        return AndroidAdbDeviceList.parse(result.stdout)
    }

    @discardableResult
    func run(serial: String, arguments: [String]) async throws -> AndroidAdbCommandResult {
        let result = try await runner.run(executable: executable,
                                          arguments: ["-s", serial] + arguments,
                                          timeout: .seconds(10))
        guard result.exitCode == 0 else {
            throw AndroidAdbFailure.commandFailed(exitCode: result.exitCode,
                                                  message: result.stderr)
        }
        return result
    }
}
