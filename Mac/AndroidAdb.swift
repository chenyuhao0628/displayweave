import Foundation

enum AndroidAdbState: Equatable {
    case device
    case unauthorized
    case offline
    case unknown(String)
}

struct AndroidAdbDevice: Equatable, Identifiable {
    let serial: String
    let state: AndroidAdbState
    let model: String?

    var id: String { serial }
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
            return AndroidAdbDevice(serial: fields[0], state: state, model: model)
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
