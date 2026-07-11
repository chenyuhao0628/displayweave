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

    func start(runId: String) throws {
        try queue.sync {
            guard active == nil else { throw BenchmarkRecorderError.alreadyStarted }
            guard Self.valid(runId: runId) else { throw BenchmarkRecorderError.invalidRunId }
            let directory = rootURL.appendingPathComponent(runId, isDirectory: true)
            guard !fileManager.fileExists(atPath: directory.path) else {
                throw BenchmarkRecorderError.runDirectoryExists
            }
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                let csvURL = directory.appendingPathComponent("benchmark.csv")
                let jsonlURL = directory.appendingPathComponent("benchmark.jsonl")
                guard fileManager.createFile(atPath: csvURL.path, contents: nil),
                      fileManager.createFile(atPath: jsonlURL.path, contents: nil) else {
                    throw BenchmarkRecorderError.fileOperationFailed("could not create output files")
                }
                let csv = try FileHandle(forWritingTo: csvURL)
                let jsonl = try FileHandle(forWritingTo: jsonlURL)
                let header = BenchmarkSample.csvHeader.joined(separator: ",") + "\r\n"
                try csv.write(contentsOf: Data(header.utf8))
                active = ActiveRun(
                    runId: runId,
                    urls: BenchmarkOutputURLs(csvURL: csvURL, jsonlURL: jsonlURL),
                    csv: csv,
                    jsonl: jsonl)
            } catch let error as BenchmarkRecorderError {
                try? fileManager.removeItem(at: directory)
                throw error
            } catch {
                try? fileManager.removeItem(at: directory)
                throw BenchmarkRecorderError.fileOperationFailed(error.localizedDescription)
            }
        }
    }

    func append(_ sample: BenchmarkSample) throws {
        try queue.sync {
            guard let active else { throw BenchmarkRecorderError.notStarted }
            guard sample.runId == active.runId else { throw BenchmarkRecorderError.runIdMismatch }
            do {
                try active.csv.write(contentsOf: Data((sample.csv(includeHeader: false) + "\r\n").utf8))
                try active.jsonl.write(contentsOf: Data((try sample.jsonLine() + "\n").utf8))
            } catch let error as BenchmarkRecorderError {
                throw error
            } catch {
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
