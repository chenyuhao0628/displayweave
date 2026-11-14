import Foundation
import Network
import Security

enum AppleTLS {
    private static let failureLock = NSLock()
    private static var recentPeerFailure: (uptime: TimeInterval, message: String)?

    /// Validates peer X.509 certificate pin, 1-year validity window (`notAfter < now`),
    /// and Security trust possession, returning an actionable Chinese error on failure.
    static func validateWithReason(
        _ trust: SecTrust,
        server: Bool,
        now: Date = Date(),
        acceptedFingerprint: (String) -> Bool
    ) -> Result<Void, TransportSecurityError> {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], chain.count == 1 else {
            return .failure(.failed("对端证书链无效，请在安全设置中重新配对"))
        }
        let cert = chain[0], der = SecCertificateCopyData(cert) as Data
        guard der.count <= 8192, acceptedFingerprint(AppleTransportIdentity.fingerprint(der)) else {
            return .failure(.failed("对端证书指纹不匹配，请在安全设置中撤销旧配对并重新配对"))
        }
        if let validity = AppleTransportIdentity.certificateValidity(der) {
            if validity.notAfter < now {
                return .failure(.failed(AppleTransportIdentity.expiredPeerCertificateMessage))
            }
            if validity.notBefore.addingTimeInterval(-300) > now {
                return .failure(.failed(AppleTransportIdentity.notYetValidPeerCertificateMessage))
            }
        }
        // Pinning replaces CA/hostname discovery, not TLS possession or the
        // platform's key usage/validity checks. Never fetch untrusted AIA URLs.
        guard SecTrustSetPolicies(trust, SecPolicyCreateSSL(server, nil)) == errSecSuccess,
              SecTrustSetAnchorCertificates(trust, [cert] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
              SecTrustSetVerifyDate(trust, now as CFDate) == errSecSuccess else {
            return .failure(.failed("无法初始化 TLS 信任校验，请重试"))
        }
        guard SecTrustEvaluateWithError(trust, nil) else {
            if AppleTransportIdentity.isCertificateExpired(der, at: now) {
                return .failure(.failed(AppleTransportIdentity.expiredPeerCertificateMessage))
            }
            return .failure(.failed("TLS 证书校验未通过，请检查两端系统时间或在安全设置中重置传输身份并重新配对"))
        }
        return .success(())
    }

    /// `server` indicates that the peer is a server (the local endpoint is client).
    static func validate(
        _ trust: SecTrust,
        server: Bool,
        now: Date = Date(),
        acceptedFingerprint: (String) -> Bool
    ) -> Bool {
        if case .success = validateWithReason(trust, server: server, now: now, acceptedFingerprint: acceptedFingerprint) {
            return true
        }
        return false
    }

    static func options(identity: AppleTransportIdentity, peerIsServer: Bool, queue: DispatchQueue,
                        acceptedFingerprint: @escaping (String) -> Bool) throws -> NWProtocolTLS.Options {
        if AppleTransportIdentity.isCertificateExpired(identity.certificateDER) {
            throw TransportSecurityError.failed(AppleTransportIdentity.expiredLocalCertificateMessage)
        }
        let tls = NWProtocolTLS.Options(), options = tls.securityProtocolOptions
        guard let local = sec_identity_create(identity.identity) else {
            throw TransportSecurityError.failed("无法加载 TLS 身份")
        }
        sec_protocol_options_set_local_identity(options, local)
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv13)
        sec_protocol_options_append_tls_ciphersuite(options, .AES_128_GCM_SHA256)
        sec_protocol_options_append_tls_ciphersuite(options, .AES_256_GCM_SHA384)
        sec_protocol_options_append_tls_ciphersuite(options, .CHACHA20_POLY1305_SHA256)
        sec_protocol_options_append_tls_ciphersuite(options, .ECDHE_ECDSA_WITH_AES_128_GCM_SHA256)
        sec_protocol_options_append_tls_ciphersuite(options, .ECDHE_ECDSA_WITH_AES_256_GCM_SHA384)
        sec_protocol_options_set_peer_authentication_required(options, true)
        sec_protocol_options_set_tls_tickets_enabled(options, false)
        sec_protocol_options_set_tls_resumption_enabled(options, false)
        // Disabling tickets/resumption also prevents TLS 1.3 zero-RTT.
        sec_protocol_options_set_verify_block(options, { _, peerTrust, complete in
            let trust = sec_trust_copy_ref(peerTrust).takeRetainedValue()
            switch validateWithReason(trust, server: peerIsServer, acceptedFingerprint: acceptedFingerprint) {
            case .success:
                complete(true)
            case .failure(let reason):
                if case .failed(let detail) = reason,
                   (detail == AppleTransportIdentity.expiredPeerCertificateMessage
                    || detail == AppleTransportIdentity.notYetValidPeerCertificateMessage) {
                    recordRecentPeerFailure(detail)
                }
                complete(false)
            }
        }, queue)
        return tls
    }

    static func consumeRecentPeerFailureMessage() -> String? {
        failureLock.lock()
        defer { failureLock.unlock() }
        guard let entry = recentPeerFailure else { return nil }
        recentPeerFailure = nil
        guard ProcessInfo.processInfo.systemUptime - entry.uptime <= 5.0 else { return nil }
        return entry.message
    }

    static func handshakeFailureMessage(for error: NWError) -> String {
        if case .tls(let status) = error {
            if status == errSSLCertExpired {
                return AppleTransportIdentity.expiredPeerCertificateMessage
            }
            if status == errSSLCertNotYetValid {
                return AppleTransportIdentity.notYetValidPeerCertificateMessage
            }
        }
        return "TLS 连接失败（\(error)），请检查网络、系统时间和配对身份；若证书满 1 年已过期，请在两端“安全与配对”中重置传输身份并重新配对"
    }

    private static func recordRecentPeerFailure(_ message: String) {
        failureLock.lock()
        recentPeerFailure = (ProcessInfo.processInfo.systemUptime, message)
        failureLock.unlock()
    }

    static func peerFingerprint(_ connection: NWConnection) -> String? {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else { return nil }
        var certificates: [Data] = []
        let accessed = sec_protocol_metadata_access_peer_certificate_chain(metadata.securityProtocolMetadata) { cert in
            guard certificates.count < 2 else { return }
            let value = sec_certificate_copy_ref(cert).takeRetainedValue()
            certificates.append(SecCertificateCopyData(value) as Data)
        }
        guard accessed, certificates.count == 1, certificates[0].count <= 8192 else { return nil }
        return AppleTransportIdentity.fingerprint(certificates[0])
    }
}
