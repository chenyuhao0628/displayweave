package app.opendisplay.android.update;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import javax.net.ssl.SSLException;

public final class UpdateClient {
    private static final int CONNECT_TIMEOUT_MILLIS = 10_000;
    private static final int READ_TIMEOUT_MILLIS = 30_000;
    private static final int MAX_REDIRECTS = 5;
    private static final int MAX_MANIFEST_BYTES = 1024 * 1024;
    private static final String PRIMARY_FEED =
            "https://downloads.urlget.cyou/displayweave/android-update.json";
    private static final String FALLBACK_FEED =
            "https://chenyuhao0628.github.io/displayweave/android-update.json";

    interface ConnectionOpener {
        HttpURLConnection open(URL url) throws IOException;
    }
    private final ConnectionOpener opener;

    public UpdateClient() {
        this(url -> (HttpURLConnection) url.openConnection());
    }

    UpdateClient(ConnectionOpener opener) {
        this.opener = opener;
    }

    public UpdateManifest fetchLatestManifest(long nowMillis) throws IOException {
        String query = "?displayweave_cache_bust=" + nowMillis;
        try {
            return fetchManifest(new URL(PRIMARY_FEED + query));
        } catch (MirrorUnavailableException primaryError) {
            try {
                return fetchManifest(new URL(FALLBACK_FEED + query));
            } catch (IOException fallbackError) {
                fallbackError.addSuppressed(primaryError);
                throw fallbackError;
            }
        }
    }

    public interface Progress {
        void onProgress(long downloadedBytes, long totalBytes);
    }

    public static final class MirrorUnavailableException extends IOException {
        MirrorUnavailableException(String message, Throwable cause) {
            super(message, cause);
        }

        MirrorUnavailableException(String message) {
            super(message);
        }
    }

    private static final class ArtifactRejectedException extends IOException {
        ArtifactRejectedException(String message) {
            super(message);
        }
    }

    public UpdateManifest fetchManifest(URL url) throws IOException {
        HttpURLConnection connection;
        try {
            connection = open(url, true);
        } catch (IOException error) {
            throw unavailable("Unable to reach update feed", error);
        }
        try {
            int status = connection.getResponseCode();
            if (status == 404 || status == 410 || status == 408 || status == 429
                    || (status >= 500 && status <= 599)) {
                throw new MirrorUnavailableException("Update feed returned HTTP " + status);
            }
            if (status < 200 || status >= 300) {
                throw new ArtifactRejectedException("Update feed rejected: HTTP " + status);
            }
            long length = connection.getContentLengthLong();
            if (length > MAX_MANIFEST_BYTES) {
                throw new ArtifactRejectedException("Update manifest exceeds size limit");
            }
            try (InputStream input = connection.getInputStream();
                 ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                copyBounded(input, output, MAX_MANIFEST_BYTES, null, length);
                try {
                    return UpdateManifest.parse(new String(output.toByteArray(), StandardCharsets.UTF_8));
                } catch (IllegalArgumentException error) {
                    throw new ArtifactRejectedException("Invalid update manifest: " + error.getMessage());
                }
            }
        } catch (IOException error) {
            throw unavailable("Unable to read update feed", error);
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

        HttpURLConnection connection;
        try {
            connection = open(url, false);
        } catch (IOException error) {
            throw unavailable("Unable to connect to update mirror", error);
        }
        boolean completed = false;
        try {
            try {
                requireSuccess(connection);
            } catch (IOException error) {
                throw unavailable(error.getMessage(), error);
            }
            long contentLength = connection.getContentLengthLong();
            if (contentLength > expectedSize) {
                throw new ArtifactRejectedException("Update download exceeds declared size");
            }
            InputStream input;
            try {
                input = connection.getInputStream();
            } catch (IOException error) {
                throw unavailable("Update mirror response failed", error);
            }
            try (InputStream response = input;
                 FileOutputStream output = new FileOutputStream(destination)) {
                try {
                    copyBounded(response, output, expectedSize, progress, expectedSize);
                } catch (ArtifactRejectedException error) {
                    throw error;
                } catch (IOException error) {
                    throw unavailable("Update mirror download failed", error);
                }
                output.getFD().sync();
            }
            if (destination.length() != expectedSize) {
                throw new ArtifactRejectedException(
                        "Update download size does not match manifest");
            }
            completed = true;
        } finally {
            connection.disconnect();
            if (!completed && destination.exists() && !destination.delete()) {
                destination.deleteOnExit();
            }
        }
    }

    private static IOException unavailable(String message, IOException error) {
        // Certificate and policy failures are not availability failures.
        if (error instanceof SSLException || error instanceof ArtifactRejectedException) return error;
        if (error instanceof MirrorUnavailableException) {
            return (MirrorUnavailableException) error;
        }
        return new MirrorUnavailableException(message, error);
    }

    private HttpURLConnection open(URL initialUrl, boolean requireFreshResponse)
            throws IOException {
        URL url = initialUrl;
        for (int redirects = 0; redirects <= MAX_REDIRECTS; redirects++) {
            requireHttps(url);
            HttpURLConnection connection = opener.open(url);
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
            boolean returned = false;
            try {
                connection.connect();
                int status = connection.getResponseCode();
                if (status < 300 || status >= 400) {
                    returned = true;
                    return connection;
                }
                String location = connection.getHeaderField("Location");
                if (location == null) throw new ArtifactRejectedException("Update redirect is missing Location");
                URL redirected = new URL(url, location);
                if (requireFreshResponse && !initialUrl.getHost().equalsIgnoreCase(redirected.getHost())) {
                    throw new ArtifactRejectedException("Update feed redirect changes host");
                }
                url = redirected;
            } finally {
                if (!returned) connection.disconnect();
            }
        }
        throw new ArtifactRejectedException("Too many update redirects");
    }

    private static void requireHttps(URL url) throws IOException {
        if (!"https".equalsIgnoreCase(url.getProtocol())) {
            throw new ArtifactRejectedException("Update transport must use HTTPS");
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
            if (copied > maximum) {
                throw new ArtifactRejectedException("Update response exceeds size limit");
            }
            output.write(buffer, 0, count);
            if (progress != null) progress.onProgress(copied, total);
        }
    }
}
