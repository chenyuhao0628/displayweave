package app.opendisplay.android.update;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import javax.net.ssl.SSLHandshakeException;

final class UpdateClientSelfTest {
    static void run(String validManifest) throws Exception {
        FakeOpener opener = new FakeOpener();
        opener.responses.add(new Response(200, validManifest));
        new UpdateClient(opener).fetchLatestManifest(42);
        expect(opener.urls.size() == 1, "healthy primary needs only one request");
        expect(opener.urls.get(0).toString().equals(
                "https://downloads.urlget.cyou/displayweave/android-update.json?displayweave_cache_bust=42"),
                "new clients use migrated feed with cache busting");

        for (int status : new int[]{404, 410, 408, 429, 500, 503}) {
            opener = new FakeOpener();
            opener.responses.add(new Response(status, ""));
            opener.responses.add(new Response(200, validManifest));
            new UpdateClient(opener).fetchLatestManifest(43);
            expect(opener.urls.size() == 2, "unavailable feed falls back exactly once");
            expect(opener.urls.get(1).getHost().equals("chenyuhao0628.github.io"),
                    "fallback is pinned to historical feed");
            expect(opener.disconnected == 2, "every connection is released");
        }
        for (Response invalid : new Response[]{new Response(403, ""),
                new Response(200, "{}"), new Response(200, "x".repeat(1024 * 1024 + 1))}) {
            opener = new FakeOpener();
            opener.responses.add(invalid);
            expectFailure(new UpdateClient(opener));
            expect(opener.urls.size() == 1, "rejected metadata never falls back");
            expect(opener.disconnected == 1, "rejected metadata releases connection");
        }
        opener = new FakeOpener();
        opener.responses.add(new Response(503, ""));
        opener.responses.add(new Response(503, ""));
        expectFailure(new UpdateClient(opener));
        expect(opener.urls.size() == 2, "fallback exhaustion is bounded");
        final int[] attempts = {0};
        expectFailure(new UpdateClient(url -> {
            attempts[0]++;
            throw new SSLHandshakeException("untrusted certificate");
        }));
        expect(attempts[0] == 1, "TLS trust failures do not trigger fallback");
        System.out.println("UpdateClientSelfTest PASS");
    }

    private static void expectFailure(UpdateClient client) throws Exception {
        try { client.fetchLatestManifest(44); throw new AssertionError("expected failure"); }
        catch (IOException expected) { }
    }
    private static void expect(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }
    private record Response(int status, String body) { }
    private static final class FakeOpener implements UpdateClient.ConnectionOpener {
        final ArrayDeque<Response> responses = new ArrayDeque<>();
        final List<URL> urls = new ArrayList<>();
        int disconnected;
        public HttpURLConnection open(URL url) {
            urls.add(url);
            Response response = responses.removeFirst();
            return new HttpURLConnection(url) {
                public void connect() { }
                public void disconnect() { disconnected++; }
                public boolean usingProxy() { return false; }
                public int getResponseCode() { return response.status(); }
                public long getContentLengthLong() {
                    return response.body().getBytes(StandardCharsets.UTF_8).length;
                }
                public InputStream getInputStream() {
                    return new ByteArrayInputStream(response.body().getBytes(StandardCharsets.UTF_8));
                }
            };
        }
    }
}
