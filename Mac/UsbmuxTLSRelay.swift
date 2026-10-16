import Foundation
import Network

/// Network.framework cannot attach TLS after usbmux's plaintext tunnel setup.
/// This session-owned loopback bridge copies only encrypted TLS records into
/// the already-open tunnel. One 64 KiB chunk per direction is in flight.
final class UsbmuxTLSRelay {
    private let tunnel: NWConnection
    private let queue: DispatchQueue
    private var listener: NWListener?
    private var local: NWConnection?
    private var timer: DispatchSourceTimer?
    private var stopped = false
    private var startup: ((Result<UInt16, Error>) -> Void)?
    var onClosed: (() -> Void)?

    init(tunnel: NWConnection, queue: DispatchQueue) { self.tunnel = tunnel; self.queue = queue }

    func start(completion: @escaping (Result<UInt16, Error>) -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !stopped, listener == nil else {
            completion(.failure(TransportSecurityError.failed("USB 加密转发已结束，请重新连接"))); return
        }
        startup = completion
        do {
            let tcp = NWProtocolTCP.Options(); tcp.noDelay = true
            let parameters = NWParameters(tls: nil, tcp: tcp)
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                guard let self, !self.stopped, self.local == nil else { connection.cancel(); return }
                self.local = connection
                self.listener?.cancel(); self.listener = nil
                connection.stateUpdateHandler = { [weak self] state in
                    guard let self, !self.stopped else { return }
                    switch state {
                    case .ready:
                        self.timer?.cancel(); self.timer = nil
                        self.pump(connection, to: self.tunnel)
                        self.pump(self.tunnel, to: connection)
                    case .failed, .waiting, .cancelled: self.stop()
                    default: break
                    }
                }
                connection.start(queue: self.queue)
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, !self.stopped, self.listener === listener else { return }
                switch state {
                case .ready:
                    guard let port = listener?.port?.rawValue else { self.stop(); return }
                    let callback = self.startup; self.startup = nil
                    callback?(.success(port))
                case .failed, .waiting: self.stop()
                default: break
                }
            }
            tunnel.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed, .waiting, .cancelled: self?.stop()
                default: break
                }
            }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            self.timer = timer
            timer.schedule(deadline: .now() + 10)
            timer.setEventHandler { [weak self] in self?.stop() }
            timer.resume()
            listener.start(queue: queue)
        } catch { stop() }
    }

    private func pump(_ source: NWConnection, to destination: NWConnection) {
        guard !stopped else { return }
        source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, ended, error in
            guard let self, !self.stopped else { return }
            guard error == nil, let data, !data.isEmpty else { self.stop(); return }
            destination.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self, !self.stopped else { return }
                if error != nil || ended { self.stop() } else { self.pump(source, to: destination) }
            })
        }
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !stopped else { return }
        stopped = true
        timer?.cancel(); timer = nil
        listener?.cancel(); listener = nil
        local?.stateUpdateHandler = nil; local?.cancel(); local = nil
        tunnel.stateUpdateHandler = nil; tunnel.cancel()
        let callback = startup; startup = nil
        callback?(.failure(TransportSecurityError.failed("USB 加密转发中断，请检查线缆并重新连接")))
        let closed = onClosed; onClosed = nil
        closed?()
    }
}
