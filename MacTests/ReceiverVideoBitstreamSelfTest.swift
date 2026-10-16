import Foundation
import CoreMedia
import VideoToolbox

@main struct ReceiverVideoBitstreamSelfTest {
    static func main() throws {
        var parser = ReceiverVideoBitstream(codec: .h264)
        let h264 = try receiverTestH264Frame()
        let output = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
        if let output {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try h264.write(to: output.appendingPathComponent("synthetic.h264"))
        }
        let packet = try parser.parse(h264)
        precondition(packet.keyframe && packet.formatChanged && !packet.slices.isEmpty)
        precondition(CMVideoFormatDescriptionGetDimensions(packet.format!).width == 64)
        let repeatPacket = try parser.parse(h264)
        precondition(!repeatPacket.formatChanged)
        let metadata = Data(#"{"cap":123,"snd":124}"#.utf8)
        let prefixed = try parser.parse(metadata + h264)
        precondition(prefixed.metadata == metadata)
        for bad in [Data([0,0,0,1,0x80]), Data([1,2,3]),
                    Data(repeating: 0, count: 65537) + h264,
                    (0..<513).reduce(into: Data()) { d, _ in d.append(contentsOf: [0,0,0,1,0x09]) }] {
            do { _ = try parser.parse(bad); fatalError("malformed bitstream accepted") }
            catch ReceiverVideoBitstream.Failure.malformed { }
        }
        var hevc = ReceiverVideoBitstream(codec: .hevc)
        do { _ = try hevc.parse(Data([0,0,0,1,0x26,0])); fatalError("invalid temporal id") }
        catch ReceiverVideoBitstream.Failure.malformed { }
        if EncoderHardwareCapabilities.hevc {
            let frame = try receiverTestH264Frame(codec: kCMVideoCodecType_HEVC)
            if let output { try frame.write(to: output.appendingPathComponent("synthetic.hevc")) }
            let result = try hevc.parse(frame)
            precondition(result.keyframe && result.formatChanged && !result.slices.isEmpty)
            precondition(CMVideoFormatDescriptionGetDimensions(result.format!).width == 64)
            precondition(CMFormatDescriptionGetMediaSubType(result.format!) == kCMVideoCodecType_HEVC)
        } else { print("SKIP real HEVC: hardware encoder unavailable") }
        print("Bounded H264/HEVC bitstream and real parameter sets PASS")
    }
}
