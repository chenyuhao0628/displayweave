package app.opendisplay.android.update;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

public final class UpdateClient {
    private static final int CONNECT_TIMEOUT_MILLIS = 10_000;
    private static final int READ_TIMEOUT_MILLIS = 30_000;
    private static final int MAX_REDIRECTS = 5;
    private static final int MAX_MANIFEST_BYTES = 1024 * 1024;

    public interface Progress {
        void onProgress(long downloadedBytes, long totalBytes);
    }

    public UpdateManifest fetchManifest(URL url) throws IOException {
        HttpURLConnection connection = open(url, true);
        try {
            requireSuccess(connection);
            long length = connection.getContentLengthLong();
            if (length > MAX_MANIFEST_BYTES) {
                throw new IOException("Update manifest exceeds size limit");
            }
            try (InputStream input = connection.getInputStream();
                 ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                copyBounded(input, output, MAX_MANIFEST_BYTES, null, length);
                try {
                    return UpdateManifest.parse(output.toString(StandardCharsets.UTF_8));
                } catch (IllegalArgumentException error) {
                    throw new IOException("Invalid update manifest", error);
                }
            }
        } finally {
            connection.disconnect();
        }
    }

    public void download(URL url, File destination, long expectedSize, Progress progress)
            throws IOException {
        if (expectedSize <= 0L) throw new IOException("Invalid expected download size");
        if (!"DisplayWeave-update.apk.part".equals(destination.getName())) {
            throw new IOException("Update downloads must use the temporary APK filename");
        }
        File parent = destination.getParentFile();
        if (parent == null || (!parent.isDirectory() && !parent.mkdirs())) {
            throw new IOException("Unable to create update download directory");
        }

        HttpURLConnection connection = open(url, false);
        boolean completed = false;
        try {
            requireSuccess(connection);
            long contentLength = connection.getContentLengthLong();
            if (contentLength > expectedSize) {
                throw new IOException("Update download exceeds declared size");
            }
            try (InputStream input = connection.getInputStream();
                 FileOutputStream output = new FileOutputStream(destination)) {
                copyBounded(input, output, expectedSize, progress, expectedSize);
                output.getFD().sync();
            }
            if (destination.length() != expectedSize) {
                throw new IOException("Update download size does not match manifest");
            }
            completed = true;
        } finally {
            connection.disconnect();
            if (!completed && destination.exists() && !destination.delete()) {
                destination.deleteOnExit();
            }
        }
    }

    private static HttpURLConnection open(URL initialUrl, boolean requireFreshResponse)
            throws IOException {
        URL url = initialUrl;
        for (int redirects = 0; redirects <= MAX_REDIRECTS; redirects++) {
            requireHttps(url);
            HttpURLConnection connection = (HttpURLConnection) url.openConnection();
            connection.setConnectTimeout(CONNECT_TIMEOUT_MILLIS);
            connection.setReadTimeout(READ_TIMEOUT_MILLIS);
            connection.setInstanceFollowRedirects(false);
            if (requireFreshResponse) {
                connection.setUseCaches(false);
                connection.setDefaultUseCaches(false);
                connection.setRequestProperty("Cache-Control", "no-cache, no-store, max-age=0");
                connection.setRequestProperty("Pragma", "no-cache");
            }
            connection.setRequestProperty("Accept", "application/json, application/octet-stream");
            connection.connect();
            int status = connection.getResponseCode();
            if (status < 300 || status >= 400) return connection;
            String location = connection.getHeaderField("Location");
            connection.disconnect();
            if (location == null) throw new IOException("Update redirect is missing Location");
            url = new URL(url, location);
        }
        throw new IOException("Too many update redirects");
    }

    private static void requireHttps(URL url) throws IOException {
        if (!"https".equalsIgnoreCase(url.getProtocol())) {
            throw new IOException("Update transport must use HTTPS");
        }
    }

    private static void requireSuccess(HttpURLConnection connection) throws IOException {
        int status = connection.getResponseCode();
        if (status < 200 || status >= 300) {
            throw new IOException("Update server returned HTTP " + status);
        }
    }

    private static void copyBounded(
            InputStream input, java.io.OutputStream output, long maximum,
            Progress progress, long total) throws IOException {
        byte[] buffer = new byte[16 * 1024];
        long copied = 0L;
        int count;
        while ((count = input.read(buffer)) != -1) {
            copied += count;
            if (copied > maximum) throw new IOException("Update response exceeds size limit");
            output.write(buffer, 0, count);
            if (progress != null) progress.onProgress(copied, total);
        }
    }
}
