// HEVC parameter-set handling adapted from peetzweg/opendisplay 91ca272 (GPL-3.0).
// DisplayWeave bounds NAL count, metadata, parameter sets and codec state.
import Foundation
import CoreMedia

enum ReceiverVideoCodec: String { case h264, hevc }

struct ReceiverVideoBitstream {
    enum Failure: Error { case malformed, invalidFormat }
    struct Packet {
        let slices: [Data]
        let keyframe: Bool
        let format: CMVideoFormatDescription?
        let formatChanged: Bool
    }
    let codec: ReceiverVideoCodec
    private var parameters: [UInt8: Data] = [:]
    private var format: CMVideoFormatDescription?

    init(codec: ReceiverVideoCodec) { self.codec = codec }

    mutating func parse(_ data: Data) throws -> Packet {
        var ranges: [Range<Int>] = []
        try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var start: Int?
            var i = 0
            while i + 4 <= bytes.count {
                if bytes[i] == 0, bytes[i+1] == 0, bytes[i+2] == 0, bytes[i+3] == 1 {
                    if let start {
                        guard start < i, ranges.count < 511 else { throw Failure.malformed }
                        ranges.append(start..<i)
                    } else if i > 16 * 1024 { throw Failure.malformed }
                    start = i + 4
                    i += 4
                } else { i += 1 }
            }
            guard let start, start < bytes.count else { throw Failure.malformed }
            ranges.append(start..<bytes.count)
        }
        var slices: [Data] = []
        var keyframe = false
        var changed = false
        for range in ranges {
            let nalu = data.subdata(in: range)
            guard nalu[0] & 0x80 == 0 else { throw Failure.malformed }
            let type: UInt8
            let isParameter: Bool
            if codec == .hevc {
                guard nalu.count >= 2, nalu[1] & 7 != 0 else { throw Failure.malformed }
                type = (nalu[0] >> 1) & 0x3f
                isParameter = (32...34).contains(type)
                if type <= 31 { slices.append(nalu); keyframe = keyframe || (16...23).contains(type) }
            } else {
                type = nalu[0] & 0x1f
                isParameter = type == 7 || type == 8
                if (1...5).contains(type) { slices.append(nalu); keyframe = keyframe || type == 5 }
            }
            if isParameter {
                guard nalu.count <= 64 * 1024 else { throw Failure.malformed }
                if parameters[type] != nalu { parameters[type] = nalu; format = nil; changed = true }
            }
        }
        let types: [UInt8] = codec == .hevc ? [32, 33, 34] : [7, 8]
        if format == nil, types.allSatisfy({ parameters[$0] != nil }) {
            // NSData retains stable storage for the C API's array of pointers.
            let storage = types.map { parameters[$0]! as NSData }
            let pointers = storage.map { $0.bytes.assumingMemoryBound(to: UInt8.self) }
            let sizes = storage.map { $0.length }
            let result: OSStatus = withExtendedLifetime(storage) {
                if codec == .hevc {
                    return CMVideoFormatDescriptionCreateFromHEVCParameterSets(allocator: kCFAllocatorDefault,
                        parameterSetCount: 3, parameterSetPointers: pointers, parameterSetSizes: sizes,
                        nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &format)
                }
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault,
                    parameterSetCount: 2, parameterSetPointers: pointers, parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4, formatDescriptionOut: &format)
            }
            guard result == noErr, format != nil else { throw Failure.invalidFormat }
            changed = true
        }
        return Packet(slices: slices, keyframe: keyframe, format: format, formatChanged: changed)
    }
}
