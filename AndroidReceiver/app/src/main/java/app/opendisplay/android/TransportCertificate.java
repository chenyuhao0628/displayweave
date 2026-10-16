package app.opendisplay.android;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.SecureRandom;
import java.security.Signature;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.security.interfaces.ECPublicKey;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;

/** Local X.509 encoding only; JCA/Android Keystore performs every signature. */
public final class TransportCertificate {
    private TransportCertificate() { }
    public static X509Certificate create(PrivateKey privateKey, PublicKey publicKey) throws GeneralSecurityException {
        if (!(publicKey instanceof ECPublicKey) || ((ECPublicKey) publicKey).getParams().getCurve().getField().getFieldSize() != 256) {
            throw new GeneralSecurityException("transport identity requires P-256");
        }
        byte[] spki = publicKey.getEncoded();
        if (spki == null || spki.length > 256) throw new GeneralSecurityException("invalid transport public key");
        byte[] serial = new byte[16]; new SecureRandom().nextBytes(serial); serial[0] = (byte) ((serial[0] & 0x7f) | 1);
        byte[] algorithm = sequence(oid(0x2a, 0x86, 0x48, 0xce, 0x3d, 4, 3, 2));
        byte[] name = sequence(value(0x31, sequence(oid(0x55, 4, 3), value(0x0c, "DisplayWeave Transport".getBytes(StandardCharsets.UTF_8)))));
        byte[] basic = sequence(oid(0x55, 0x1d, 0x13), value(1, bytes(0xff)), value(4, sequence()));
        byte[] usage = sequence(oid(0x55, 0x1d, 0x0f), value(1, bytes(0xff)), value(4, value(3, bytes(7, 0x80))));
        byte[] extended = sequence(oid(0x55, 0x1d, 0x25), value(4, sequence(
                oid(0x2b, 6, 1, 5, 5, 7, 3, 1), oid(0x2b, 6, 1, 5, 5, 7, 3, 2))));
        long now = System.currentTimeMillis();
        byte[] tbs = sequence(value(0xa0, value(2, bytes(2))), value(2, serial), algorithm, name,
                sequence(time(new Date(now - 86400000L)), time(new Date(now + 365L * 86400000L))), name, spki,
                value(0xa3, sequence(basic, usage, extended)));
        Signature signer = Signature.getInstance("SHA256withECDSA");
        signer.initSign(privateKey); signer.update(tbs);
        byte[] cert = sequence(tbs, algorithm, value(3, concat(bytes(0), signer.sign())));
        X509Certificate result = (X509Certificate) CertificateFactory.getInstance("X.509")
                .generateCertificate(new ByteArrayInputStream(cert));
        result.verify(publicKey);
        return result;
    }
    private static byte[] bytes(int... values) { byte[] data = new byte[values.length]; for (int n = 0; n < values.length; n++) data[n] = (byte) values[n]; return data; }
    private static byte[] concat(byte[]... arrays) {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        for (byte[] array : arrays) output.write(array, 0, array.length);
        return output.toByteArray();
    }
    private static byte[] value(int tag, byte[] bytes) {
        ByteArrayOutputStream output = new ByteArrayOutputStream(); output.write(tag);
        if (bytes.length < 128) output.write(bytes.length);
        else if (bytes.length <= 255) { output.write(0x81); output.write(bytes.length); }
        else { output.write(0x82); output.write(bytes.length >> 8); output.write(bytes.length & 255); }
        output.write(bytes, 0, bytes.length); return output.toByteArray();
    }
    private static byte[] sequence(byte[]... data) { return value(0x30, concat(data)); }
    private static byte[] oid(int... values) { return value(6, bytes(values)); }
    private static byte[] time(Date date) {
        SimpleDateFormat year = new SimpleDateFormat("yyyy", Locale.ROOT); year.setTimeZone(TimeZone.getTimeZone("UTC"));
        boolean generalized = Integer.parseInt(year.format(date)) >= 2050;
        SimpleDateFormat format = new SimpleDateFormat(generalized ? "yyyyMMddHHmmss'Z'" : "yyMMddHHmmss'Z'", Locale.ROOT);
        format.setTimeZone(TimeZone.getTimeZone("UTC"));
        return value(generalized ? 0x18 : 0x17, format.format(date).getBytes(StandardCharsets.US_ASCII));
    }
}
