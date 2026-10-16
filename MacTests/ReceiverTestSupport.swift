import Foundation
import Darwin
import AVFoundation
import VideoToolbox

struct ReceiverTestFailure: Error { let message: String }

final class ReceiverTestPeer: @unchecked Sendable {
    let fd: Int32
    init(port: UInt16) throws {
        fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ReceiverTestFailure(message: "socket") }
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0 else { close(fd); throw ReceiverTestFailure(message: "connect errno=\(errno)") }
    }
    deinit { close(fd) }
    func write(_ data: Data) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let n = Darwin.send(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                guard n > 0 else { throw ReceiverTestFailure(message: "send errno=\(errno)") }
                offset += n
            }
        }
    }
    func read(_ count: Int) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < count {
                let n = recv(fd, bytes.baseAddress!.advanced(by: offset), count - offset, 0)
                guard n > 0 else { throw ReceiverTestFailure(message: "read EOF/errno=\(errno)") }
                offset += n
            }
        }
        return data
    }
    func hello() throws -> [String: Any] {
        let header = try read(4)
        let size = header.withUnsafeBytes { Int(UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))) }
        guard size < 32768 else { throw ReceiverTestFailure(message: "hello too large") }
        return try JSONSerialization.jsonObject(with: read(size)) as! [String: Any]
    }
    func isClosed() -> Bool {
        // Controls already in flight (ping / codecFailure) may precede EOF.
        var bytes = [UInt8](repeating: 0, count: 4096)
        for _ in 0..<16 {
            let n = recv(fd, &bytes, bytes.count, 0)
            if n <= 0 { return n == 0 || errno == ECONNRESET }
        }
        return false
    }
}

private final class EncodedSample {
    var data: Data?
    func accept(_ sample: CMSampleBuffer) {
        guard let format = CMSampleBufferGetFormatDescription(sample),
              let block = CMSampleBufferGetDataBuffer(sample) else { return }
        var result = Data()
        let hevc = CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_HEVC
        for i in 0..<(hevc ? 3 : 2) {
            var pointer: UnsafePointer<UInt8>?
            var size = 0
            let status = hevc
                ? CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, parameterSetIndex: i,
                    parameterSetPointerOut: &pointer, parameterSetSizeOut: &size,
                    parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                : CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: i,
                    parameterSetPointerOut: &pointer, parameterSetSizeOut: &size,
                    parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
            guard status == noErr, let pointer else { return }
            result.append(contentsOf: [0,0,0,1]); result.append(pointer, count: size)
        }
        let length = CMBlockBufferGetDataLength(block)
        var avcc = Data(count: length)
        _ = avcc.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
        var offset = 0
        while offset + 4 <= length {
            let count = avcc[offset..<(offset+4)].withUnsafeBytes { Int(UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))) }
            offset += 4
            guard count > 0, offset + count <= length else { return }
            result.append(contentsOf: [0,0,0,1]); result.append(avcc[offset..<(offset+count)])
            offset += count
        }
        data = result
    }
}

func receiverTestH264Frame(codec: CMVideoCodecType = kCMVideoCodecType_H264) throws -> Data {
    let box = EncodedSample()
    var session: VTCompressionSession?
    let status = VTCompressionSessionCreate(allocator: kCFAllocatorDefault, width: 64, height: 64,
        codecType: codec, encoderSpecification: nil, imageBufferAttributes: nil,
        compressedDataAllocator: nil, outputCallback: { context, _, status, _, sample in
            if status == noErr, let context, let sample {
                Unmanaged<EncodedSample>.fromOpaque(context).takeUnretainedValue().accept(sample)
            }
        }, refcon: Unmanaged.passUnretained(box).toOpaque(), compressionSessionOut: &session)
    guard status == noErr, let session else { throw ReceiverTestFailure(message: "H264 encoder unavailable: \(status)") }
    defer { VTCompressionSessionInvalidate(session) }
    VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
    VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
    var pixel: CVPixelBuffer?
    guard CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &pixel) == kCVReturnSuccess,
          let pixel else { throw ReceiverTestFailure(message: "pixel buffer") }
    CVPixelBufferLockBaseAddress(pixel, [])
    let base = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(pixel)
    for y in 0..<64 { for x in 0..<64 {
        let colors: [[UInt8]] = [[30, 40, 240, 255], [50, 210, 40, 255], [230, 70, 40, 255], [50, 220, 240, 255]]
        let color = colors[(y / 32) * 2 + x / 32]
        for c in 0..<4 { base[y * stride + x * 4 + c] = color[c] }
    } }
    CVPixelBufferUnlockBaseAddress(pixel, [])
    guard VTCompressionSessionEncodeFrame(session, imageBuffer: pixel, presentationTimeStamp: .zero,
        duration: CMTime(value: 1, timescale: 60), frameProperties: [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary,
        sourceFrameRefcon: nil, infoFlagsOut: nil) == noErr else { throw ReceiverTestFailure(message: "encode") }
    VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
    guard let data = box.data else { throw ReceiverTestFailure(message: "no encoded frame") }
    return data
}
