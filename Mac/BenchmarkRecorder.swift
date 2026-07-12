import Foundation

enum BenchmarkRecorderError: Error, CustomStringConvertible {
    case notStarted
    case alreadyStarted
    case invalidRunId
    case runDirectoryExists
    case runIdMismatch
    case fileOperationFailed(String)

    var description: String {
        switch self {
        case .notStarted: return "notStarted"
        case .alreadyStarted: return "alreadyStarted"
        case .invalidRunId: return "invalidRunId"
        case .runDirectoryExists: return "runDirectoryExists"
        case .runIdMismatch: return "runIdMismatch"
        case let .fileOperationFailed(message): return "fileOperationFailed: \(message)"
        }
    }
}

struct BenchmarkOutputURLs {
    var csvURL: URL
    var jsonlURL: URL
}

final class BenchmarkRecorder {
    private struct ActiveRun {
        var runId: String
        var urls: BenchmarkOutputURLs
        var csv: FileHandle
        var jsonl: FileHandle
    }

    private let rootURL: URL
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "app.displayweave.benchmark-recorder")
    private var active: ActiveRun?

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    var isActive: Bool { queue.sync { active != nil } }

    var activeRunId: String? { queue.sync { active?.runId } }

    func start(runId: String) throws {
        try queue.sync {
            guard active == nil else { throw BenchmarkRecorderError.alreadyStarted }
            guard Self.valid(runId: runId) else { throw BenchmarkRecorderError.invalidRunId }
            let directory = rootURL.appendingPathComponent(runId, isDirectory: true)
            var ownsDirectory = false
            var openedCSV: FileHandle?
            var openedJSONL: FileHandle?
            do {
                try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
                do {
                    try fileManager.createDirectory(
                        at: directory, withIntermediateDirectories: false)
                    ownsDirectory = true
                } catch {
                    let nsError = error as NSError
                    if nsError.domain == NSCocoaErrorDomain,
                       nsError.code == NSFileWriteFileExistsError {
                        throw BenchmarkRecorderError.runDirectoryExists
                    }
                    throw error
                }
                let csvURL = directory.appendingPathComponent("benchmark.csv")
                let jsonlURL = directory.appendingPathComponent("benchmark.jsonl")
                guard fileManager.createFile(atPath: csvURL.path, contents: nil),
                      fileManager.createFile(atPath: jsonlURL.path, contents: nil) else {
                    throw BenchmarkRecorderError.fileOperationFailed("could not create output files")
                }
                let csv = try FileHandle(forWritingTo: csvURL)
                openedCSV = csv
                let jsonl = try FileHandle(forWritingTo: jsonlURL)
                openedJSONL = jsonl
                let header = BenchmarkSample.csvHeader.joined(separator: ",") + "\r\n"
                try csv.write(contentsOf: Data(header.utf8))
                active = ActiveRun(
                    runId: runId,
                    urls: BenchmarkOutputURLs(csvURL: csvURL, jsonlURL: jsonlURL),
                    csv: csv,
                    jsonl: jsonl)
            } catch let error as BenchmarkRecorderError {
                try? openedCSV?.close()
                try? openedJSONL?.close()
                if ownsDirectory { try? fileManager.removeItem(at: directory) }
                throw error
            } catch {
                try? openedCSV?.close()
                try? openedJSONL?.close()
                if ownsDirectory { try? fileManager.removeItem(at: directory) }
                throw BenchmarkRecorderError.fileOperationFailed(error.localizedDescription)
            }
        }
    }

    func append(_ sample: BenchmarkSample) throws {
        try queue.sync {
            guard let active else { throw BenchmarkRecorderError.notStarted }
            guard sample.runId == active.runId else { throw BenchmarkRecorderError.runIdMismatch }
            do {
                let csvData = Data((sample.csv(includeHeader: false) + "\r\n").utf8)
                let jsonlData = Data((try sample.jsonLine() + "\n").utf8)
                let csvOffset = try active.csv.offset()
                let jsonlOffset = try active.jsonl.offset()
                do {
                    try active.csv.write(contentsOf: csvData)
                    try active.jsonl.write(contentsOf: jsonlData)
                } catch {
                    do {
                        try active.csv.truncate(atOffset: csvOffset)
                        try active.jsonl.truncate(atOffset: jsonlOffset)
                        try active.csv.seek(toOffset: csvOffset)
                        try active.jsonl.seek(toOffset: jsonlOffset)
                    } catch let rollbackError {
                        self.active = nil
                        try? active.csv.close()
                        try? active.jsonl.close()
                        throw BenchmarkRecorderError.fileOperationFailed(
                            "write failed and rollback failed: \(rollbackError.localizedDescription)")
                    }
                    throw error
                }
            } catch {
                if let recorderError = error as? BenchmarkRecorderError {
                    throw recorderError
                }
                throw BenchmarkRecorderError.fileOperationFailed(error.localizedDescription)
            }
        }
    }

    func stop() throws -> BenchmarkOutputURLs {
        try queue.sync {
            guard let run = active else { throw BenchmarkRecorderError.notStarted }
            do {
                try run.csv.synchronize()
                try run.jsonl.synchronize()
                try run.csv.close()
                try run.jsonl.close()
                active = nil
                return run.urls
            } catch {
                active = nil
                try? run.csv.close()
                try? run.jsonl.close()
                throw BenchmarkRecorderError.fileOperationFailed(error.localizedDescription)
            }
        }
    }

    private static func valid(runId: String) -> Bool {
        guard !runId.isEmpty, runId != ".", runId != ".." else { return false }
        return runId.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        }
    }
}
