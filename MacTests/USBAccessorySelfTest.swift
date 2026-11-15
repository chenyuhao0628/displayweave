import Foundation
import Network

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError("USBAccessorySelfTest failed: \(message)") }
}

private final class LoopbackAccessoryPipe: @unchecked Sendable {
    let listener: NWListener
    private let queue: DispatchQueue
    var onAccepted: ((NWConnection) -> Void)?

    init(queue: DispatchQueue) throws {
        self.queue = queue
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)
        self.listener = try NWListener(using: params, on: .any)
    }

    func start() throws -> UInt16 {
        let ready = DispatchSemaphore(value: 0)
        var boundPort: UInt16?
        var startupError: Error?
        listener.newConnectionHandler = { [weak self] conn in
            self?.onAccepted?(conn)
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                boundPort = self?.listener.port?.rawValue
                ready.signal()
            case .failed(let err):
                startupError = err
                ready.signal()
            default:
                break
            }
        }
        listener.start(queue: queue)
        expect(ready.wait(timeout: .now() + 5) == .success, "loopback accessory pipe listener timed out")
        if let startupError { throw startupError }
        guard let boundPort else { fatalError("missing loopback port") }
        return boundPort
    }

    func stop() {
        listener.cancel()
    }
}

@main
struct USBAccessorySelfTest {
    static func main() throws {
        testAndroidUSBFunctionFiltering()
        testAOAIdentityAndUDIDParsing()
        testProtocolAnswerAndBusyRecoveryMessages()
        testZeroLengthPacketFraming()
        testDeterministicAdbVsAoaArbitration()
        try testMutualTLSRelayOverSimulatedAccessoryStream()
        print("USBAccessorySelfTest PASS")
    }

    private static func testAndroidUSBFunctionFiltering() {
        // Valid Android interfaces
        expect(AndroidUSBFunction(interfaceClass: 0xFF, subclass: 0x42, protocol: 0x01, name: nil) == .adb,
               "0xFF/0x42/0x01 should classify as Android ADB")
        expect(AndroidUSBFunction(interfaceClass: 0xFF, subclass: 0x42, protocol: 0x01, name: "ADB Interface") == .adb,
               "named 0xFF/0x42/0x01 should classify as Android ADB")
        expect(AndroidUSBFunction(interfaceClass: 0x06, subclass: 0x01, protocol: 0x01, name: "MTP") == .mtp,
               "standard Still Image interface named MTP should classify as Android MTP")
        expect(AndroidUSBFunction(interfaceClass: 0xFF, subclass: 0xFF, protocol: 0x00, name: "MTP") == .mtp,
               "vendor 0xFF/0xFF/0x00 interface named MTP should classify as Android MTP")
        expect(AndroidUSBFunction(interfaceClass: 0xFF, subclass: 0xFF, protocol: 0x00, name: "Samsung mtp gadget") == .mtp,
               "case-insensitive MTP substring should classify as Android MTP")

        // Non-Android devices that MUST NOT be probed with AOA GET_PROTOCOL (bcf8e2b lesson)
        expect(AndroidUSBFunction(interfaceClass: 0x02, subclass: 0x0D, protocol: 0x00, name: "AX88179A") == nil,
               "ASIX AX88179A CDC-NCM USB-C dock Ethernet must never match")
        expect(AndroidUSBFunction(interfaceClass: 0xFF, subclass: 0xFF, protocol: 0x00, name: nil) == nil,
               "unnamed vendor 0xFF/0xFF/0x00 dock interface must never match")
        expect(AndroidUSBFunction(interfaceClass: 0xFF, subclass: 0xFF, protocol: 0x00, name: "AX88179A") == nil,
               "vendor dock interface must never match")
        expect(AndroidUSBFunction(interfaceClass: 0xFF, subclass: 0xFF, protocol: 0x00, name: "Android Accessory Interface") == nil,
               "already-switched AOA accessory interface must not re-match as composite probe target")
        expect(AndroidUSBFunction(interfaceClass: 0x06, subclass: 0x01, protocol: 0x01, name: nil) == nil,
               "unnamed Still Image camera must not match")
        expect(AndroidUSBFunction(interfaceClass: 0x06, subclass: 0x01, protocol: 0x01, name: "PTP") == nil,
               "PTP camera must not match")
        expect(AndroidUSBFunction(interfaceClass: 0x01, subclass: 0x03, protocol: 0x00, name: "MIDI") == nil,
               "USB MIDI interface must not match")
    }

    private static func testAOAIdentityAndUDIDParsing() {
        expect(AOA.manufacturer == "OpenDisplay", "AOA manufacturer must remain OpenDisplay for accessory_filter.xml compatibility")
        expect(AOA.model == "OpenDisplay Receiver", "AOA model must remain OpenDisplay Receiver for accessory_filter.xml compatibility")
        expect(AOA.identity[0] == (0, "OpenDisplay") && AOA.identity[1] == (1, "OpenDisplay Receiver"),
               "AOA identity indices 0 and 1 must match manufacturer and model")
        let uri: String = AOA.identity.first(where: { $0.0 == 4 })?.1 ?? ""
        expect(uri.hasPrefix("https://github.com/chenyuhao0628/displayweave"),
               "AOA URI must point to GitHub Releases and never reintroduce external hosts")

        expect(AOA.isUDID("aoa:R58M123456"), "aoa: prefix should be recognized")
        expect(!AOA.isUDID("00008110-00123456"), "usbmux UDID must not match aoa: prefix")
        expect(!AOA.isUDID(nil), "nil UDID must not match")
        expect(AOA.serial(from: "aoa:R58M123456") == "R58M123456", "serial should strip aoa: prefix")
        expect(AOA.serial(from: "aoa:") == nil, "empty aoa: serial must return nil")
        expect(AOA.serial(from: "00008110-00123456") == nil, "non-aoa UDID must return nil")
    }

    private static func testProtocolAnswerAndBusyRecoveryMessages() {
        let signedBusy = NSError(domain: "IOUSBHostErrorDomain", code: Int(Int32(bitPattern: 0xE000_02C5)))
        let unsignedBusy = NSError(domain: "IOUSBHostErrorDomain", code: Int(0xE000_02C5))
        expect(AOA.ProtocolAnswer(probeError: signedBusy) == .busy,
               "sign-extended kIOReturnExclusiveAccess (0xE00002C5) must map to .busy")
        expect(AOA.ProtocolAnswer(probeError: unsignedBusy) == .busy,
               "unsigned kIOReturnExclusiveAccess (0xE00002C5) must map to .busy")

        let signedStall = NSError(domain: "IOUSBHostErrorDomain", code: Int(Int32(bitPattern: 0xE000_5000)))
        let unsignedStall = NSError(domain: "IOUSBHostErrorDomain", code: Int(0xE000_5000))
        expect(AOA.ProtocolAnswer(probeError: signedStall) == .refused,
               "sign-extended kUSBHostReturnPipeStalled (0xE0005000) must map to .refused")
        expect(AOA.ProtocolAnswer(probeError: unsignedStall) == .refused,
               "unsigned kUSBHostReturnPipeStalled (0xE0005000) must map to .refused")

        let aborted = NSError(domain: "IOUSBHostErrorDomain", code: Int(Int32(bitPattern: 0xE000_02EB)))
        let noDevice = NSError(domain: "IOUSBHostErrorDomain", code: Int(Int32(bitPattern: 0xE000_02C0)))
        expect(AOA.ProtocolAnswer(probeError: aborted) == .silent, "aborted control request must map to .silent")
        expect(AOA.ProtocolAnswer(probeError: noDevice) == .silent, "detached device must map to .silent")

        let busyText = AOA.Failure.busy.localizedDescription
        expect(busyText.contains("0xE00002C5")
               && busyText.contains("adb kill-server")
               && busyText.contains("USB 调试"),
               "AOA.Failure.busy must explain 0xE00002C5, USB debugging authorization, and adb kill-server")

        let policyBusyText = AndroidWiredArbitrationPolicy.recoveryMessage(
            serial: "R58M1234567890", name: "Pixel 8", adbState: nil)
        expect(policyBusyText.contains("0xE00002C5") && policyBusyText.contains("adb kill-server"),
               "arbitration busy recovery message must guide user to allow USB debugging or run adb kill-server")
    }

    private static func testZeroLengthPacketFraming() {
        expect(AOA.bulkReadBufferBytes == 16 * 1024, "bulk read buffer must be 16 KiB")
        expect(AOA.maxConsecutiveEmptyReads == 64, "consecutive empty ZLP bound must be 64")

        // USB 2.0 High-Speed (512-byte max packet) and USB 3.x SuperSpeed (1024-byte max packet)
        for maxPacket in [512, 1024] {
            expect(!AOA.needsZeroLengthPacket(byteCount: 0, maxPacketSize: maxPacket),
                   "0-byte write must not emit an extra ZLP")
            expect(!AOA.needsZeroLengthPacket(byteCount: maxPacket - 1, maxPacketSize: maxPacket),
                   "short USB packet terminates transfer without ZLP")
            expect(AOA.needsZeroLengthPacket(byteCount: maxPacket, maxPacketSize: maxPacket),
                   "single full packet < 16 KiB must emit ZLP so f_accessory completes its 16 KiB URB")
            expect(AOA.needsZeroLengthPacket(byteCount: maxPacket * 3, maxPacketSize: maxPacket),
                   "packet-aligned write < 16 KiB must emit ZLP")
            expect(!AOA.needsZeroLengthPacket(byteCount: 16 * 1024, maxPacketSize: maxPacket),
                   "exact 16 KiB URB fills Android request completely and must not send trailing ZLP")
            expect(!AOA.needsZeroLengthPacket(byteCount: 32 * 1024, maxPacketSize: maxPacket),
                   "exact multiple of 16 KiB URBs must not send trailing ZLP")
            expect(AOA.needsZeroLengthPacket(byteCount: 16 * 1024 + maxPacket, maxPacketSize: maxPacket),
                   "multi-URB write ending on packet boundary without filling second 16 KiB URB must emit ZLP")
            expect(!AOA.needsZeroLengthPacket(byteCount: 16 * 1024 + 137, maxPacketSize: maxPacket),
                   "multi-URB write ending on short packet must not emit ZLP")
        }
    }

    private static func testDeterministicAdbVsAoaArbitration() {
        // 1. ADB online (.device) wins over AOA for the same serial (never fight adb).
        let adbOnline = [AndroidWiredAdbCandidate(serial: "SER_A", state: .device, model: "Pixel 9")]
        let aoaSame = [AndroidWiredAccessoryCandidate(serial: "SER_A", name: "Pixel 9", busy: true)]
        expect(AndroidWiredArbitrationPolicy.arbitrate(adbCandidates: adbOnline, accessoryCandidates: aoaSame)
               == [.preferAdb(serial: "SER_A", model: "Pixel 9")],
               "online ADB device must deterministically win over AOA")

        // 2. When ADB is absent or USB debugging is off, AOA is selected.
        let aoaReady = [AndroidWiredAccessoryCandidate(serial: "SER_B", name: "Galaxy Tab S9", busy: false)]
        expect(AndroidWiredArbitrationPolicy.arbitrate(adbCandidates: [], accessoryCandidates: aoaReady)
               == [.useAccessory(serial: "SER_B", name: "Galaxy Tab S9")],
               "AOA must be used when ADB does not claim the serial")

        // 3. Mixed multi-device: SER_A on ADB (.device), SER_B on AOA (zero-ADB), SER_C unauthorized in ADB.
        let adbMixed = [
            AndroidWiredAdbCandidate(serial: "SER_A", state: .device, model: "Pixel 9"),
            AndroidWiredAdbCandidate(serial: "SER_C", state: .unauthorized, model: "Xiaomi Pad"),
        ]
        let aoaMixed = [
            AndroidWiredAccessoryCandidate(serial: "SER_B", name: "Galaxy Tab S9", busy: false),
            AndroidWiredAccessoryCandidate(serial: "SER_C", name: "Xiaomi Pad", busy: true),
        ]
        expect(AndroidWiredArbitrationPolicy.arbitrate(adbCandidates: adbMixed, accessoryCandidates: aoaMixed) == [
            .preferAdb(serial: "SER_A", model: "Pixel 9"),
            .blockedByExclusiveOwner(serial: "SER_C", name: "Xiaomi Pad", adbState: .unauthorized),
            .useAccessory(serial: "SER_B", name: "Galaxy Tab S9"),
        ], "multi-device arbitration must isolate per-serial state deterministically")

        // 4. Auto-connect policy: unpaired charging phone without invitation does not auto-switch to AOA;
        //    paired peer or imported invitation enables zero-ADB plug-and-play.
        expect(!AndroidWiredArbitrationPolicy.shouldAutoConnectAccessory(
            mode: .auto,
            sessionID: "usb:aoa:SER_B",
            knownInstallID: nil,
            trustedPeerIDs: ["PEER_1"],
            importedInvitationID: nil,
            allowLegacySender: false,
            disabledSessionIDs: []
        ), "unknown unpaired phone without invitation should not auto-enter accessory mode")

        expect(AndroidWiredArbitrationPolicy.shouldAutoConnectAccessory(
            mode: .auto,
            sessionID: "usb:aoa:SER_B",
            knownInstallID: nil,
            trustedPeerIDs: [],
            importedInvitationID: "INVITED_PEER",
            allowLegacySender: false,
            disabledSessionIDs: []
        ), "imported pairing invitation should enable zero-ADB plug-and-play on attach")

        expect(AndroidWiredArbitrationPolicy.shouldAutoConnectAccessory(
            mode: .usb,
            sessionID: "usb:aoa:SER_B",
            knownInstallID: "PEER_1",
            trustedPeerIDs: ["PEER_1"],
            importedInvitationID: nil,
            allowLegacySender: false,
            disabledSessionIDs: []
        ), "previously paired Android install ID should auto-connect on USB attach")

        expect(!AndroidWiredArbitrationPolicy.shouldAutoConnectAccessory(
            mode: .wifi,
            sessionID: "usb:aoa:SER_B",
            knownInstallID: "PEER_1",
            trustedPeerIDs: ["PEER_1"],
            importedInvitationID: nil,
            allowLegacySender: false,
            disabledSessionIDs: []
        ), "Wi-Fi-only transport mode must not auto-connect USB accessory")
    }

    private static func testMutualTLSRelayOverSimulatedAccessoryStream() throws {
        let queue = DispatchQueue(label: "test.aoa.tls")
        let senderIdentity = try AppleTransportIdentity.ephemeral()
        let receiverIdentity = try AppleTransportIdentity.ephemeral()
        let senderPairing = try SecurePairingState(
            localID: "11111111-1111-4111-8111-111111111111",
            localFingerprint: senderIdentity.fingerprint,
            persisted: nil,
            persist: { _ in })
        let receiverPairing = try SecurePairingState(
            localID: "22222222-2222-4222-8222-222222222222",
            localFingerprint: receiverIdentity.fingerprint,
            persisted: nil,
            persist: { _ in })

        let invitation = try receiverPairing.startPairing()
        let senderPlan = try AppleSenderSecurityPlan.resolve(
            identity: senderIdentity,
            pairing: senderPairing,
            receiverID: nil,
            advertisedTLS: false,
            name: "Pixel 8",
            invitation: invitation,
            allowLegacy: false)
        expect(senderPlan.encrypted, "AOA sender security plan must require TLS by default")

        // Simulate the raw byte-stream loopback pipe returned by AOA.dial, and
        // wrap the Android side with TLS server + AppleSecureAdmissionPool.
        let pipe = try LoopbackAccessoryPipe(queue: queue)
        defer { pipe.stop() }

        let serverAuthenticated = DispatchSemaphore(value: 0)
        let clientAuthenticated = DispatchSemaphore(value: 0)
        let helloDelivered = DispatchSemaphore(value: 0)
        var serverConnBox: NWConnection?
        let admissionPool = AppleSecureAdmissionPool(queue: queue, timeout: 4)
        var receivedHelloPayload: Data?

        // Create a TLS server listener representing the Android receiver side
        // behind the simulated AOA bulk pipe.
        let serverTLS = try AppleTLS.options(
            identity: receiverIdentity,
            peerIsServer: false,
            queue: queue,
            acceptedFingerprint: { receiverPairing.acceptsTLS($0) })
        let serverTCP = NWProtocolTCP.Options()
        serverTCP.noDelay = true
        let serverParams = NWParameters(tls: serverTLS, tcp: serverTCP)
        let tlsServer = try NWListener(using: serverParams, on: .any)
        defer { queue.sync { admissionPool.cancelAll(); tlsServer.cancel() } }

        let tlsServerReady = DispatchSemaphore(value: 0)
        var tlsServerPort: UInt16 = 0
        tlsServer.newConnectionHandler = { (conn: NWConnection) in
            serverConnBox = conn
            admissionPool.accept(conn, pairing: receiverPairing) { result in
                if case .success = result {
                    let hello = #"{"type":"hello","id":"22222222-2222-4222-8222-222222222222","pixelsWide":2400,"pixelsHigh":1080,"scale":2,"device":"Android","security":true}"#.data(using: .utf8)!
                    var len = UInt32(hello.count).bigEndian
                    var framed = Data(bytes: &len, count: 4)
                    framed.append(hello)
                    conn.send(content: framed, completion: .contentProcessed { _ in })
                    serverAuthenticated.signal()
                }
            }
        }
        tlsServer.stateUpdateHandler = { (state: NWListener.State) in
            if case .ready = state, let port = tlsServer.port?.rawValue {
                tlsServerPort = port
                tlsServerReady.signal()
            }
        }
        tlsServer.start(queue: queue)
        expect(tlsServerReady.wait(timeout: .now() + 5) == .success, "TLS server listener failed to start")

        // Bridge raw AOA pipe -> TLS server (simulating bulk IN/OUT pipe bridge).
        var bridgeBackends: [NWConnection] = []
        pipe.onAccepted = { rawAccepted in
            let backendTCP = NWProtocolTCP.Options()
            backendTCP.noDelay = true
            let backend = NWConnection(
                to: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: tlsServerPort)!),
                using: NWParameters(tls: nil, tcp: backendTCP))
            bridgeBackends.append(backend)
            rawAccepted.start(queue: queue)
            backend.start(queue: queue)
            func pump(_ from: NWConnection, _ to: NWConnection) {
                from.receive(minimumIncompleteLength: 1, maximumLength: AOA.bulkReadBufferBytes) { data, _, ended, err in
                    if let data, !data.isEmpty {
                        to.send(content: data, completion: .contentProcessed { sendErr in
                            if sendErr != nil || ended || err != nil {
                                from.cancel(); to.cancel()
                            } else {
                                pump(from, to)
                            }
                        })
                    } else if ended || err != nil {
                        from.cancel(); to.cancel()
                    }
                }
            }
            pump(rawAccepted, backend)
            pump(backend, rawAccepted)
        }
        let aoaPort = try pipe.start()
        defer { bridgeBackends.forEach { $0.cancel() }; serverConnBox?.cancel() }

        // Connect raw tunnel (as AOA.dial returns) and wrap with UsbmuxTLSRelay + AppleTLS client!
        let rawTunnel = NWConnection(
            to: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: aoaPort)!),
            using: .tcp)
        let tunnelReady = DispatchSemaphore(value: 0)
        rawTunnel.stateUpdateHandler = { state in
            if case .ready = state { tunnelReady.signal() }
        }
        rawTunnel.start(queue: queue)
        expect(tunnelReady.wait(timeout: .now() + 5) == .success, "raw AOA tunnel failed to connect")

        let relay = UsbmuxTLSRelay(tunnel: rawTunnel, queue: queue)
        defer { queue.sync { relay.stop() } }
        let relayStarted = DispatchSemaphore(value: 0)
        var relayPort: UInt16 = 0
        queue.async {
            relay.start { result in
                if case .success(let port) = result {
                    relayPort = port
                    relayStarted.signal()
                }
            }
        }
        expect(relayStarted.wait(timeout: .now() + 5) == .success, "UsbmuxTLSRelay failed to start over AOA tunnel")

        let clientPlan = try senderPlan.admission(localName: "Test Mac")
        let clientTLS = try AppleTLS.options(
            identity: senderIdentity,
            peerIsServer: true,
            queue: queue,
            acceptedFingerprint: { $0 == clientPlan.fingerprint })
        let clientTCP = NWProtocolTCP.Options()
        clientTCP.noDelay = true
        let tlsClient = NWConnection(
            to: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: relayPort)!),
            using: NWParameters(tls: clientTLS, tcp: clientTCP))
        defer { tlsClient.cancel() }

        var clientAdmissionBox: AppleSecureAdmission?
        queue.async {
            let admission = AppleSecureAdmission(connection: tlsClient, queue: queue) { result in
                if case .success = result {
                    senderPlan.didAuthenticate()
                    tlsClient.receive(minimumIncompleteLength: 4, maximumLength: 4) { hdr, _, _, _ in
                        guard let hdr, hdr.count == 4 else { return }
                        let length = hdr.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                        tlsClient.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { body, _, _, _ in
                            receivedHelloPayload = body
                            helloDelivered.signal()
                        }
                    }
                    clientAuthenticated.signal()
                }
            }
            clientAdmissionBox = admission
            admission.startClient(clientPlan)
        }
        expect(serverAuthenticated.wait(timeout: .now() + 5) == .success,
               "AOA TLS server should authenticate DWA1 request")
        expect(clientAuthenticated.wait(timeout: .now() + 5) == .success,
               "AOA TLS client should verify DWR1 response and pin receiver")
        expect(helloDelivered.wait(timeout: .now() + 5) == .success,
               "encrypted hello frame should arrive intact over UsbmuxTLSRelay + AOA pipe")
        withExtendedLifetime(clientAdmissionBox) {}
        expect(senderPlan.permitsHello(id: "22222222-2222-4222-8222-222222222222"),
               "authenticated AOA security plan should permit matching hello install ID")
        expect(!senderPlan.permitsHello(id: "33333333-3333-4333-8333-333333333333"),
               "authenticated AOA security plan must reject mismatched hello install ID")
        expect(receivedHelloPayload != nil, "decrypted hello payload must be non-empty")
    }
}
