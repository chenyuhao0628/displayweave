import Foundation

/// Bounded encoder selection. The low-latency fallback follows upstream
/// peetzweg/opendisplay d9eb302 (GPL-3.0); codec negotiation stays local.
enum EncoderSessionFactory {
    struct Attempt: Equatable {
        let codec: StreamCodec
        let lowLatency: Bool
    }

    struct Selection<Session> {
        let session: Session
        let attempt: Attempt
    }

    struct AttemptFailure {
        let attempt: Attempt
        let message: String
    }

    struct Failure: LocalizedError {
        let attempts: [AttemptFailure]
        var errorDescription: String? {
            let detail = attempts.map {
                "\($0.attempt.codec.label)/lowLatency=\($0.attempt.lowLatency): \($0.message)"
            }.joined(separator: "; ")
            return "视频编码器无法启动（\(detail)）。请降低分辨率或帧率后重新连接，并导出日志。"
        }
    }

    static func make<Session>(preferredCodec: StreamCodec, lowLatency: Bool,
                             create: (Attempt) throws -> Session,
                             onFailure: (Attempt, Error) -> Void = { _, _ in }) throws -> Selection<Session> {
        let codecs: [StreamCodec] = preferredCodec == .hevc ? [.hevc, .h264] : [.h264]
        // Retry the same codec without the low-latency requirement before
        // switching codecs. Explicitly disabled low latency stays disabled.
        let latencyModes = lowLatency ? [true, false] : [false]
        var failures: [AttemptFailure] = []
        for codec in codecs {
            for mode in latencyModes {
                let attempt = Attempt(codec: codec, lowLatency: mode)
                do { return Selection(session: try create(attempt), attempt: attempt) }
                catch {
                    onFailure(attempt, error)
                    failures.append(AttemptFailure(attempt: attempt, message: error.localizedDescription))
                }
            }
        }
        throw Failure(attempts: failures)
    }
}
