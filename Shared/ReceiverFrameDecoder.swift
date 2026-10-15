import Foundation

/// Legacy Apple framing. Each receive is bounded by 256 KiB; a peer-controlled
/// length is checked before waiting for (or allocating) the rest of its payload.
struct ReceiverFrameDecoder {
    enum Failure: Error { case invalidLength }
    static let maximumFrameBytes = 16 * 1024 * 1024
    let maxFrameBytes: Int
    private var buffer = Data()

    init(maxFrameBytes: Int = Self.maximumFrameBytes) { self.maxFrameBytes = maxFrameBytes }

    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        var cursor = buffer.startIndex
        while buffer.endIndex - cursor >= 4 {
            let length = buffer[cursor..<(cursor + 4)].withUnsafeBytes {
                Int(UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)))
            }
            guard length > 0, length <= maxFrameBytes else {
                buffer.removeAll()
                throw Failure.invalidLength
            }
            guard buffer.endIndex - cursor >= length + 4 else { break }
            frames.append(Data(buffer[(cursor + 4)..<(cursor + 4 + length)]))
            cursor += 4 + length
        }
        buffer.removeSubrange(buffer.startIndex..<cursor)
        return frames
    }

    static func frame(_ payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        var result = Data(bytes: &length, count: 4)
        result.append(payload)
        return result
    }
}
