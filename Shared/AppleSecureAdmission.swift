import Foundation
import Network

/// Immutable for one dial. Discovery cannot change the pin or enable cleartext
/// after a TLS error. All trust writes remain inside SecurePairingState.
struct SecureClientAdmission {
    let pairing: SecurePairingState
    let receiverID: String
    let receiverName: String
    let fingerprint: String
    let token: Data?
    let localName: String
    let trustRevision: UInt64

    init(pairing: SecurePairingState, receiverID: String, receiverName: String,
         fingerprint: String, token: Data?, localName: String) {
        self.pairing = pairing; self.receiverID = receiverID; self.receiverName = receiverName
        self.fingerprint = fingerprint; self.token = token; self.localName = localName
        trustRevision = pairing.revision
    }
}

/// One TLS handshake plus one pre-application frame exchange. Owned and called
/// on `queue`; the successful caller takes over an already-started connection.
/// Exact reads deliberately leave any coalesced hello/video bytes in Network.
final class AppleSecureAdmission {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let timeout: Double
    private var timer: DispatchSourceTimer?
    private var completion: ((Result<SecurePeerRecord, Error>) -> Void)?
    private var begun = false
    private var tlsReady = false

    init(connection: NWConnection, queue: DispatchQueue, timeout: Double = 10,
         completion: @escaping (Result<SecurePeerRecord, Error>) -> Void) {
        self.connection = connection; self.queue = queue
        self.timeout = timeout.isFinite ? min(10, max(0.05, timeout)) : 10
        self.completion = completion
    }

    func startServer(_ pairing: SecurePairingState) {
        start { [weak self] fingerprint in
            guard let self else { return }
            self.readFrame { [weak self] data in
                guard let self else { return }
                do {
                    let request = try SecureAuthRequest.decode(data)
                    let peer = try pairing.authenticate(request, fingerprint: fingerprint)
                    let ready = try SecureAuthRequest.ready(pairing.localID)
                    self.writeFrame(ready) { [weak self] in
                        guard let self else { return }
                        // A revoke during the acknowledgement must not admit
                        // a socket that is no longer trusted.
                        guard pairing.trustedPeer(peer.installID)?.certificateSHA256 == fingerprint else {
                            self.fail("配对已撤销，请重新配对"); return
                        }
                        self.finish(.success(peer))
                    }
                } catch { self.finish(.failure(error)) }
            }
        }
    }

    func startClient(_ plan: SecureClientAdmission) {
        start { [weak self] fingerprint in
            guard let self else { return }
            guard fingerprint == plan.fingerprint else {
                self.fail("接收端证书不匹配，请检查配对身份"); return
            }
            do {
                let request = SecureAuthRequest(installID: plan.pairing.localID, name: plan.localName,
                                                pairingToken: plan.token)
                self.writeFrame(try request.encoded()) { [weak self] in
                    self?.readFrame { [weak self] data in
                        guard let self else { return }
                        do {
                            guard try SecureAuthRequest.readyIdentity(data) == plan.receiverID else {
                                self.fail("接收端身份不匹配，请选择邀请对应的设备"); return
                            }
                            try plan.pairing.trustConfirmedReceiver(id: plan.receiverID, name: plan.receiverName,
                                fingerprint: fingerprint, explicitInvitation: plan.token != nil,
                                expectedRevision: plan.trustRevision)
                            guard let peer = plan.pairing.trustedPeer(plan.receiverID) else {
                                self.fail("配对已撤销，请重新配对"); return
                            }
                            self.finish(.success(peer))
                        } catch { self.finish(.failure(error)) }
                    }
                }
            } catch { self.finish(.failure(error)) }
        }
    }

    func cancel() { fail("安全连接已取消，请重新连接") }

    private func start(_ ready: @escaping (String) -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !begun, completion != nil else { return }
        begun = true
        let timer = DispatchSource.makeTimerSource(queue: queue)
        self.timer = timer
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { [weak self] in self?.fail("安全连接超时，请检查网络并重新获取配对邀请") }
        timer.resume()
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, self.completion != nil else { return }
            switch state {
            case .ready:
                guard !self.tlsReady else { return }
                self.tlsReady = true
                guard let fingerprint = AppleTLS.peerFingerprint(self.connection) else {
                    self.fail("未取得 TLS 对端身份，请重新配对"); return
                }
                ready(fingerprint)
            case .failed, .waiting:
                self.fail("TLS 连接失败，请检查网络、系统时间和配对身份")
            case .cancelled: self.fail("安全连接已结束，请重新连接")
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func readFrame(_ receive: @escaping (Data) -> Void) {
        readExactly(4) { [weak self] header in
            guard let self else { return }
            let count = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard count > 0, count <= SecurePairingProtocol.maximumAuthBytes else {
                self.fail("认证消息长度无效，请更新对端应用"); return
            }
            self.readExactly(Int(count), receive)
        }
    }

    private func readExactly(_ count: Int, _ receive: @escaping (Data) -> Void) {
        guard completion != nil else { return }
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { [weak self] data, _, ended, error in
            guard let self, self.completion != nil else { return }
            guard error == nil, !ended, let data, data.count == count else {
                self.fail("认证消息中断，请重新连接"); return
            }
            receive(data)
        }
    }

    private func writeFrame(_ data: Data, _ sent: @escaping () -> Void) {
        guard completion != nil, !data.isEmpty, data.count <= SecurePairingProtocol.maximumAuthBytes else { return }
        let n = UInt32(data.count)
        var framed = Data([UInt8(n >> 24), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)])
        framed.append(data)
        connection.send(content: framed, completion: .contentProcessed { [weak self] error in
            guard let self, self.completion != nil else { return }
            if error != nil { self.fail("认证发送失败，请重新连接") } else { sent() }
        })
    }

    private func fail(_ message: String) { finish(.failure(TransportSecurityError.failed(message))) }

    private func finish(_ result: Result<SecurePeerRecord, Error>) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let callback = completion else { return }
        completion = nil
        timer?.cancel(); timer = nil
        connection.stateUpdateHandler = nil
        if case .failure = result { connection.cancel() }
        callback(result)
    }
}

/// Listener-owned admission slots. An unauthenticated socket never reaches the
/// receiver's current connection, decoder, hello or input callbacks.
final class AppleSecureAdmissionPool {
    private let queue: DispatchQueue
    private let timeout: Double
    private var pending: [ObjectIdentifier: AppleSecureAdmission] = [:]
    var pendingCount: Int { dispatchPrecondition(condition: .onQueue(queue)); return pending.count }

    init(queue: DispatchQueue, timeout: Double = 10) { self.queue = queue; self.timeout = timeout }

    func accept(_ connection: NWConnection, pairing: SecurePairingState,
                completion: @escaping (Result<SecurePeerRecord, Error>) -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard pending.count < 2 else {
            connection.cancel()
            completion(.failure(TransportSecurityError.failed("安全连接正在验证，请稍后重试")))
            return
        }
        let key = ObjectIdentifier(connection)
        let admission = AppleSecureAdmission(connection: connection, queue: queue, timeout: timeout) { [weak self] result in
            self?.pending.removeValue(forKey: key)
            completion(result)
        }
        pending[key] = admission
        admission.startServer(pairing)
    }

    func cancelAll() {
        dispatchPrecondition(condition: .onQueue(queue))
        let old = Array(pending.values)
        pending.removeAll()
        old.forEach { $0.cancel() }
    }
}
