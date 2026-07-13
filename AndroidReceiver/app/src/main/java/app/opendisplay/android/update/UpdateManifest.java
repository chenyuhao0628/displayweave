package app.opendisplay.android.update;

import java.net.URI;
import java.time.Instant;
import java.time.format.DateTimeParseException;
import java.util.LinkedHashMap;
import java.util.Map;

public final class UpdateManifest {
    public static final int CURRENT_SCHEMA_VERSION = 1;
    public static final String EXPECTED_PACKAGE_NAME = "app.opendisplay.android";
    public static final String EXPECTED_SIGNING_CERTIFICATE_SHA256 =
            "89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d";
    public static final String EXPECTED_RELEASE_PATH_PREFIX =
            "/chenyuhao0628/displayweave/releases/download/";
    public static final int MINIMUM_SUPPORTED_SDK = 26;

    public final int schemaVersion;
    public final String packageName;
    public final long versionCode;
    public final String versionName;
    public final int minimumSdk;
    public final URI apkUrl;
    public final long apkSize;
    public final String sha256;
    public final String signingCertificateSha256;
    public final Instant publishedAt;
    public final URI releaseNotesUrl;

    private UpdateManifest(Map<String, Object> values) {
        schemaVersion = integer(values, "schemaVersion");
        packageName = string(values, "packageName");
        versionCode = number(values, "versionCode");
        versionName = string(values, "versionName");
        minimumSdk = integer(values, "minimumSdk");
        apkUrl = uri(values, "apkUrl");
        apkSize = number(values, "apkSize");
        sha256 = UpdatePolicy.normalizeHex(string(values, "sha256"));
        signingCertificateSha256 = UpdatePolicy.normalizeHex(
                string(values, "signingCertificateSha256"));
        publishedAt = instant(values, "publishedAt");
        releaseNotesUrl = uri(values, "releaseNotesUrl");
        validate();
    }

    public static UpdateManifest parse(String json) {
        return new UpdateManifest(FlatJsonParser.parse(json));
    }

    private void validate() {
        require(schemaVersion == CURRENT_SCHEMA_VERSION, "Unsupported update schema");
        require(EXPECTED_PACKAGE_NAME.equals(packageName), "Unexpected Android package");
        require(versionCode > 0, "Invalid version code");
        require(!versionName.isBlank(), "Missing version name");
        require(minimumSdk >= MINIMUM_SUPPORTED_SDK, "Unsupported minimum SDK");
        require(apkSize > 0, "Invalid APK size");
        validateHttps(apkUrl, "APK URL");
        require("github.com".equalsIgnoreCase(apkUrl.getHost()), "Unexpected APK host");
        require(apkUrl.getPath() != null
                        && apkUrl.getPath().startsWith(EXPECTED_RELEASE_PATH_PREFIX)
                        && apkUrl.getPath().endsWith("/DisplayWeave-Android.apk"),
                "Unexpected APK filename");
        require(EXPECTED_SIGNING_CERTIFICATE_SHA256.equals(signingCertificateSha256),
                "Unexpected APK signing certificate");
        validateHttps(releaseNotesUrl, "release notes URL");
    }

    private static void validateHttps(URI uri, String label) {
        require("https".equalsIgnoreCase(uri.getScheme()) && uri.getHost() != null,
                "Invalid " + label);
    }

    private static String string(Map<String, Object> values, String key) {
        Object value = values.get(key);
        if (!(value instanceof String)) {
            throw new IllegalArgumentException("Missing string field: " + key);
        }
        return (String) value;
    }

    private static long number(Map<String, Object> values, String key) {
        Object value = values.get(key);
        if (!(value instanceof Long)) {
            throw new IllegalArgumentException("Missing integer field: " + key);
        }
        return (Long) value;
    }

    private static int integer(Map<String, Object> values, String key) {
        long value = number(values, key);
        if (value < Integer.MIN_VALUE || value > Integer.MAX_VALUE) {
            throw new IllegalArgumentException("Integer field out of range: " + key);
        }
        return (int) value;
    }

    private static URI uri(Map<String, Object> values, String key) {
        try {
            return URI.create(string(values, key));
        } catch (IllegalArgumentException error) {
            throw new IllegalArgumentException("Invalid URI field: " + key, error);
        }
    }

    private static Instant instant(Map<String, Object> values, String key) {
        try {
            return Instant.parse(string(values, key));
        } catch (DateTimeParseException error) {
            throw new IllegalArgumentException("Invalid timestamp field: " + key, error);
        }
    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new IllegalArgumentException(message);
        }
    }

    /** Minimal strict parser for the flat, signed-by-HTTPS update feed schema. */
    private static final class FlatJsonParser {
        private final String input;
        private int index;

        private FlatJsonParser(String input) {
            this.input = input == null ? "" : input;
        }

        static Map<String, Object> parse(String input) {
            FlatJsonParser parser = new FlatJsonParser(input);
            Map<String, Object> result = parser.object();
            parser.space();
            if (parser.index != parser.input.length()) {
                throw parser.error("Trailing JSON content");
            }
            return result;
        }

        private Map<String, Object> object() {
            expect('{');
            Map<String, Object> result = new LinkedHashMap<>();
            space();
            if (take('}')) return result;
            while (true) {
                String key = string();
                space();
                expect(':');
                space();
                Object value = peek() == '"' ? string() : integer();
                if (result.put(key, value) != null) {
                    throw error("Duplicate JSON key: " + key);
                }
                space();
                if (take('}')) return result;
                expect(',');
                space();
            }
        }

        private String string() {
            expect('"');
            StringBuilder value = new StringBuilder();
            while (index < input.length()) {
                char character = input.charAt(index++);
                if (character == '"') return value.toString();
                if (character == '\\') {
                    if (index >= input.length()) throw error("Incomplete JSON escape");
                    char escape = input.charAt(index++);
                    switch (escape) {
                        case '"': case '\\': case '/': value.append(escape); break;
                        case 'b': value.append('\b'); break;
                        case 'f': value.append('\f'); break;
                        case 'n': value.append('\n'); break;
                        case 'r': value.append('\r'); break;
                        case 't': value.append('\t'); break;
                        case 'u': value.append(unicode()); break;
                        default: throw error("Invalid JSON escape");
                    }
                } else {
                    if (character < 0x20) throw error("Control character in JSON string");
                    value.append(character);
                }
            }
            throw error("Unterminated JSON string");
        }

        private char unicode() {
            if (index + 4 > input.length()) throw error("Incomplete Unicode escape");
            try {
                char value = (char) Integer.parseInt(input.substring(index, index + 4), 16);
                index += 4;
                return value;
            } catch (NumberFormatException error) {
                throw error("Invalid Unicode escape");
            }
        }

        private Long integer() {
            int start = index;
            if (take('-')) { /* included below */ }
            int digits = index;
            while (index < input.length() && Character.isDigit(input.charAt(index))) index++;
            if (digits == index) throw error("Expected JSON integer");
            try {
                return Long.parseLong(input.substring(start, index));
            } catch (NumberFormatException error) {
                throw error("Invalid JSON integer");
            }
        }

        private void space() {
            while (index < input.length() && Character.isWhitespace(input.charAt(index))) index++;
        }

        private char peek() {
            if (index >= input.length()) throw error("Unexpected end of JSON");
            return input.charAt(index);
        }

        private boolean take(char expected) {
            if (index < input.length() && input.charAt(index) == expected) {
                index++;
                return true;
            }
            return false;
        }

        private void expect(char expected) {
            if (!take(expected)) throw error("Expected '" + expected + "'");
        }

        private IllegalArgumentException error(String message) {
            return new IllegalArgumentException(message + " at offset " + index);
        }
    }
}
