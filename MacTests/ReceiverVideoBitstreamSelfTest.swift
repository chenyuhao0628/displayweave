import Foundation
import CoreMedia
import VideoToolbox

@main struct ReceiverVideoBitstreamSelfTest {
    static func main() throws {
        var parser = ReceiverVideoBitstream(codec: .h264)
        let h264 = try receiverTestH264Frame()
        let packet = try parser.parse(h264)
        precondition(packet.keyframe && packet.formatChanged && !packet.slices.isEmpty)
        precondition(CMVideoFormatDescriptionGetDimensions(packet.format!).width == 64)
        let repeatPacket = try parser.parse(h264)
        precondition(!repeatPacket.formatChanged)
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
            let result = try hevc.parse(receiverTestH264Frame(codec: kCMVideoCodecType_HEVC))
            precondition(result.keyframe && result.formatChanged && !result.slices.isEmpty)
            precondition(CMVideoFormatDescriptionGetDimensions(result.format!).width == 64)
            precondition(CMFormatDescriptionGetMediaSubType(result.format!) == kCMVideoCodecType_HEVC)
        } else { print("SKIP real HEVC: hardware encoder unavailable") }
        print("Bounded H264/HEVC bitstream and real parameter sets PASS")
    }
}
