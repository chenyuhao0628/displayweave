[English](secure-transport-design.md) | [简体中文](secure-transport-design.zh-CN.md)

# Secure transport and pairing design

F03 implementation design, 2026-10-16. Apple sender/receiver and Android receiver integration is implemented in source. Published p8 is unchanged. Completion and exercised evidence are tracked in [the active ledger](feature-completion.md); see [source usage](secure-transport.md).

## Decision

Use platform TLS, mutual certificate possession and an out-of-band invitation. Apple uses Security / Network.framework; Android uses Android Keystore / JSSE. Retain the inherited TCP port 9000, Bonjour `_opensidecar._tcp`, outer length framing and application messages. A new `security=tls-v1` TXT field describes the encrypted listener. TLS precedes all application framing. No opportunistic STARTTLS or silent cleartext retry is permitted.

Each installation has a separate P-256 transport key and self-signed X.509 certificate. It is unrelated to app signing, Sparkle, APK updates or ADB identities. Apple stores the private key/certificate in app-scoped Keychain items; Android uses Android Keystore. macOS explicitly uses the login Keychain because the ad-hoc preview has no provisioned data-protection access group; iOS uses its application's data-protection Keychain. No storage error enables a file fallback. Pin the full SHA-256 certificate fingerprint. Certificate replacement requires explicit pairing again. The minimal Apple certificate DER builder only encodes the local certificate; Security performs signing and TLS. Platform certificate parsers and cross-language TLS tests validate its output.

## First pairing

1. The receiver explicitly opens a two-minute pairing window and displays a copyable `DW1` invitation containing its installation ID, complete certificate fingerprint and a cryptographically random 256-bit one-use secret. Transfer it through a trusted channel or in person. It is not a short numeric code or plaintext TOFU.
2. The sender imports the bounded invitation and selects the receiver. It pins the server certificate before sending any secret or screen data and presents its own client certificate. Unknown client certificates are provisionally accepted only while pairing is open; no application connection is admitted yet.
3. Inside TLS, the sender sends one bounded `secureAuth` frame with protocol version, sender installation ID and invitation token. The receiver binds the TLS client certificate to that ID only after validating the token and storing trust durably. The token is consumed on success; five failed token attempts close the pairing window.
4. The receiver sends `secureReady` with its installation ID. Only then does the sender persist reciprocal trust and enter the existing hello/video/input protocol. The receiver also withholds hello, decoder state and input until authentication completes. A pending unauthenticated socket never replaces an active authenticated session.

## Reconnect, revocation and compatibility

Paired sessions require the recorded certificate and ID on both sides. A certificate cannot silently change an existing ID or alias another recorded identity. Revocation keeps a bounded tombstone so discovery stripping or a global legacy setting cannot downgrade a previously paired peer. Explicit re-pairing may restore a revoked identity with a new certificate; it does not happen from a network request alone. Closing the pairing window cancels pending unknown-peer admission.

The encrypted listener is the default. A receiver may explicitly select **insecure legacy compatibility**, visibly disabling TLS for that listener so old senders can connect. A new sender must also explicitly permit a legacy target and refuse it if that ID has any pairing history. TLS/authentication errors never trigger that path. Legacy mode retains its trusted-network limitation and cannot enable the new Mac keyboard/mouse forwarding feature.

The same authenticated stream is used over Wi-Fi, Ethernet and Android ADB forwarding. iOS usbmux first establishes its existing device tunnel; a session-owned loopback relay carries encrypted TLS bytes into that tunnel because Network.framework cannot retrofit TLS onto the already negotiated usbmux connection. The relay permits one local client, pumps bounded chunks with send completion backpressure and closes with its session. No capture begins before authenticated hello.

## Resource and failure bounds

- Invitation ≤ 2 KiB; auth/control admission frame ≤ 4 KiB; at most 128 trust records, with bounded IDs/names and validated full fingerprints.
- At most two pending TLS/auth sockets per listener; handshake/admission deadline ten seconds. Existing application frame limits remain unchanged after admission.
- One-use tokens expire using monotonic time. Tokens/private keys are not placed in Bonjour, preferences, logs, benchmark files or Git.
- TLS 1.2+ with forward-secret ECDHE and AEAD; TLS 1.3 where available. Disable early data and session resumption so every connection presents the certificate checked by the current trust/revocation policy.
- Store/identity failures fail closed with an actionable UI message. No replacement key is silently generated when stored identity material is inconsistent or unreadable.
- Pending callbacks carry connection/role generations. Role changes, stop, cancel, backgrounding and revocation cancel admission and release input state.

## Required evidence

Swift and Java policy vectors: invitation bounds, exact pins, wrong ID/token, token expiry/reuse, five-attempt closure, durable trust failure, revocation, downgrade refusal and exhausted stores. Real platform TLS loopback: Swift↔Swift, Swift↔Java, wrong server/client certificate, unauthenticated admission timeout, malformed/auth-before-video rejection, TLS tampering and reconnect with no token. Receiver/sender integration tests must prove no screen/input/application state before admission and no stale connection takeover. Both Apple builds and Android regression gate remain required. Physical network performance and the user-supplied pairing channel are separate boundaries.

## Official API checks

Checked official documentation and installed SDK headers on 2026-10-16: Apple `SecIdentityCreate` (macOS 10.12 / iOS 11.2+), `sec_protocol_options_set_verify_block`, peer authentication and TLS version options; Android SSLSocket and Android Keystore. API references: [Apple identity](https://developer.apple.com/documentation/security/secidentitycreate(_:_:_:)), [Apple TLS verification](https://developer.apple.com/documentation/security/sec_protocol_options_set_verify_block(_:_:_:)), [Android TLS socket](https://developer.android.com/reference/javax/net/ssl/SSLSocket), [Android Keystore](https://developer.android.com/privacy-and-security/keystore).

## Core implementation notes

The shared pre-application messages use strict bounded binary fields, avoiding duplicate JSON-key interpretations: invitation `DWP1` + UInt16 ID length + UTF-8 ID + 32-byte certificate SHA-256 + 32-byte token, encoded as unpadded base64url after `DW1.`; authentication `DWA1` + one token-present flag byte + length-prefixed ID + length-prefixed name + optional 32-byte token; acknowledgement `DWR1` + length-prefixed receiver ID. Lengths use network byte order; unknown flags, invalid UTF-8 and trailing bytes are rejected. Auth/ack travel inside the existing four-byte outer length frame, after TLS. Shared public synthetic golden vectors live in `tools/fixtures/secure-pairing-v1.properties`.

Transport certificates expire 365 days after creation (with one day of not-before clock tolerance). Apple SSL policy rejected a ten-year prototype, so it was not retained. Expiry/key loss requires an explicit identity reset and fresh pairing; no silent pin rotation. This transport identity lifetime is unrelated to application signing certificates.

Core tests use ephemeral identities and temporary test keystores; they never access the application's saved pairing keys. Apple→Apple and both Apple↔Java directions exercised real TLS. Real Keychain tests use a random scope, delete only their own records, and run the iOS part in a disposable simulator with Xcode-generated app signing. Source UI and session integration use the same core; Android Keystore/runtime and hardware evidence are tracked separately.

Android Keystore signing authorizes `DIGEST_NONE` as required by [KeyGenParameterSpec for TLS](https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec.Builder#setDigests(java.lang.String...)); the TLS provider hashes its transcript, then asks Keystore to sign that digest. SHA-256/384 remain authorized for certificate signing. Keys lacking the TLS authorization are rejected with an explicit reset action. A real Keystore-backed TLS fixture first reproduced the failure and gates this path; software-only key tests are insufficient.
