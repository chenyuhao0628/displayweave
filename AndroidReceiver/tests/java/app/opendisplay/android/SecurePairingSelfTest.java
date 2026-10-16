package app.opendisplay.android;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Properties;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;

final class SecurePairingSelfTest {
    interface Action { void run() throws Exception; }
    private static void reject(Action action) throws Exception {
        try { action.run(); throw new AssertionError("invalid pairing action accepted"); }
        catch (IOException expected) { }
    }
    private static void expect(boolean value) { if (!value) throw new AssertionError("pairing invariant"); }
    static void run() throws Exception {
        String pin = "01".repeat(32), clientPin = "ab".repeat(32);
        byte[] token = new byte[32]; for (int n = 0; n < token.length; n++) token[n] = (byte) n;
        SecurePairingProtocol.Invitation fixture = new SecurePairingProtocol.Invitation("receiver", pin, token);
        String invitation = fixture.encode();
        expect(SecurePairingProtocol.Invitation.decode(invitation).certificateSHA256.equals(pin));
        reject(() -> SecurePairingProtocol.Invitation.decode(invitation + "="));
        reject(() -> SecurePairingProtocol.Invitation.decode("DW1." + "a".repeat(2048)));
        byte[] wire = new SecurePairingProtocol.Auth("sender", "Test Mac", token).encode();
        expect(SecurePairingProtocol.Auth.decode(wire).installID.equals("sender"));
        for (int n = 0; n < wire.length; n++) {
            byte[] truncated = Arrays.copyOf(wire, n);
            reject(() -> SecurePairingProtocol.Auth.decode(truncated));
        }
        reject(() -> SecurePairingProtocol.Auth.decode(Arrays.copyOf(wire, wire.length + 1)));
        reject(() -> SecurePairingProtocol.Auth.decode("{\"type\":\"hello\"}".getBytes(StandardCharsets.UTF_8)));
        byte[] invalid = wire.clone(); invalid[4] = 2;
        reject(() -> SecurePairingProtocol.Auth.decode(invalid));
        reject(() -> new SecurePairingProtocol.Auth("", "", null).encode());
        reject(() -> new SecurePairingProtocol.Auth("sender", "bad\nname", null).encode());
        byte[] ready = SecurePairingProtocol.ready("receiver");
        expect(SecurePairingProtocol.readyIdentity(ready).equals("receiver"));
        Properties golden = new Properties();
        Path fixtures = null;
        for (String prefix : new String[]{"", "../", "../../"}) {
            Path candidate = Path.of(prefix + "tools/fixtures/secure-pairing-v1.properties");
            if (Files.exists(candidate)) { fixtures = candidate; break; }
        }
        if (fixtures == null) throw new AssertionError("secure golden vectors missing");
        try (java.io.InputStream input = Files.newInputStream(fixtures)) { golden.load(input); }
        expect(golden.getProperty("invitation").equals(invitation));
        expect(golden.getProperty("authHex").equals(SecurePairingProtocol.hex(wire)));
        expect(golden.getProperty("readyHex").equals(SecurePairingProtocol.hex(ready)));
        expect(SecurePairingProtocol.Invitation.decode(golden.getProperty("invitation")).receiverID.equals("receiver"));

        AtomicLong clock = new AtomicLong(100000);
        AtomicReference<byte[]> stored = new AtomicReference<>();
        AtomicBoolean failing = new AtomicBoolean();
        SecurePairingState state = new SecurePairingState("receiver", pin, null, clock::get, data -> {
            if (failing.get()) throw new IOException("fixture storage failure"); stored.set(data);
        });
        expect(!state.acceptsTLS(clientPin) && !state.hasPairingHistory("sender"));
        SecurePairingProtocol.Invitation invite = state.startPairing();
        expect(state.acceptsTLS(clientPin));
        SecurePairingProtocol.Auth auth = new SecurePairingProtocol.Auth("sender", "Test Mac", invite.token);
        failing.set(true); reject(() -> state.authenticate(auth, clientPin));
        expect(!state.hasPairingHistory("sender"));
        failing.set(false);
        state.authenticate(auth, clientPin);
        expect(!state.pairingOpen() && state.acceptsTLS(clientPin) && state.hasPairingHistory("sender"));
        state.authenticate(new SecurePairingProtocol.Auth("sender", "", null), clientPin);
        reject(() -> state.authenticate(auth, "cd".repeat(32)));
        reject(() -> state.authenticate(new SecurePairingProtocol.Auth("alias", "", invite.token), clientPin));
        state.revoke("sender");
        expect(!state.acceptsTLS(clientPin) && state.hasPairingHistory("sender"));
        reject(() -> state.authenticate(auth, clientPin));
        SecurePairingProtocol.Invitation repair = state.startPairing();
        state.authenticate(new SecurePairingProtocol.Auth("sender", "Test Mac", repair.token), clientPin);
        SecurePairingState restored = new SecurePairingState("receiver", pin, stored.get(), clock::get, ignored -> { });
        expect(restored.acceptsTLS(clientPin) && restored.hasPairingHistory("sender"));
        SecurePairingProtocol.Invitation expired = state.startPairing();
        clock.addAndGet(121000);
        expect(!state.pairingOpen());
        reject(() -> state.authenticate(new SecurePairingProtocol.Auth("unknown", "", expired.token), "cd".repeat(32)));
        state.startPairing();
        SecurePairingProtocol.Auth wrong = new SecurePairingProtocol.Auth("unknown", "", new byte[32]);
        for (int n = 0; n < 5; n++) reject(() -> state.authenticate(wrong, "cd".repeat(32)));
        expect(!state.pairingOpen());
        reject(() -> new SecurePairingState("receiver", pin, new byte[131073], clock::get, ignored -> { }));
        reject(() -> new SecurePairingState("receiver", pin, new byte[]{0}, clock::get, ignored -> { }));
        SecurePairingState full = new SecurePairingState("receiver", pin, null, clock::get, ignored -> { });
        for (int n = 1; n <= 128; n++) {
            SecurePairingProtocol.Invitation next = full.startPairing();
            full.authenticate(new SecurePairingProtocol.Auth("peer" + n, "Test", next.token),
                    String.format(java.util.Locale.ROOT, "%064x", n));
        }
        SecurePairingProtocol.Invitation overflow = full.startPairing();
        reject(() -> full.authenticate(new SecurePairingProtocol.Auth("overflow", "", overflow.token), clientPin));
        expect(full.peers().size() == 128);
        System.out.println("SecurePairingSelfTest PASS (shared Swift/Java golden vectors)");
    }
}
