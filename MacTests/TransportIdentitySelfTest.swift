import Foundation
import Security
import CryptoKit

@main enum TransportIdentitySelfTest {
    static func main() throws {
        let first = try AppleTransportIdentity.ephemeral()
        let second = try AppleTransportIdentity.ephemeral()
        precondition(first.fingerprint.count == 64 && first.fingerprint != second.fingerprint)
        precondition(SecCertificateCreateWithData(nil, first.certificateDER as CFData) != nil)
        var cert: SecCertificate?
        precondition(SecIdentityCopyCertificate(first.identity, &cert) == errSecSuccess)
        precondition((SecCertificateCopyData(cert!) as Data) == first.certificateDER)
        var privateKey: SecKey?
        precondition(SecIdentityCopyPrivateKey(first.identity, &privateKey) == errSecSuccess)
        let publicKey = SecCertificateCopyKey(cert!)!
        let challenge = Data("DisplayWeave TLS possession test".utf8)
        let signature = SecKeyCreateSignature(privateKey!, .ecdsaSignatureMessageX962SHA256,
                                              challenge as CFData, nil)!
        precondition(SecKeyVerifySignature(publicKey, .ecdsaSignatureMessageX962SHA256,
                                            challenge as CFData, signature, nil))
        var trust: SecTrust?
        precondition(SecTrustCreateWithCertificates(cert!, SecPolicyCreateSSL(true, nil), &trust) == errSecSuccess)
        SecTrustSetAnchorCertificates(trust!, [cert!] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust!, true)
        SecTrustSetNetworkFetchAllowed(trust!, false)
        var evaluationError: CFError?
        if !SecTrustEvaluateWithError(trust!, &evaluationError) {
            FileHandle.standardError.write(Data("Local certificate evaluation: \(String(describing: evaluationError))\n".utf8))
        }
        if CommandLine.arguments.count == 2 {
            try first.certificateDER.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        precondition(AppleTLS.validate(trust!, server: true, acceptedFingerprint: { $0 == first.fingerprint }))
        precondition(!AppleTLS.validate(trust!, server: true, acceptedFingerprint: { $0 == second.fingerprint }))
        precondition(!AppleTLS.validate(trust!, server: true, acceptedFingerprint: { _ in false }))
        print("Transport identity: parsed self-signed certificate, matching key, full pin and trust rejection PASS")
    }
}
