import Foundation

private enum EncoderRefusal: Error { case unsupported, prepareFailed }

@main struct EncoderSessionFactorySelfTest {
    @MainActor static func main() async throws {
        typealias Attempt = EncoderSessionFactory.Attempt
        var calls: [Attempt] = []
        var failures = 0
        let fallback = try EncoderSessionFactory.make(preferredCodec: .h264, lowLatency: true, create: {
            calls.append($0)
            if $0.lowLatency { throw EncoderRefusal.unsupported }
            return 17
        }, onFailure: { _, _ in failures += 1 })
        precondition(fallback.session == 17 && !fallback.attempt.lowLatency)
        precondition(calls == [Attempt(codec: .h264, lowLatency: true), Attempt(codec: .h264, lowLatency: false)])
        precondition(failures == 1, "unsupported low-latency mode must retry ordinary H.264")

        calls = []
        let direct = try EncoderSessionFactory.make(preferredCodec: .h264, lowLatency: true) {
            calls.append($0); return 1
        }
        precondition(calls.count == 1 && direct.attempt.lowLatency, "working low-latency mode must stay enabled")

        calls = []
        let hevc = try EncoderSessionFactory.make(preferredCodec: .hevc, lowLatency: true) {
            calls.append($0)
            if $0.lowLatency { throw EncoderRefusal.prepareFailed }
            return 2
        }
        precondition(hevc.attempt == Attempt(codec: .hevc, lowLatency: false) && calls.count == 2,
            "ordinary HEVC must be tried before changing codecs, including preparation failures")

        calls = []
        let h264 = try EncoderSessionFactory.make(preferredCodec: .hevc, lowLatency: true) {
            calls.append($0)
            if $0.codec == .hevc || $0.lowLatency { throw EncoderRefusal.unsupported }
            return 3
        }
        precondition(h264.attempt == Attempt(codec: .h264, lowLatency: false) && calls.count == 4)

        calls = []
        _ = try EncoderSessionFactory.make(preferredCodec: .hevc, lowLatency: false) {
            calls.append($0)
            if $0.codec == .hevc { throw EncoderRefusal.unsupported }
            return 4
        }
        precondition(calls == [Attempt(codec: .hevc, lowLatency: false), Attempt(codec: .h264, lowLatency: false)],
            "explicitly disabled low-latency mode must remain disabled")

        // Exercise the same throwing boundary used before capture startup:
        // failure must release the owned pipeline and never reach capture/config success.
        calls = []
        var captureStarted = false, stops = 0, reported = false
        let lifetime = SessionLifetime(start: {
            let _: EncoderSessionFactory.Selection<Int> = try EncoderSessionFactory.make(
                preferredCodec: .hevc, lowLatency: true) {
                    calls.append($0); throw EncoderRefusal.unsupported
                }
            captureStarted = true
        }, stop: { stops += 1; return Task {} }) { error in
            guard let error = error as? EncoderSessionFactory.Failure else { preconditionFailure("lost encoder failure") }
            precondition(error.attempts.count == 4 && error.localizedDescription.contains("重新连接"))
            precondition(stops == 1 && !captureStarted)
            reported = true
        }
        lifetime.start()
        for _ in 0..<200 where !reported { await Task.yield() }
        precondition(reported && calls.count == 4 && !captureStarted)
        await lifetime.stop().value
        precondition(stops == 1)
        print("Encoder creation: ordinary-mode fallback, codec order, bounded attempts, preferences and startup cleanup PASS")
    }
}
