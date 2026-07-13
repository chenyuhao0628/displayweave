import Foundation

@main
enum MetalRenderPassOrderingSelfTest {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceRoots = ["Mac", "iOS"].map { root.appendingPathComponent($0) }
        var encoderCount = 0

        for sourceRoot in sourceRoots {
            guard let enumerator = FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: nil
            ) else {
                preconditionFailure("Unable to enumerate \(sourceRoot.path)")
            }

            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                let lines = try String(contentsOf: fileURL, encoding: .utf8)
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map(String.init)

                for (index, line) in lines.enumerated()
                    where line.contains("makeRenderCommandEncoder(descriptor:") {
                    encoderCount += 1
                    let descriptor = descriptorName(in: line)
                    precondition(descriptor != nil,
                                 "Could not parse render-pass descriptor at \(location(fileURL, index))")

                    for laterIndex in (index + 1)..<lines.count {
                        let laterLine = lines[laterIndex]
                        if laterLine.contains("endEncoding()") { break }
                        precondition(
                            !laterLine.trimmingCharacters(in: .whitespaces)
                                .hasPrefix("\(descriptor!)."),
                            "Render-pass descriptor '\(descriptor!)' is mutated after encoder creation at "
                                + location(fileURL, laterIndex)
                        )
                    }
                }
            }
        }

        precondition(encoderCount > 0, "No Metal render encoders found; self-test scanned nothing")
        print("MetalRenderPassOrderingSelfTest PASS (\(encoderCount) encoders checked)")
    }

    private static func descriptorName(in line: String) -> String? {
        guard let marker = line.range(of: "makeRenderCommandEncoder(descriptor:") else {
            return nil
        }
        let suffix = line[marker.upperBound...]
        guard let close = suffix.firstIndex(of: ")") else { return nil }
        return suffix[..<close].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func location(_ fileURL: URL, _ zeroBasedLine: Int) -> String {
        "\(fileURL.path):\(zeroBasedLine + 1)"
    }
}
