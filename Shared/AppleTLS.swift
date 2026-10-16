import Foundation
import Network
import Security

enum AppleTLS {
    /// `server` indicates that the peer is a server (the local endpoint is client).
    static func validate(_ trust: SecTrust, server: Bool,
                         acceptedFingerprint: (String) -> Bool) -> Bool {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], chain.count == 1 else { return false }
        let cert = chain[0], der = SecCertificateCopyData(cert) as Data
        guard der.count <= 8192, acceptedFingerprint(AppleTransportIdentity.fingerprint(der)) else { return false }
        // Pinning replaces CA/hostname discovery, not TLS possession or the
        // platform's key usage/validity checks. Never fetch untrusted AIA URLs.
        guard SecTrustSetPolicies(trust, SecPolicyCreateSSL(server, nil)) == errSecSuccess,
              SecTrustSetAnchorCertificates(trust, [cert] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess else { return false }
        return SecTrustEvaluateWithError(trust, nil)
    }

    static func options(identity: AppleTransportIdentity, peerIsServer: Bool, queue: DispatchQueue,
                        acceptedFingerprint: @escaping (String) -> Bool) throws -> NWProtocolTLS.Options {
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
            complete(validate(trust, server: peerIsServer, acceptedFingerprint: acceptedFingerprint))
        }, queue)
        return tls
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
