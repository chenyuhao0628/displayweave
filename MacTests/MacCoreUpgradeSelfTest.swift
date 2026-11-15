import CoreAudio
import CoreMedia
import dnssd
import Foundation
import Network
import VideoToolbox

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError("MacCoreUpgradeSelfTest failed: \(message)")
    }
}

@main
struct MacCoreUpgradeSelfTest {
    static func main() throws {
        testNetworkDiagnosticsPolicies()
        try testAudioCapturePacketizer()
        testAudioPCMRingBufferAndPlayer()
        testCursorEchoUDPAndFallback()
        try testVideoToolboxVBVAndDisplayP3()
        print("MacCoreUpgradeSelfTest PASS")
    }

    private static func testNetworkDiagnosticsPolicies() {
        let lanIPv4 = NWEndpoint.hostPort(host: .ipv4(IPv4Address("192.168.1.42")!), port: 9000)
        let loopbackIPv4 = NWEndpoint.hostPort(host: .ipv4(.loopback), port: 9000)
        let loopbackIPv6 = NWEndpoint.hostPort(host: .ipv6(.loopback), port: 9000)
        let localhostName = NWEndpoint.hostPort(host: .name("localhost", nil), port: 9000)
        let bonjourService = NWEndpoint.service(name: "DisplayWeave Mac", type: "_opensidecar._tcp", domain: "local.", interface: nil)

        expect(LANProxyBypassPolicy.shouldBypassProxies(for: lanIPv4),
               "LAN IPv4 endpoint must bypass system HTTP/SOCKS proxies")
        expect(LANProxyBypassPolicy.shouldBypassProxies(for: bonjourService),
               "Bonjour service endpoint must bypass system HTTP/SOCKS proxies")
        expect(!LANProxyBypassPolicy.shouldBypassProxies(for: loopbackIPv4),
               "127.0.0.1 ADB/usbmux tunnel must not set LAN proxy bypass")
        expect(!LANProxyBypassPolicy.shouldBypassProxies(for: loopbackIPv6),
               "::1 loopback must not set LAN proxy bypass")
        expect(!LANProxyBypassPolicy.shouldBypassProxies(for: localhostName),
               "localhost loopback must not set LAN proxy bypass")

        let policyDenied = NWError.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))
        expect(LocalNetworkDiscoveryPolicy.isPolicyDenied(policyDenied),
               "kDNSServiceErr_PolicyDenied must be recognized")
        expect(LocalNetworkDiscoveryPolicy.recoveryStatus(for: policyDenied)
            == "请在“系统设置 > 隐私与安全性 > 本地网络”中允许 DisplayWeave，然后重试",
               "policy denied must surface exact actionable Chinese guidance")
        expect(LocalNetworkDiscoveryPolicy.retryDelaySeconds(attempt: 0) == 1.0
            && LocalNetworkDiscoveryPolicy.retryDelaySeconds(attempt: 3) == 8.0
            && LocalNetworkDiscoveryPolicy.retryDelaySeconds(attempt: 99) == 15.0,
               "browser retry backoff must remain bounded at <= 15s")

        expect(WiFiAWDLAdvisoryPolicy.advisory(wifiStreamingActive: true, discoverableMode: "Everyone") != nil,
               "active Wi-Fi session with AirDrop=Everyone must emit non-blocking advisory")
        expect(WiFiAWDLAdvisoryPolicy.advisory(wifiStreamingActive: false, discoverableMode: "Everyone") == nil,
               "inactive Wi-Fi session must not show AWDL advisory")
        expect(WiFiAWDLAdvisoryPolicy.advisory(wifiStreamingActive: true, discoverableMode: "Contacts Only") == nil,
               "Contacts Only AirDrop must not show AWDL advisory")

        expect(UDPMediaActivationPolicy.shouldActivateUDPMedia(peerSupportsUDP: true, pinnedInterfaceName: nil, forceOnDirectCable: false),
               "Wi-Fi / unpinned LAN activates udpMediaV1 when peer advertises it")
        expect(!UDPMediaActivationPolicy.shouldActivateUDPMedia(peerSupportsUDP: true, pinnedInterfaceName: "en5", forceOnDirectCable: false),
               "pinned DirectCable link stays on kernel TCP by default")
        expect(UDPMediaActivationPolicy.shouldActivateUDPMedia(peerSupportsUDP: true, pinnedInterfaceName: "en5", forceOnDirectCable: true),
               "explicit DirectCable override allows UDP media while retaining interface binding")
    }

    private static func testAudioCapturePacketizer() throws {
        var packetizer = AudioCapturePacketizer()
        let left240 = (0..<240).map { Float(sin(Double($0) * 0.1)) * 0.5 }
        let right240 = (0..<240).map { Float(cos(Double($0) * 0.1)) * 0.5 }
        let chunks = packetizer.ingestFloat32Planar(left: left240, right: right240, sampleRate: 48_000)
        expect(chunks.count == 1 && chunks[0].count == 960,
               "240 stereo frames @ 48 kHz must yield exactly one 960-byte S16LE chunk")

        // Verify CMSampleBuffer non-interleaved Float32 48 kHz extraction
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var formatDesc: CMAudioFormatDescription?
        let fmtStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )
        expect(fmtStatus == noErr && formatDesc != nil, "CMAudioFormatDescriptionCreate succeeded")

        let frameCount = 480 // 10 ms = two 5 ms chunks
        var interleavedFloats = [Float](repeating: 0, count: frameCount * 2)
        for i in 0..<frameCount {
            interleavedFloats[i * 2] = 0.25
            interleavedFloats[i * 2 + 1] = -0.25
        }
        let byteLength = interleavedFloats.count * MemoryLayout<Float>.size
        var blockBuffer: CMBlockBuffer?
        expect(CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteLength,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteLength,
            flags: 0,
            blockBufferOut: &blockBuffer
        ) == noErr, "CMBlockBufferCreate succeeded")
        interleavedFloats.withUnsafeBytes { raw in
            _ = CMBlockBufferReplaceDataBytes(
                with: raw.baseAddress!,
                blockBuffer: blockBuffer!,
                offsetIntoDestination: 0,
                dataLength: byteLength
            )
        }
        var sampleBuffer: CMSampleBuffer?
        expect(CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer!,
            formatDescription: formatDesc!,
            sampleCount: frameCount,
            presentationTimeStamp: CMTime(value: 0, timescale: 48_000),
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr && sampleBuffer != nil, "CMAudioSampleBufferCreateReady succeeded")

        let sbChunks = packetizer.ingest(sampleBuffer!)
        expect(sbChunks.count == 2 && sbChunks[0].count == 960 && sbChunks[1].count == 960,
               "10 ms CMSampleBuffer must packetize into two 960-byte chunks")

        // Verify 100 ms bounded buffer cap
        let huge = Data(repeating: 0x01, count: AudioCapturePacketizer.maxBufferedBytes * 3)
        let cappedChunks = packetizer.ingestInterleavedS16LE(huge)
        expect(cappedChunks.count <= AudioCapturePacketizer.maxBufferedFrames / AudioCapturePacketizer.framesPerChunk,
               "packetizer must bound buffered audio at <= 100 ms")
    }

    private static func testAudioPCMRingBufferAndPlayer() {
        let player = MacAudioPlayer(capacityFrames: 2_880, disableHardwareOutput: true)
        var chunk = Data(capacity: 960)
        for _ in 0..<240 {
            var l = Int16(16384).littleEndian
            var r = Int16(-16384).littleEndian
            withUnsafeBytes(of: &l) { chunk.append(contentsOf: $0) }
            withUnsafeBytes(of: &r) { chunk.append(contentsOf: $0) }
        }
        // Enqueue 15 chunks (3,600 frames > 2,880 capacity) -> bounded at 2,880 frames (60 ms)
        for _ in 0..<15 {
            player.enqueueS16LE(chunk)
        }
        expect(player.ringBuffer.availableFrames == 2_880,
               "ring buffer must cap queued audio at 60 ms (2,880 frames)")
        expect(player.ringBuffer.droppedFrames == 720,
               "ring buffer must drop oldest overflow frames cleanly")

        var outLeft = [Float](repeating: -1, count: 240)
        var outRight = [Float](repeating: -1, count: 240)
        let readCount = outLeft.withUnsafeMutableBufferPointer { lBuf in
            outRight.withUnsafeMutableBufferPointer { rBuf in
                player.ringBuffer.render(intoLeft: lBuf.baseAddress!, right: rBuf.baseAddress!, frameCount: 240)
            }
        }
        expect(readCount == 240 && abs(outLeft[0] - 0.5) < 0.01 && abs(outRight[0] + 0.5) < 0.01,
               "ring buffer must decode S16LE stereo samples accurately")

        player.isMuted = true
        expect(player.ringBuffer.availableFrames == 0, "muting flushes queued audio immediately")
        player.enqueueS16LE(chunk)
        expect(player.ringBuffer.availableFrames == 0, "muted player rejects incoming audio")
        player.stop()
    }

    private static func testCursorEchoUDPAndFallback() {
        let echo = CursorEcho()
        let lock = NSLock()
        var currentPos = CursorPosition(x: 0.25, y: 0.75, visible: true)
        var useUDP = true
        var udpSeqs: [UInt64] = []
        var tcpSeqs: [UInt64] = []
        let udpArrived = DispatchSemaphore(value: 0)
        let tcpArrived = DispatchSemaphore(value: 0)

        echo.start(
            sample: {
                lock.lock()
                defer { lock.unlock() }
                return currentPos
            },
            write: { framed, complete in
                if framed.count > 4,
                   let obj = try? JSONSerialization.jsonObject(with: framed.dropFirst(4)) as? [String: Any],
                   let seq = (obj["s"] as? NSNumber)?.uint64Value {
                    lock.lock()
                    tcpSeqs.append(seq)
                    lock.unlock()
                    tcpArrived.signal()
                }
                complete(true)
            },
            udpSend: { _, seq in
                lock.lock()
                let allow = useUDP
                if allow { udpSeqs.append(seq) }
                lock.unlock()
                if allow { udpArrived.signal() }
                return allow
            }
        )

        expect(udpArrived.wait(timeout: .now() + 1.0) == .success,
               "CursorEcho must emit over UDP fast path when udpSend returns true")
        lock.lock()
        useUDP = false
        currentPos = CursorPosition(x: 0.6, y: 0.4, visible: true)
        lock.unlock()

        expect(tcpArrived.wait(timeout: .now() + 1.0) == .success,
               "CursorEcho must fall back seamlessly to framed TCP when udpSend returns false")
        echo.stop()

        lock.lock()
        let firstUDP = udpSeqs.first ?? 0
        let firstTCP = tcpSeqs.first ?? 0
        lock.unlock()
        expect(firstUDP >= 1 && firstTCP > firstUDP,
               "cursor sequence must remain strictly monotonic across UDP->TCP fallback")
    }

    private static func testVideoToolboxVBVAndDisplayP3() throws {
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: 1920,
            height: 1080,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        guard status == noErr, let session else {
            print("SKIP VideoToolbox VBV/P3 test: HEVC compression session unavailable (\(status))")
            return
        }
        defer { VTCompressionSessionInvalidate(session) }

        let limits = StreamEncodingPolicy.dataRateLimits(bitrate: 40_000_000, fps: 60) as CFArray
        let vbvStatus = VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_DataRateLimits,
            value: limits
        )
        expect(vbvStatus == noErr, "VideoToolbox must accept StreamEncodingPolicy.dataRateLimits CFArray (\(vbvStatus))")

        expect(VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_ColorPrimaries,
            value: kCMFormatDescriptionColorPrimaries_P3_D65
        ) == noErr, "VideoToolbox must accept Display P3 color primaries")
        expect(VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_TransferFunction,
            value: kCMFormatDescriptionTransferFunction_sRGB
        ) == noErr, "VideoToolbox must accept sRGB transfer function for Display P3")
        expect(VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_YCbCrMatrix,
            value: kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2
        ) == noErr, "VideoToolbox must accept Rec.709 YCbCr matrix for Display P3")
    }
}
